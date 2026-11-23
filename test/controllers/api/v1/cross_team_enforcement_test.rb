require "controllers/api/v1/test"

# H1 — token<->URL team enforcement at the api/v1 seam.
#
# A user who belongs to BOTH Team A and Team B can mint a sync token under
# Team A. With BulletTrain's default `current_team = current_user.teams.first`,
# that token could previously POST to /api/v1/teams/<TEAM_B_ID>/... and the
# write would land on Team B. The new
# `enforce_token_team_matches_url_team` before_action in
# Api::V1::ApplicationController shuts that down with a 403.
#
# See docs/security/2026-05-19-data-isolation-audit.md (H1).
class Api::V1::CrossTeamEnforcementTest < Api::V1::Test
  setup do
    # @user, @team, @platform_application are set up by Api::Test.
    # Create a second team that @user is ALSO a member of, then mint a
    # token bound to @team. URLs pointing at @other_team must 403.
    @other_team = create(:team)
    create(:membership, user: @user, team: @other_team)
  end

  test "bulk subscribers POST to a different team's URL is forbidden" do
    body = {external_id: "x1", email: "x@example.com", subscribed: true}.to_json + "\n"
    post "/api/v1/teams/#{@other_team.id}/subscribers/bulk",
      params: body,
      headers: {"CONTENT_TYPE" => "application/x-ndjson", "Authorization" => "Bearer #{access_token}"}
    assert_response :forbidden
    assert_match(/bound to team .+ but the URL targets team/i, response.parsed_body["error"])
    assert_equal 0, @other_team.subscribers.count
  end

  test "events#track to a different team's URL is forbidden" do
    post "/api/v1/teams/#{@other_team.id}/events/track",
      params: {external_id: "anyone", event: "click"}.to_json,
      headers: {"CONTENT_TYPE" => "application/json", "Authorization" => "Bearer #{access_token}"}
    assert_response :forbidden
  end

  test "events#bulk to a different team's URL is forbidden" do
    post "/api/v1/teams/#{@other_team.id}/events/bulk",
      params: {external_id: "anyone", event: "click"}.to_json + "\n",
      headers: {"CONTENT_TYPE" => "application/x-ndjson", "Authorization" => "Bearer #{access_token}"}
    assert_response :forbidden
  end

  test "destroy_by_external_id to a different team's URL is forbidden" do
    delete "/api/v1/teams/#{@other_team.id}/subscribers/by_external_id/anything",
      headers: {"Authorization" => "Bearer #{access_token}"}
    assert_response :forbidden
  end

  test "index for a different team's URL is forbidden (CRUD path also covered)" do
    get "/api/v1/teams/#{@other_team.id}/subscribers", params: {access_token: access_token}
    assert_response :forbidden
  end

  test "POST to own team's bulk endpoint succeeds (regression guard)" do
    body = {external_id: "self-1", email: "self@example.com", subscribed: true}.to_json + "\n"
    assert_difference -> { @team.subscribers.count }, 1 do
      post "/api/v1/teams/#{@team.id}/subscribers/bulk",
        params: body,
        headers: {"CONTENT_TYPE" => "application/x-ndjson", "Authorization" => "Bearer #{access_token}"}
    end
    assert_response :success
  end

  # Shallow member routes (/api/v1/subscribers/:id, /api/v1/campaigns/:id, …)
  # carry no :team_id, so the record itself must belong to the token's team.
  test "shallow member routes refuse another team's records" do
    foreign = @other_team.subscribers.create!(email: "foreign@example.com", name: "Foreign")
    campaign = @other_team.campaigns.create!(subject: "Theirs", status: "draft", body_mjml: "<mjml><mj-body></mj-body></mjml>")
    auth = {"Authorization" => "Bearer #{access_token}"}

    get "/api/v1/subscribers/#{foreign.to_param}", headers: auth
    assert_response :not_found
    refute_includes response.body, "foreign@example.com"

    get "/api/v1/campaigns/#{campaign.to_param}", headers: auth
    assert_response :not_found

    get "/api/v1/teams/#{@other_team.to_param}", headers: auth
    assert_response :not_found
  end

  test "nested shallow routes refuse a parent from another team" do
    foreign = @other_team.subscribers.create!(email: "foreign@example.com")
    foreign.events.create!(team: @other_team, name: "secret_event", occurred_at: Time.current)
    auth = {"Authorization" => "Bearer #{access_token}"}

    get "/api/v1/subscribers/#{foreign.to_param}/events", headers: auth
    assert_response :not_found
    refute_includes response.body, "secret_event"

    assert_no_difference -> { Event.count } do
      post "/api/v1/subscribers/#{foreign.to_param}/events",
        params: {event: {name: "planted", occurred_at: Time.current}}.to_json,
        headers: auth.merge("CONTENT_TYPE" => "application/json")
    end
    assert_response :not_found
  end

  # A plain membership only grants read, which is why writes to the other
  # team looked safe. As an admin of that team the same token could write.
  test "shallow member routes refuse writes to a team where the user is admin" do
    @other_team.memberships.find_by!(user: @user).update!(role_ids: ["admin"])
    foreign = @other_team.subscribers.create!(email: "foreign@example.com", name: "Foreign")
    auth = {"Authorization" => "Bearer #{access_token}"}

    patch "/api/v1/subscribers/#{foreign.to_param}", params: {subscriber: {name: "Changed"}}.to_json,
      headers: auth.merge("CONTENT_TYPE" => "application/json")
    assert_response :not_found
    assert_equal "Foreign", foreign.reload.name

    delete "/api/v1/subscribers/#{foreign.to_param}", headers: auth
    assert_response :not_found
    assert Subscriber.exists?(foreign.id)

    patch "/api/v1/teams/#{@other_team.to_param}", params: {team: {name: "Renamed"}}.to_json,
      headers: auth.merge("CONTENT_TYPE" => "application/json")
    assert_response :not_found
    refute_equal "Renamed", @other_team.reload.name
  end

  test "another team's access tokens can't be read or minted" do
    other_app = create(:platform_application, team: @other_team)
    other_token = Doorkeeper::AccessToken.create!(resource_owner_id: @user.id, application: other_app,
      token: SecureRandom.hex, scopes: "read write delete", provisioned: true)
    auth = {"Authorization" => "Bearer #{access_token}"}

    get "/api/v1/platform/access_tokens/#{other_token.id}", headers: auth
    assert_response :not_found
    refute_includes response.body, other_token.token

    assert_no_difference -> { other_app.access_tokens.count } do
      post "/api/v1/platform/applications/#{other_app.id}/access_tokens",
        params: {access_token: access_token, platform_access_token: {description: "stolen"}}
    end
    assert_response :not_found
  end

  test "unnested indexes only list the token's team" do
    stranger = create(:onboarded_user)
    create(:membership, user: stranger, team: @other_team, user_email: stranger.email)
    auth = {"Authorization" => "Bearer #{access_token}"}

    get "/api/v1/teams", headers: auth
    assert_response :success
    assert_equal [@team.id], response.parsed_body.map { it["id"] }

    get "/api/v1/users", headers: auth
    assert_response :success
    ids = response.parsed_body.map { it["id"] }
    assert_includes ids, @user.id
    refute_includes ids, stranger.id

    get "/api/v1/users/#{stranger.id}", headers: auth
    assert_response :not_found
  end

  test "a token without a team can't reach team records on shallow routes" do
    unbound_app = create(:platform_application, team: nil)
    token = Doorkeeper::AccessToken.create!(resource_owner_id: @user.id, application: unbound_app,
      token: SecureRandom.hex, scopes: "read write delete").token
    own = @team.subscribers.create!(email: "own@example.com")
    auth = {"Authorization" => "Bearer #{token}"}

    get "/api/v1/subscribers/#{own.to_param}", headers: auth
    assert_response :not_found
    refute_includes response.body, "own@example.com"

    get "/api/v1/teams/#{@team.to_param}", headers: auth
    assert_response :not_found

    get "/api/v1/users/me", headers: auth
    assert_response :success
  end

  test "shallow member routes still serve the token's own team" do
    own = @team.subscribers.create!(email: "own@example.com", name: "Own")
    own.events.create!(team: @team, name: "own_event", occurred_at: Time.current)
    auth = {"Authorization" => "Bearer #{access_token}"}

    get "/api/v1/subscribers/#{own.to_param}", headers: auth
    assert_response :success
    assert_equal "own@example.com", response.parsed_body["email"]

    get "/api/v1/subscribers/#{own.to_param}/events", headers: auth
    assert_response :success
    assert_includes response.body, "own_event"

    patch "/api/v1/subscribers/#{own.to_param}", params: {subscriber: {name: "Renamed"}}.to_json,
      headers: auth.merge("CONTENT_TYPE" => "application/json")
    assert_response :success
    assert_equal "Renamed", own.reload.name

    get "/api/v1/teams/#{@team.to_param}", headers: auth
    assert_response :success

    get "/api/v1/users/me", headers: auth
    assert_response :success
    assert_equal @user.id, response.parsed_body["id"]
  end
end
