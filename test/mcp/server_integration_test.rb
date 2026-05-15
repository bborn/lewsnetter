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
  end
end
