# frozen_string_literal: true

require "test_helper"

# Covers the OAuth `refresh_token` grant at POST /oauth/token.
#
# MCP clients (Claude Desktop/Code, Cursor) keep a long-running session alive
# by silently exchanging a refresh token for a fresh access token once the
# ~2h access token expires. If the refresh grant is unavailable the client is
# forced back through full re-authorization, dropping the connection.
#
# The /.well-known/oauth-authorization-server metadata already advertises
# `refresh_token` in grant_types_supported — these tests assert the server
# actually honors that claim.
class OauthRefreshTokenTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:onboarded_user)
    @team = @user.current_team
  end

  test "refresh_token grant issues a fresh access token and rotates the refresh token" do
    application = create(:platform_application, team: @team)
    token = Doorkeeper::AccessToken.create!(
      resource_owner_id: @user.id,
      application: application,
      scopes: "mcp:read mcp:write",
      use_refresh_token: true
    )
    assert token.refresh_token.present?, "setup: token must carry a refresh token"
    original_refresh = token.refresh_token
    original_access = token.token

    post "/oauth/token", params: {
      grant_type: "refresh_token",
      refresh_token: original_refresh,
      client_id: application.uid,
      client_secret: application.secret
    }

    assert_response :success
    body = JSON.parse(response.body)
    assert body["access_token"].present?, "response must include a new access token"
    refute_equal original_access, body["access_token"], "access token must be freshly minted"

    assert body["refresh_token"].present?, "response must include a rotated refresh token"
    refute_equal original_refresh, body["refresh_token"], "refresh token must rotate on use"
  end

  test "public (secret-less) dynamically-registered client can use the refresh_token grant" do
    # Simulates a Platform::Application registered via POST /oauth/register with
    # token_endpoint_auth_method: "none" + PKCE — the shape Claude uses. It has
    # no usable client secret, so the refresh must succeed on client_id alone.
    public_app = Platform::Application.create!(
      name: "Public MCP client",
      redirect_uri: "https://claude.ai/api/mcp/auth_callback",
      scopes: "mcp:read mcp:write",
      confidential: false,
      team: @team
    )
    token = Doorkeeper::AccessToken.create!(
      resource_owner_id: @user.id,
      application: public_app,
      scopes: "mcp:read mcp:write",
      use_refresh_token: true
    )
    original_refresh = token.refresh_token

    post "/oauth/token", params: {
      grant_type: "refresh_token",
      refresh_token: original_refresh,
      client_id: public_app.uid
      # no client_secret — public client
    }

    assert_response :success
    body = JSON.parse(response.body)
    assert body["access_token"].present?
    assert body["refresh_token"].present?
    refute_equal original_refresh, body["refresh_token"]
  end
end
