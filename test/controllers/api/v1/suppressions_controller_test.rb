require "controllers/api/v1/test"

class Api::V1::SuppressionsControllerTest < Api::V1::Test
  def post_suppression(team, body)
    post "/api/v1/teams/#{team.id}/suppressions",
      params: body.to_json,
      headers: {"CONTENT_TYPE" => "application/json", "Authorization" => "Bearer #{access_token}"}
  end

  test "creates a suppression and is idempotent" do
    post_suppression(@team, {email: " Person@Example.com ", reason: "complaint", note: "from helpdesk"})
    assert_response :created
    body = response.parsed_body
    assert_equal "person@example.com", body["email"]
    assert_equal "complaint", body["reason"]
    assert_equal "api", body["source"]
    assert body["created"]

    post_suppression(@team, {email: "person@example.com", reason: "manual"})
    assert_response :ok
    assert_equal "complaint", response.parsed_body["reason"], "first reason wins"
    assert_not response.parsed_body["created"]
    assert_equal 1, @team.suppressions.count
  end

  test "the suppressed address is skipped by sends" do
    post_suppression(@team, {email: "gone@example.com"})
    assert_equal ["gone@example.com"], Suppression.for_team_emails(@team, ["gone@example.com"]).to_a
  end

  test "rejects a missing email or unknown reason" do
    post_suppression(@team, {reason: "manual"})
    assert_response :bad_request

    post_suppression(@team, {email: "a@example.com", reason: "because"})
    assert_response :unprocessable_entity
    assert_equal 0, @team.suppressions.count
  end

  test "another team's URL is forbidden" do
    other = create(:team)
    create(:membership, user: @user, team: other)
    post_suppression(other, {email: "a@example.com"})
    assert_response :forbidden
    assert_equal 0, other.suppressions.count
  end
end
