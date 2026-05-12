require "controllers/api/v1/test"

class Api::V1::SubscribersControllerTest < Api::Test
  setup do
    # See `test/controllers/api/test.rb` for common set up for API tests.

    @subscriber = build(:subscriber, team: @team)
    @other_subscribers = create_list(:subscriber, 3)

    @another_subscriber = create(:subscriber, team: @team)

    # 🚅 super scaffolding will insert file-related logic above this line.
    @subscriber.save
    @another_subscriber.save

    @original_hide_things = ENV["HIDE_THINGS"]
    ENV["HIDE_THINGS"] = "false"
    Rails.application.reload_routes!
  end

  teardown do
    ENV["HIDE_THINGS"] = @original_hide_things
    Rails.application.reload_routes!
  end

  # This assertion is written in such a way that new attributes won't cause the tests to start failing, but removing
  # data we were previously providing to users _will_ break the test suite.
  def assert_proper_object_serialization(subscriber_data)
    # Fetch the subscriber in question and prepare to compare it's attributes.
    subscriber = Subscriber.find(subscriber_data["id"])

    assert_equal_or_nil subscriber_data["external_id"], subscriber.external_id
    assert_equal_or_nil subscriber_data["email"], subscriber.email
    assert_equal_or_nil subscriber_data["name"], subscriber.name
    assert_equal_or_nil subscriber_data["subscribed"], subscriber.subscribed
    # 🚅 super scaffolding will insert new fields above this line.

    assert_equal subscriber_data["team_id"], subscriber.team_id
  end

  test "index" do
    # Fetch and ensure nothing is seriously broken.
    get "/api/v1/teams/#{@team.id}/subscribers", params: {access_token: access_token}
    assert_response :success

    # Make sure it's returning our resources.
    subscriber_ids_returned = response.parsed_body.map { |subscriber| subscriber["id"] }
    assert_includes(subscriber_ids_returned, @subscriber.id)

    # But not returning other people's resources.
    assert_not_includes(subscriber_ids_returned, @other_subscribers[0].id)

    # And that the object structure is correct.
    assert_proper_object_serialization response.parsed_body.first
  end

  test "show" do
    # Fetch and ensure nothing is seriously broken.
    get "/api/v1/subscribers/#{@subscriber.id}", params: {access_token: access_token}
    assert_response :success

    # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # Also ensure we can't do that same action as another user.
    get "/api/v1/subscribers/#{@subscriber.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end

  test "create" do
    # Use the serializer to generate a payload, but strip some attributes out.
    params = {access_token: access_token}
    subscriber_data = JSON.parse(build(:subscriber, team: nil).api_attributes.to_json)
    subscriber_data.except!("id", "team_id", "created_at", "updated_at")
    params[:subscriber] = subscriber_data

    post "/api/v1/teams/#{@team.id}/subscribers", params: params
    assert_response :success

    # # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # Also ensure we can't do that same action as another user.
    post "/api/v1/teams/#{@team.id}/subscribers",
      params: params.merge({access_token: another_access_token})
    assert_response :not_found
  end

  test "update" do
    # Post an attribute update ensure nothing is seriously broken.
    put "/api/v1/subscribers/#{@subscriber.id}", params: {
      access_token: access_token,
      subscriber: {
        external_id: "Alternative String Value",
        email: "another.email@test.com",
        name: "Alternative String Value",
        # 🚅 super scaffolding will also insert new fields above this line.
      }
    }

    assert_response :success

    # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # But we have to manually assert the value was properly updated.
    @subscriber.reload
    assert_equal @subscriber.external_id, "Alternative String Value"
    assert_equal @subscriber.email, "another.email@test.com"
    assert_equal @subscriber.name, "Alternative String Value"
    # 🚅 super scaffolding will additionally insert new fields above this line.

    # Also ensure we can't do that same action as another user.
    put "/api/v1/subscribers/#{@subscriber.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end

  test "destroy" do
    # Delete and ensure it actually went away.
    assert_difference("Subscriber.count", -1) do
      delete "/api/v1/subscribers/#{@subscriber.id}", params: {access_token: access_token}
      assert_response :success
    end

    # Also ensure we can't do that same action as another user.
    delete "/api/v1/subscribers/#{@another_subscriber.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end
end
