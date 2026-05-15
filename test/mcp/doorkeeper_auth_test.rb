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
  end
end
