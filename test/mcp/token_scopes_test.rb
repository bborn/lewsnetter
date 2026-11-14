# frozen_string_literal: true

require "test_helper"

module Mcp
  # The OAuth consent page promises that mcp:read only reads and that
  # changing data or sending needs mcp:write
  # (config/locales/en/doorkeeper.en.yml). These tests hold the MCP endpoint
  # to that promise without changing what older tokens can do.
  class TokenScopesTest < ActionDispatch::IntegrationTest
    # Tools that only read team data. Every other tool needs a token that may
    # write, so a new tool is closed to read-only tokens until it opts in.
    READ_ONLY_TOOLS = %w[
      campaigns_get campaigns_list campaigns_postmortem
      email_templates_get email_templates_list email_templates_render_preview
      events_list_for_subscriber
      llm_analyze_send llm_draft_campaign
      segments_count_matching segments_get segments_list segments_sample_matching
      sender_addresses_get sender_addresses_list
      sequences_list sequences_stats
      subscribers_count subscribers_find_by_external_id subscribers_get subscribers_list
      team_custom_attribute_schema team_get_current team_list_companies
    ].freeze

    setup do
      @user = create(:onboarded_user)
      @team = @user.current_team
      @application = create(:platform_application, team: @team)
      @campaign = @team.campaigns.create!(subject: "Draft", status: "draft", body_markdown: "Hello")
    end

    test "a read-only token can call read tools" do
      result = call_tool(token("mcp:read"), "campaigns_get", id: @campaign.id)

      assert_nil result["error"]
      assert_equal @campaign.id, JSON.parse(result.dig("result", "content", 0, "text")).dig("campaign", "id")
    end

    test "a read-only token cannot delete a campaign" do
      result = call_tool(token("mcp:read"), "campaigns_delete", id: @campaign.id)

      assert_equal(-32602, result.dig("error", "code"))
      assert_equal "Unauthorized", result.dig("error", "message")
      assert Campaign.exists?(@campaign.id), "a read-only token must not delete"
    end

    test "a read-only token cannot send a test email" do
      # SesSender records a Delivery for every attempt, stub mode included.
      assert_no_difference -> { Delivery.count } do
        result = call_tool(token("mcp:read"), "campaigns_send_test", id: @campaign.id)
        assert_equal "Unauthorized", result.dig("error", "message")
      end
    end

    test "mcp:write lets a token change data" do
      result = call_tool(token("mcp:read mcp:write"), "campaigns_delete", id: @campaign.id)

      assert_nil result["error"]
      refute Campaign.exists?(@campaign.id)
    end

    test "tokens without mcp scopes keep full access" do
      ["read write delete", "admin", ""].each do |scopes|
        campaign = @team.campaigns.create!(subject: "Legacy #{scopes}", status: "draft", body_markdown: "Hello")
        result = call_tool(token(scopes), "campaigns_delete", id: campaign.id)

        assert_nil result["error"], "scopes #{scopes.inspect}: #{result.inspect}"
        refute Campaign.exists?(campaign.id), "scopes #{scopes.inspect} lost write access"
      end
    end

    test "admin alongside mcp:read still writes, as the consent page says" do
      result = call_tool(token("admin mcp:read"), "campaigns_delete", id: @campaign.id)

      assert_nil result["error"]
      refute Campaign.exists?(@campaign.id)
    end

    test "every tool declares whether it is read-only" do
      declared = Mcp::Tool::Loader.load_all.select(&:read_only?).map(&:tool_name).sort

      assert_equal READ_ONLY_TOOLS.sort, declared
    end

    test "the in-app agent context has no token and may call every tool" do
      ctx = Mcp::Tool::Context.new(user: @user, team: @team)

      assert Mcp::Tool::Loader.load_all.all? { ctx.may_call?(it) }
    end

    private

    def token(scopes)
      Doorkeeper::AccessToken.create!(
        resource_owner_id: @user.id,
        application: @application,
        scopes: scopes,
        token: SecureRandom.hex
      ).token
    end

    def call_tool(token, name, **arguments)
      post "/mcp/messages",
        params: {jsonrpc: "2.0", id: 1, method: "tools/call", params: {name: name, arguments: arguments}}.to_json,
        headers: {"Authorization" => "Bearer #{token}", "Content-Type" => "application/json"}
      assert_response :success
      JSON.parse(response.body)
    end
  end
end
