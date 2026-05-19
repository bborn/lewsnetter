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

  test "invalid token renders the invalid-link page (200) and does not mutate any subscriber" do
    get "/unsubscribe/not-a-real-token"
    assert_response :success
    assert_match(/invalid or expired/i, response.body)
    assert @subscriber.reload.subscribed
  end

  # C1 regression — `Subscriber.find_by(id: token)` used to let any
  # unauthenticated attacker iterate /unsubscribe/1, /unsubscribe/2, ...
  # and mass-unsubscribe every team's subscribers. The signed token MUST be
  # the only credential the endpoint will honor.
  test "bare integer ID in :token slot does NOT unsubscribe and renders the invalid page" do
    [@subscriber.id.to_s, "1", "2", "999999"].each do |raw_id|
      get "/unsubscribe/#{raw_id}"
      assert_response :success
      assert_match(/invalid or expired/i, response.body)
    end
    assert @subscriber.reload.subscribed, "subscriber must not be flipped by an integer-id probe"
    assert_nil @subscriber.unsubscribed_at, "unsubscribed_at must not be stamped by an integer-id probe"
  end

  test "POST with bare integer ID (one-click probe) does NOT unsubscribe" do
    post "/unsubscribe/#{@subscriber.id}"
    assert_response :success
    assert @subscriber.reload.subscribed
    assert_nil @subscriber.unsubscribed_at
  end
end
