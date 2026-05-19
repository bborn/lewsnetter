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
    assert_match(/different team/i, response.parsed_body["error"])
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
end
