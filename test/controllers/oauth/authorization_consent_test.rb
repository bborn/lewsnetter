# frozen_string_literal: true

require "test_helper"

# Any client can register itself through /oauth/register with any redirect
# URI. Opening an authorize link for such a client must ask the signed-in
# user for consent; it must not issue a grant, or bind the client to the
# user's team, until the user approves.
module Oauth
  class AuthorizationConsentTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    REDIRECT_URI = "https://client.example/callback"

    setup do
      @user = FactoryBot.create(:onboarded_user)
      @team = @user.current_team
      sign_in @user

      post "/oauth/register",
        params: {redirect_uris: [REDIRECT_URI], client_name: "Some MCP client"}.to_json,
        headers: {"Content-Type" => "application/json"}
      assert_response :created
      @application = Platform::Application.find_by!(uid: JSON.parse(response.body)["client_id"])
    end

    def authorize_params
      {
        client_id: @application.uid,
        redirect_uri: REDIRECT_URI,
        response_type: "code",
        scope: "mcp:read mcp:write",
        state: "xyz"
      }
    end

    test "authorize shows a consent page instead of issuing a code" do
      assert_no_difference -> { Doorkeeper::AccessGrant.count } do
        get "/oauth/authorize", params: authorize_params
      end

      assert_response :ok, "expected the consent page, got a #{response.status} to #{response.location.inspect}"
      refute_match(/code=/, response.location.to_s)
      assert_includes response.body, "Some MCP client"
      assert_nil @application.reload.team_id, "the client must not be bound to a team before consent"
    end

    test "approving the consent page issues a code and binds the client to the user's team" do
      get "/oauth/authorize", params: authorize_params
      assert_response :ok

      assert_difference -> { Doorkeeper::AccessGrant.count }, 1 do
        post "/oauth/authorize", params: authorize_params
      end

      assert_response :redirect
      assert response.location.start_with?(REDIRECT_URI), response.location
      assert_match(/code=/, response.location)
      assert_equal @team.id, @application.reload.team_id
    end

    test "denying the consent page issues nothing" do
      get "/oauth/authorize", params: authorize_params

      assert_no_difference -> { Doorkeeper::AccessGrant.count } do
        delete "/oauth/authorize", params: authorize_params
      end

      assert_match(/error=access_denied/, response.location.to_s)
      assert_nil @application.reload.team_id
    end
  end
end
