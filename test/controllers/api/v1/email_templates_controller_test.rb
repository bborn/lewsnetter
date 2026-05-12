require "controllers/api/v1/test"

class Api::V1::EmailTemplatesControllerTest < Api::Test
  setup do
    # See `test/controllers/api/test.rb` for common set up for API tests.

    @email_template = build(:email_template, team: @team)
    @other_email_templates = create_list(:email_template, 3)

    @another_email_template = create(:email_template, team: @team)

    # 🚅 super scaffolding will insert file-related logic above this line.
    @email_template.save
    @another_email_template.save

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
  def assert_proper_object_serialization(email_template_data)
    # Fetch the email_template in question and prepare to compare it's attributes.
    email_template = EmailTemplate.find(email_template_data["id"])

    assert_equal_or_nil email_template_data["name"], email_template.name
    assert_equal_or_nil email_template_data["mjml_body"], email_template.mjml_body
    # 🚅 super scaffolding will insert new fields above this line.

    assert_equal email_template_data["team_id"], email_template.team_id
  end

  test "index" do
    # Fetch and ensure nothing is seriously broken.
    get "/api/v1/teams/#{@team.id}/email_templates", params: {access_token: access_token}
    assert_response :success

    # Make sure it's returning our resources.
    email_template_ids_returned = response.parsed_body.map { |email_template| email_template["id"] }
    assert_includes(email_template_ids_returned, @email_template.id)

    # But not returning other people's resources.
    assert_not_includes(email_template_ids_returned, @other_email_templates[0].id)

    # And that the object structure is correct.
    assert_proper_object_serialization response.parsed_body.first
  end

  test "show" do
    # Fetch and ensure nothing is seriously broken.
    get "/api/v1/email_templates/#{@email_template.id}", params: {access_token: access_token}
    assert_response :success

    # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # Also ensure we can't do that same action as another user.
    get "/api/v1/email_templates/#{@email_template.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end

  test "create" do
    # Use the serializer to generate a payload, but strip some attributes out.
    params = {access_token: access_token}
    email_template_data = JSON.parse(build(:email_template, team: nil).api_attributes.to_json)
    email_template_data.except!("id", "team_id", "created_at", "updated_at")
    params[:email_template] = email_template_data

    post "/api/v1/teams/#{@team.id}/email_templates", params: params
    assert_response :success

    # # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # Also ensure we can't do that same action as another user.
    post "/api/v1/teams/#{@team.id}/email_templates",
      params: params.merge({access_token: another_access_token})
    assert_response :not_found
  end

  test "update" do
    # Post an attribute update ensure nothing is seriously broken.
    put "/api/v1/email_templates/#{@email_template.id}", params: {
      access_token: access_token,
      email_template: {
        name: "Alternative String Value",
        mjml_body: "Alternative String Value",
        # 🚅 super scaffolding will also insert new fields above this line.
      }
    }

    assert_response :success

    # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # But we have to manually assert the value was properly updated.
    @email_template.reload
    assert_equal @email_template.name, "Alternative String Value"
    assert_equal @email_template.mjml_body, "Alternative String Value"
    # 🚅 super scaffolding will additionally insert new fields above this line.

    # Also ensure we can't do that same action as another user.
    put "/api/v1/email_templates/#{@email_template.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end

  test "destroy" do
    # Delete and ensure it actually went away.
    assert_difference("EmailTemplate.count", -1) do
      delete "/api/v1/email_templates/#{@email_template.id}", params: {access_token: access_token}
      assert_response :success
    end

    # Also ensure we can't do that same action as another user.
    delete "/api/v1/email_templates/#{@another_email_template.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end
end
