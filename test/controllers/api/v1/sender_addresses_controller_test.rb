require "controllers/api/v1/test"

class Api::V1::SenderAddressesControllerTest < Api::Test
  setup do
    # See `test/controllers/api/test.rb` for common set up for API tests.

    @sender_address = build(:sender_address, team: @team)
    @other_sender_addresses = create_list(:sender_address, 3)

    @another_sender_address = create(:sender_address, team: @team)

    # 🚅 super scaffolding will insert file-related logic above this line.
    @sender_address.save
    @another_sender_address.save

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
  def assert_proper_object_serialization(sender_address_data)
    # Fetch the sender_address in question and prepare to compare it's attributes.
    sender_address = SenderAddress.find(sender_address_data["id"])

    assert_equal_or_nil sender_address_data["email"], sender_address.email
    assert_equal_or_nil sender_address_data["name"], sender_address.name
    assert_equal_or_nil sender_address_data["verified"], sender_address.verified
    assert_equal_or_nil sender_address_data["ses_status"], sender_address.ses_status
    # 🚅 super scaffolding will insert new fields above this line.

    assert_equal sender_address_data["team_id"], sender_address.team_id
  end

  test "index" do
    # Fetch and ensure nothing is seriously broken.
    get "/api/v1/teams/#{@team.id}/sender_addresses", params: {access_token: access_token}
    assert_response :success

    # Make sure it's returning our resources.
    sender_address_ids_returned = response.parsed_body.map { |sender_address| sender_address["id"] }
    assert_includes(sender_address_ids_returned, @sender_address.id)

    # But not returning other people's resources.
    assert_not_includes(sender_address_ids_returned, @other_sender_addresses[0].id)

    # And that the object structure is correct.
    assert_proper_object_serialization response.parsed_body.first
  end

  test "show" do
    # Fetch and ensure nothing is seriously broken.
    get "/api/v1/sender_addresses/#{@sender_address.id}", params: {access_token: access_token}
    assert_response :success

    # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # Also ensure we can't do that same action as another user.
    get "/api/v1/sender_addresses/#{@sender_address.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end

  test "create" do
    # Use the serializer to generate a payload, but strip some attributes out.
    params = {access_token: access_token}
    sender_address_data = JSON.parse(build(:sender_address, team: nil).api_attributes.to_json)
    sender_address_data.except!("id", "team_id", "created_at", "updated_at")
    params[:sender_address] = sender_address_data

    post "/api/v1/teams/#{@team.id}/sender_addresses", params: params
    assert_response :success

    # # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # Also ensure we can't do that same action as another user.
    post "/api/v1/teams/#{@team.id}/sender_addresses",
      params: params.merge({access_token: another_access_token})
    assert_response :not_found
  end

  test "update" do
    # Post an attribute update ensure nothing is seriously broken.
    put "/api/v1/sender_addresses/#{@sender_address.id}", params: {
      access_token: access_token,
      sender_address: {
        email: "another.email@test.com",
        name: "Alternative String Value",
        ses_status: "Alternative String Value",
        # 🚅 super scaffolding will also insert new fields above this line.
      }
    }

    assert_response :success

    # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # But we have to manually assert the value was properly updated.
    @sender_address.reload
    assert_equal @sender_address.email, "another.email@test.com"
    assert_equal @sender_address.name, "Alternative String Value"
    assert_equal @sender_address.ses_status, "Alternative String Value"
    # 🚅 super scaffolding will additionally insert new fields above this line.

    # Also ensure we can't do that same action as another user.
    put "/api/v1/sender_addresses/#{@sender_address.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end

  test "destroy" do
    # Delete and ensure it actually went away.
    assert_difference("SenderAddress.count", -1) do
      delete "/api/v1/sender_addresses/#{@sender_address.id}", params: {access_token: access_token}
      assert_response :success
    end

    # Also ensure we can't do that same action as another user.
    delete "/api/v1/sender_addresses/#{@another_sender_address.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end
end
