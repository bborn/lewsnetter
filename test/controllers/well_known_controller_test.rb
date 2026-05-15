# frozen_string_literal: true

require "test_helper"

class WellKnownControllerTest < ActionDispatch::IntegrationTest
  test "oauth-protected-resource returns the documented JSON shape" do
    get "/.well-known/oauth-protected-resource"
    assert_response :success
    body = JSON.parse(response.body)
    assert body["resource"].present?
    assert body["authorization_servers"].is_a?(Array)
    assert_equal ["header"], body["bearer_methods_supported"]
    assert_includes body["scopes_supported"], "mcp:read"
    assert_includes body["scopes_supported"], "mcp:write"
  end

  test "oauth-authorization-server advertises endpoints + supported flows" do
    get "/.well-known/oauth-authorization-server"
    assert_response :success
    body = JSON.parse(response.body)
    assert body["issuer"].present?
    assert_match(%r{/oauth/authorize\z}, body["authorization_endpoint"])
    assert_match(%r{/oauth/token\z}, body["token_endpoint"])
    assert_match(%r{/oauth/register\z}, body["registration_endpoint"])
    assert_includes body["grant_types_supported"], "authorization_code"
    assert_includes body["code_challenge_methods_supported"], "S256"
    assert_includes body["scopes_supported"], "mcp:read"
  end
end
