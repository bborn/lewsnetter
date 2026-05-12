require "controllers/api/v1/test"

class Api::V1::SegmentsControllerTest < Api::Test
  setup do
    # See `test/controllers/api/test.rb` for common set up for API tests.

    @segment = build(:segment, team: @team)
    @other_segments = create_list(:segment, 3)

    @another_segment = create(:segment, team: @team)

    # 🚅 super scaffolding will insert file-related logic above this line.
    @segment.save
    @another_segment.save

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
  def assert_proper_object_serialization(segment_data)
    # Fetch the segment in question and prepare to compare it's attributes.
    segment = Segment.find(segment_data["id"])

    assert_equal_or_nil segment_data["name"], segment.name
    assert_equal_or_nil segment_data["natural_language_source"], segment.natural_language_source
    # 🚅 super scaffolding will insert new fields above this line.

    assert_equal segment_data["team_id"], segment.team_id
  end

  test "index" do
    # Fetch and ensure nothing is seriously broken.
    get "/api/v1/teams/#{@team.id}/segments", params: {access_token: access_token}
    assert_response :success

    # Make sure it's returning our resources.
    segment_ids_returned = response.parsed_body.map { |segment| segment["id"] }
    assert_includes(segment_ids_returned, @segment.id)

    # But not returning other people's resources.
    assert_not_includes(segment_ids_returned, @other_segments[0].id)

    # And that the object structure is correct.
    assert_proper_object_serialization response.parsed_body.first
  end

  test "show" do
    # Fetch and ensure nothing is seriously broken.
    get "/api/v1/segments/#{@segment.id}", params: {access_token: access_token}
    assert_response :success

    # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # Also ensure we can't do that same action as another user.
    get "/api/v1/segments/#{@segment.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end

  test "create" do
    # Use the serializer to generate a payload, but strip some attributes out.
    params = {access_token: access_token}
    segment_data = JSON.parse(build(:segment, team: nil).api_attributes.to_json)
    segment_data.except!("id", "team_id", "created_at", "updated_at")
    params[:segment] = segment_data

    post "/api/v1/teams/#{@team.id}/segments", params: params
    assert_response :success

    # # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # Also ensure we can't do that same action as another user.
    post "/api/v1/teams/#{@team.id}/segments",
      params: params.merge({access_token: another_access_token})
    assert_response :not_found
  end

  test "update" do
    # Post an attribute update ensure nothing is seriously broken.
    put "/api/v1/segments/#{@segment.id}", params: {
      access_token: access_token,
      segment: {
        name: "Alternative String Value",
        natural_language_source: "Alternative String Value",
        # 🚅 super scaffolding will also insert new fields above this line.
      }
    }

    assert_response :success

    # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # But we have to manually assert the value was properly updated.
    @segment.reload
    assert_equal @segment.name, "Alternative String Value"
    assert_equal @segment.natural_language_source, "Alternative String Value"
    # 🚅 super scaffolding will additionally insert new fields above this line.

    # Also ensure we can't do that same action as another user.
    put "/api/v1/segments/#{@segment.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end

  test "destroy" do
    # Delete and ensure it actually went away.
    assert_difference("Segment.count", -1) do
      delete "/api/v1/segments/#{@segment.id}", params: {access_token: access_token}
      assert_response :success
    end

    # Also ensure we can't do that same action as another user.
    delete "/api/v1/segments/#{@another_segment.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end
end
