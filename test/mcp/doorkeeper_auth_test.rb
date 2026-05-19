# frozen_string_literal: true

require "test_helper"

module Mcp
  class DoorkeeperAuthTest < ActiveSupport::TestCase
    setup do
      @user = create(:onboarded_user)
      @team = @user.current_team
      @app = create(:platform_application, team: @team)
      @token = Doorkeeper::AccessToken.create!(
        resource_owner_id: @user.id,
        application: @app,
        scopes: "read write delete",
        token: SecureRandom.hex
      )
      @inner = ->(env) { [200, {"content-type" => "application/json"}, [{ok: true, user_id: env["mcp.user"]&.id, team_id: env["mcp.team"]&.id}.to_json]] }
      @middleware = DoorkeeperAuth.new(@inner)
    end

    test "passes through with valid Bearer token" do
      env = Rack::MockRequest.env_for("/mcp", "HTTP_AUTHORIZATION" => "Bearer #{@token.token}", method: "POST")
      status, _headers, body = @middleware.call(env)
      assert_equal 200, status
      payload = JSON.parse(body.first)
      assert_equal @user.id, payload["user_id"]
      assert_equal @team.id, payload["team_id"]
    end

    test "returns 401 JSON-RPC error when no Authorization header" do
      env = Rack::MockRequest.env_for("/mcp", method: "POST")
      status, headers, body = @middleware.call(env)
      assert_equal 401, status
      assert_equal "application/json", headers["content-type"]
      payload = JSON.parse(body.first)
      assert_equal(-32001, payload["error"]["code"])
      assert_match(/missing bearer token/i, payload["error"]["message"])
    end

    test "returns 401 when token is unknown" do
      env = Rack::MockRequest.env_for("/mcp", "HTTP_AUTHORIZATION" => "Bearer not-a-real-token", method: "POST")
      status, _headers, body = @middleware.call(env)
      assert_equal 401, status
      payload = JSON.parse(body.first)
      assert_match(/invalid token/i, payload["error"]["message"])
    end

    test "returns 401 when token is revoked" do
      @token.revoke
      env = Rack::MockRequest.env_for("/mcp", "HTTP_AUTHORIZATION" => "Bearer #{@token.token}", method: "POST")
      status, _headers, _body = @middleware.call(env)
      assert_equal 401, status
    end

    test "401 includes WWW-Authenticate header pointing at protected-resource metadata" do
      env = Rack::MockRequest.env_for("/mcp", method: "POST")
      _status, headers, _body = @middleware.call(env)
      assert headers["www-authenticate"].present?, "Expected www-authenticate header"
      assert_match(/Bearer/, headers["www-authenticate"])
      assert_match(%r{/.well-known/oauth-protected-resource}, headers["www-authenticate"])
    end

    # ---- C2 regressions ---------------------------------------------------

    test "uses the token's application.team — NOT user.current_team — when user belongs to multiple teams" do
      # User is a member of both Team A and Team B. Token was minted for Team A.
      # User then "clicks around" Team B's web UI, which mutates
      # current_user.current_team_id to Team B. The MCP middleware must STILL
      # bind to Team A.
      other_team = create(:team)
      create(:membership, user: @user, team: other_team)
      @user.update!(current_team_id: other_team.id) # simulate UI flip

      env = Rack::MockRequest.env_for("/mcp", "HTTP_AUTHORIZATION" => "Bearer #{@token.token}", method: "POST")
      status, _headers, body = @middleware.call(env)
      assert_equal 200, status
      payload = JSON.parse(body.first)
      assert_equal @team.id, payload["team_id"], "MCP must scope to the token's bound team, not user.current_team"
      refute_equal other_team.id, payload["team_id"]
    end

    test "rejects with 401 when the token's application has no team binding (RFC 7591 dynamic client)" do
      # Simulates a Platform::Application created via /oauth/register — those
      # have no team_id at all. Tokens minted against them must NOT be usable
      # at the MCP boundary.
      orphan_app = Platform::Application.create!(
        name: "Orphan MCP client",
        redirect_uri: "urn:ietf:wg:oauth:2.0:oob",
        scopes: "mcp:read mcp:write",
        confidential: true
      )
      orphan_token = Doorkeeper::AccessToken.create!(
        resource_owner_id: @user.id,
        application: orphan_app,
        scopes: "mcp:read mcp:write",
        token: SecureRandom.hex
      )

      env = Rack::MockRequest.env_for("/mcp", "HTTP_AUTHORIZATION" => "Bearer #{orphan_token.token}", method: "POST")
      status, _headers, body = @middleware.call(env)
      assert_equal 401, status
      payload = JSON.parse(body.first)
      assert_match(/not bound to a team/i, payload["error"]["message"])
    end
  end
end
