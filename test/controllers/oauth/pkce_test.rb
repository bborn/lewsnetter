# frozen_string_literal: true

require "test_helper"

# The authorization server metadata advertises PKCE (S256) and public
# clients. A public client has no secret, so the code_verifier is the only
# thing that ties the token request to the client that started the flow:
# a code sent with a code_challenge must not be exchangeable without the
# matching verifier.
module Oauth
  class PkceTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    REDIRECT_URI = "https://client.example/callback"
    VERIFIER = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"

    setup do
      @user = FactoryBot.create(:onboarded_user)
      sign_in @user

      post "/oauth/register",
        params: {
          redirect_uris: [REDIRECT_URI],
          client_name: "Public MCP client",
          token_endpoint_auth_method: "none"
        }.to_json,
        headers: {"Content-Type" => "application/json"}
      assert_response :created
      @client_id = JSON.parse(response.body)["client_id"]
    end

    def authorize(client_id: @client_id, **overrides)
      params = {
        client_id: client_id,
        redirect_uri: REDIRECT_URI,
        response_type: "code",
        scope: "mcp:read mcp:write",
        state: "xyz",
        code_challenge: Base64.urlsafe_encode64(Digest::SHA256.digest(VERIFIER), padding: false),
        code_challenge_method: "S256"
      }.merge(overrides).compact
      get "/oauth/authorize", params: params
      post "/oauth/authorize", params: params
      assert_response :redirect
      Rack::Utils.parse_query(URI.parse(response.location).query)
    end

    def authorization_code
      authorize.fetch("code")
    end

    def exchange(code, **extra)
      post "/oauth/token", params: {
        grant_type: "authorization_code",
        code: code,
        client_id: @client_id,
        redirect_uri: REDIRECT_URI
      }.merge(extra)
    end

    test "a code issued with a code_challenge is refused without the code_verifier" do
      exchange(authorization_code)

      assert_response :bad_request
      assert_equal "invalid_request", JSON.parse(response.body)["error"]
    end

    test "a code issued with a code_challenge is refused with the wrong code_verifier" do
      exchange(authorization_code, code_verifier: "x" * 43)

      assert_response :bad_request
      assert_equal "invalid_grant", JSON.parse(response.body)["error"]
    end

    test "a code issued with a code_challenge is exchanged with the matching code_verifier" do
      exchange(authorization_code, code_verifier: VERIFIER)

      assert_response :success
      assert JSON.parse(response.body)["access_token"].present?
    end

    test "a public client cannot get a code without a code_challenge" do
      query = authorize(code_challenge: nil, code_challenge_method: nil)

      assert_equal "invalid_request", query["error"]
      refute query.key?("code")
    end

    test "a public client cannot use the plain code_challenge_method" do
      query = authorize(code_challenge: VERIFIER, code_challenge_method: "plain")

      assert_equal "invalid_code_challenge_method", query["error"]
      refute query.key?("code")
    end

    test "a confidential client can still exchange a code without PKCE" do
      post "/oauth/register",
        params: {redirect_uris: [REDIRECT_URI], client_name: "Confidential client"}.to_json,
        headers: {"Content-Type" => "application/json"}
      client = JSON.parse(response.body)

      code = authorize(client_id: client["client_id"], code_challenge: nil, code_challenge_method: nil).fetch("code")
      exchange(code, client_id: client["client_id"], client_secret: client["client_secret"])

      assert_response :success
      assert JSON.parse(response.body)["access_token"].present?
    end
  end
end
