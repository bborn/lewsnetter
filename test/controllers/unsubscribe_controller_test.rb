require "test_helper"

class UnsubscribeControllerTest < ActionDispatch::IntegrationTest
  setup do
    @team = create(:team)
    @subscriber = @team.subscribers.create!(
      email: "u@example.com", external_id: "u-1", subscribed: true
    )
  end

  test "GET with signed token unsubscribes" do
    token = @subscriber.to_signed_global_id(for: "unsubscribe").to_s
    get "/unsubscribe/#{token}"
    assert_response :success
    assert_not @subscriber.reload.subscribed
    assert_not_nil @subscriber.unsubscribed_at
  end

  test "POST with signed token unsubscribes (one-click)" do
    token = @subscriber.to_signed_global_id(for: "unsubscribe").to_s
    post "/unsubscribe/#{token}"
    assert_response :success
    assert_not @subscriber.reload.subscribed
  end

  test "invalid token renders 404 page" do
    get "/unsubscribe/not-a-real-token"
    assert_response :not_found
    assert @subscriber.reload.subscribed
  end
end
