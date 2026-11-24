require "controllers/api/v1/test"

class Api::V1::EventsControllerTest < Api::V1::Test
  test "create under a subscriber records the event on the subscriber's team" do
    subscriber = @team.subscribers.create!(email: "nested@example.test", external_id: "nested")

    assert_difference -> { subscriber.events.count }, 1 do
      post "/api/v1/subscribers/#{subscriber.to_param}/events",
        params: {event: {name: "trial_started", occurred_at: "2026-11-20T10:00:00Z", properties: {plan: "pro"}}}.to_json,
        headers: {"CONTENT_TYPE" => "application/json", "Authorization" => "Bearer #{access_token}"}
    end

    assert_response :created
    event = subscriber.events.last
    assert_equal @team, event.team
    assert_equal({"plan" => "pro"}, event.properties)
  end

  test "create under another team's subscriber is refused, even for a member of both teams" do
    other_team = create(:team)
    create(:membership, user: @user, team: other_team)
    subscriber = other_team.subscribers.create!(email: "other@example.test", external_id: "other")

    assert_no_difference -> { Event.count } do
      post "/api/v1/subscribers/#{subscriber.to_param}/events",
        params: {event: {name: "trial_started", occurred_at: "2026-11-20T10:00:00Z"}}.to_json,
        headers: {"CONTENT_TYPE" => "application/json", "Authorization" => "Bearer #{access_token}"}
    end
    assert_response :not_found
  end
end
