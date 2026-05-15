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
  end
end
