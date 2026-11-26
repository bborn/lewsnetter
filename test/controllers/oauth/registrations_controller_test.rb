# frozen_string_literal: true

require "test_helper"

module Oauth
  class RegistrationsControllerTest < ActionDispatch::IntegrationTest
    test "POST /oauth/register creates a Platform::Application and returns client_id + secret" do
      assert_difference -> { Platform::Application.count }, 1 do
        post "/oauth/register",
          params: {redirect_uris: ["https://example.com/cb"], client_name: "Claude Desktop"}.to_json,
          headers: {"Content-Type" => "application/json"}
      end
      assert_response :created
      body = JSON.parse(response.body)
      assert body["client_id"].present?
      assert body["client_secret"].present?  # confidential by default
      assert_equal "Claude Desktop", body["client_name"]
      assert_includes body["redirect_uris"], "https://example.com/cb"
      assert_includes body["grant_types"], "authorization_code"
    end

    test "public client (token_endpoint_auth_method: none) returns no client_secret" do
      post "/oauth/register",
        params: {redirect_uris: ["http://localhost:8080/cb"], token_endpoint_auth_method: "none"}.to_json,
        headers: {"Content-Type" => "application/json"}
      assert_response :created
      body = JSON.parse(response.body)
      assert body["client_id"].present?
      refute body.key?("client_secret"), "public client should not get a secret"
      assert_equal "none", body["token_endpoint_auth_method"]
    end

    test "missing redirect_uris is a 400" do
      post "/oauth/register",
        params: {client_name: "x"}.to_json,
        headers: {"Content-Type" => "application/json"}
      assert_response :bad_request
      assert_match(/redirect_uris/, JSON.parse(response.body)["error"])
    end

    test "invalid JSON body is a 400" do
      post "/oauth/register",
        params: "not json",
        headers: {"Content-Type" => "application/json"}
      assert_response :bad_request
      assert_match(/Invalid JSON/i, JSON.parse(response.body)["error"])
    end

    def register(redirect_uri)
      post "/oauth/register",
        params: {redirect_uris: [redirect_uri], token_endpoint_auth_method: "none"}.to_json,
        headers: {"Content-Type" => "application/json"}
    end

    test "script redirect URIs are refused" do
      ["javascript://example.com/%0Aalert(1)", "data:text/html,hi", "vbscript://example.com/x"].each do |uri|
        assert_no_difference -> { Platform::Application.count }, uri do
          register(uri)
        end
        assert_response :unprocessable_entity, uri
      end
    end

    test "plain http redirect URIs are refused off loopback" do
      register("http://client.example/callback")
      assert_response :unprocessable_entity
    end

    test "native MCP client redirect URIs are accepted" do
      ["http://localhost:33418/callback", "http://127.0.0.1:6274/oauth/callback",
        "https://claude.ai/api/mcp/auth_callback", "cursor://anysphere.cursor-mcp/oauth/callback"].each do |uri|
        register(uri)
        assert_response :created, uri
      end
    end
  end
end
