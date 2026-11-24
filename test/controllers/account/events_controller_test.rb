require "test_helper"

class Account::EventsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = FactoryBot.create(:onboarded_user)
    sign_in @user
    @subscriber = @user.current_team.subscribers.create!(email: "nested@example.test", external_id: "nested")
  end

  test "new and create under a subscriber work for a team member" do
    get new_account_subscriber_event_url(@subscriber)
    assert_response :success

    assert_difference -> { @subscriber.events.count }, 1 do
      post account_subscriber_events_url(@subscriber),
        params: {event: {name: "trial_started", occurred_at: "2026-11-20T10:00:00Z"}}
    end
    assert_redirected_to account_event_url(@subscriber.events.last)
    assert_equal @user.current_team, @subscriber.events.last.team
  end
end
