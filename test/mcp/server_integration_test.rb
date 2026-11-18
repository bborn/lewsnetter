# frozen_string_literal: true

require "test_helper"

module Mcp
  class ServerIntegrationTest < ActionDispatch::IntegrationTest
    setup do
      @user = create(:onboarded_user)
      @team = @user.current_team
      @team.update!(slug: "test-team-slug") unless @team.slug?
      @platform_application = create(:platform_application, team: @team)
      @token = Doorkeeper::AccessToken.create!(
        resource_owner_id: @user.id,
        application: @platform_application,
        scopes: "read write delete",
        token: SecureRandom.hex
      )
    end

    def post_mcp(body)
      post "/mcp/messages",
        params: body.to_json,
        headers: {
          "Authorization" => "Bearer #{@token.token}",
          "Content-Type" => "application/json"
        }
    end

    test "401 without auth" do
      post "/mcp/messages", params: "{}", headers: {"Content-Type" => "application/json"}
      assert_response :unauthorized
      payload = JSON.parse(response.body)
      assert_equal(-32001, payload["error"]["code"])
    end

    test "initialize handshake returns server info" do
      post_mcp(jsonrpc: "2.0", id: 1, method: "initialize", params: {
        protocolVersion: "2025-06-18",
        capabilities: {},
        clientInfo: {name: "test", version: "0.0.1"}
      })
      assert_response :success
      payload = JSON.parse(response.body)
      assert_equal "2.0", payload["jsonrpc"]
      assert_equal 1, payload["id"]
      assert_equal "lewsnetter", payload.dig("result", "serverInfo", "name")
    end

    test "tools/list includes team_get_current" do
      post_mcp(jsonrpc: "2.0", id: 2, method: "tools/list")
      assert_response :success
      payload = JSON.parse(response.body)
      names = payload.dig("result", "tools").map { |t| t["name"] }
      assert_includes names, "team_get_current"
    end

    # MCP hosts decide what to confirm from these hints, so a read must say
    # it only reads, and a delete or a send must say it can't be undone.
    test "tools/list tells hosts which tools only read and which destroy or send" do
      post_mcp(jsonrpc: "2.0", id: 2, method: "tools/list")
      hints = JSON.parse(response.body).dig("result", "tools").to_h { |t| [t["name"], t["annotations"]] }

      assert_equal({"readOnlyHint" => true}, hints["subscribers_list"])
      assert_equal({"readOnlyHint" => false}, hints["subscribers_update"])
      %w[campaigns_delete subscribers_delete sequences_set_enabled sequences_update campaigns_send_now campaigns_schedule campaigns_resume_send].each do |name|
        assert_equal({"readOnlyHint" => false, "destructiveHint" => true}, hints[name], name)
      end
      assert hints.values.all?, "every tool should carry annotations"
    end

    test "tools/call team_get_current returns the calling team" do
      post_mcp(jsonrpc: "2.0", id: 3, method: "tools/call", params: {
        name: "team_get_current",
        arguments: {}
      })
      assert_response :success
      payload = JSON.parse(response.body)
      content = payload.dig("result", "content")
      refute_nil content, "Expected result.content in #{payload.inspect}"
      # FastMcp wraps non-content tool results as [{type:"text", text: <string>}].
      # Our wrapper JSON-encodes Hash returns so external clients can parse them.
      assert_equal 1, content.length
      text = content.first["text"]
      parsed = JSON.parse(text)
      assert_equal @team.id, parsed["id"]
      assert_equal @team.name, parsed["name"]
      assert_equal @team.slug, parsed["slug"]
    end

    # Regression: arguments came in as **symbol-keyed kwargs from FastMcp, but
    # tools look up arguments["id"] (string), so id was nil at the call site
    # and find_by!(id: nil) blew up with "id IS NULL" SQL. The wrapper now
    # transforms keys to strings before invoking. Don't let this slip again.
    test "tools/call passes arguments through with string keys (id arg reaches the tool)" do
      sub = @team.subscribers.create!(email: "alice@example.com", external_id: "ext-1", subscribed: true)
      post_mcp(jsonrpc: "2.0", id: 4, method: "tools/call", params: {
        name: "subscribers_get",
        arguments: {id: sub.id}
      })
      assert_response :success
      payload = JSON.parse(response.body)
      content = payload.dig("result", "content")
      refute_nil content, "Expected result.content in #{payload.inspect}"
      text = content.first["text"]
      parsed = JSON.parse(text)
      assert_equal sub.id, parsed.dig("subscriber", "id"),
        "Expected subscriber.id == #{sub.id}, got #{parsed.inspect}"
      assert_equal "alice@example.com", parsed.dig("subscriber", "email")
    end

    def tool_error_text(name, arguments)
      post_mcp(jsonrpc: "2.0", id: 5, method: "tools/call", params: {name: name, arguments: arguments})
      assert_response :success
      result = JSON.parse(response.body)["result"]
      assert_equal true, result["isError"]
      result.dig("content", 0, "text")
    end

    test "tools/call reports a missing record without SQL or a backtrace" do
      text = tool_error_text("subscribers_get", {id: 999_999})

      assert_equal "Subscriber not found", text
    end

    test "tools/call keeps validation and argument messages" do
      assert_equal "Validation failed: Name can't be blank", tool_error_text("segments_create", {name: ""})
      assert_match(/\AInvalid arguments: /, tool_error_text("subscribers_get", {id: "nope"}))
    end

    test "tools/call refuses a write tool to a read-only member and allows an admin" do
      member = create(:onboarded_user)
      create(:membership, team: @team, user: member)
      sub = @team.subscribers.create!(email: "keep@example.com", subscribed: true)
      admin_token = @token
      @token = Doorkeeper::AccessToken.create!(resource_owner_id: member.id, application: @platform_application,
        scopes: "read write delete", token: SecureRandom.hex)

      assert_equal Mcp::Tool::Base::NOT_ALLOWED, tool_error_text("subscribers_delete", {id: sub.id})
      assert Subscriber.exists?(sub.id)

      @token = admin_token
      post_mcp(jsonrpc: "2.0", id: 6, method: "tools/call", params: {name: "subscribers_delete", arguments: {id: sub.id}})
      assert_equal false, JSON.parse(response.body).dig("result", "isError")
      assert_not Subscriber.exists?(sub.id)
    end

    # FastMcp writes every response to every open SSE stream. Any token can
    # open one, so a stream must only carry results for the token's own
    # user and team.
    def open_sse(token, params = {})
      io = StringIO.new
      get "/mcp/sse", params: params, headers: {"Authorization" => "Bearer #{token.token}"},
        env: {"rack.hijack" => -> { io }, "rack.hijack_io" => io}
      (@sse_streams ||= []) << io
      io
    end

    def sse_results(io)
      io.string.scan(/^data: (\{.*\})$/).map { |(json)| JSON.parse(json) }.select { |message| message.key?("result") }
    end

    def other_team_token
      outsider = create(:onboarded_user)
      application = create(:platform_application, team: outsider.current_team)
      Doorkeeper::AccessToken.create!(resource_owner_id: outsider.id, application: application,
        scopes: "read write delete", token: SecureRandom.hex)
    end

    teardown { @sse_streams&.each(&:close) }

    test "another team's SSE stream does not receive this team's tool results" do
      outsider_stream = open_sse(other_team_token)

      post_mcp(jsonrpc: "2.0", id: 7, method: "tools/call", params: {name: "team_get_current", arguments: {}})

      assert_equal @team.name, JSON.parse(JSON.parse(response.body).dig("result", "content", 0, "text"))["name"]
      assert_empty sse_results(outsider_stream)
    end

    test "an SSE stream that reuses another team's client_id does not take over its results" do
      open_sse(@token, client_id: "shared-client")
      takeover = open_sse(other_team_token, client_id: "shared-client")

      post_mcp(jsonrpc: "2.0", id: 8, method: "tools/call", params: {name: "team_get_current", arguments: {}})

      assert_empty sse_results(takeover)
    end

    test "another member's SSE stream on the same team does not receive this caller's results" do
      member = create(:onboarded_user)
      create(:membership, team: @team, user: member)
      member_stream = open_sse(Doorkeeper::AccessToken.create!(resource_owner_id: member.id,
        application: @platform_application, scopes: "read", token: SecureRandom.hex))

      post_mcp(jsonrpc: "2.0", id: 10, method: "tools/call", params: {name: "team_get_current", arguments: {}})

      assert_empty sse_results(member_stream)
    end

    test "the caller's own SSE stream still receives its results" do
      own_stream = open_sse(@token)

      post_mcp(jsonrpc: "2.0", id: 9, method: "tools/call", params: {name: "team_get_current", arguments: {}})

      assert_equal [9], sse_results(own_stream).map { |message| message["id"] }
    end

    test "a dropped SSE stream does not break the caller's response" do
      dropped = open_sse(@token)
      def dropped.write(data) = data.start_with?("data: ") ? raise(Errno::EPIPE) : super

      post_mcp(jsonrpc: "2.0", id: 11, method: "tools/call", params: {name: "team_get_current", arguments: {}})

      assert_response :success
      assert_equal 11, JSON.parse(response.body)["id"]
    end

    test "tools/call hides the message of an unexpected error" do
      tool = Mcp::Tools::Team::GetCurrent
      original = tool.instance_method(:call)
      tool.define_method(:call) { |**| raise "boom at /srv/app/secret.rb" }

      text = tool_error_text("team_get_current", {})

      assert_equal "Tool failed. The error has been logged.", text
    ensure
      tool.define_method(:call, original)
    end
  end
end
