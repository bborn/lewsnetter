require "controllers/api/v1/test"

class Api::V1::CampaignsControllerTest < Api::Test
  setup do
    # See `test/controllers/api/test.rb` for common set up for API tests.

    @campaign = build(:campaign, team: @team)
    @other_campaigns = create_list(:campaign, 3)

    @another_campaign = create(:campaign, team: @team)

    # 🚅 super scaffolding will insert file-related logic above this line.
    @campaign.save
    @another_campaign.save

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
  def assert_proper_object_serialization(campaign_data)
    # Fetch the campaign in question and prepare to compare it's attributes.
    campaign = Campaign.find(campaign_data["id"])

    assert_equal_or_nil campaign_data["subject"], campaign.subject
    assert_equal_or_nil campaign_data["preheader"], campaign.preheader
    assert_equal_or_nil campaign_data["body_mjml"], campaign.body_mjml
    assert_equal_or_nil campaign_data["status"], campaign.status
    assert_equal_or_nil DateTime.parse(campaign_data["scheduled_for"]), campaign.scheduled_for
    assert_equal_or_nil campaign_data["template_id"], campaign.template_id
    assert_equal_or_nil campaign_data["segment_id"], campaign.segment_id
    # 🚅 super scaffolding will insert new fields above this line.

    assert_equal campaign_data["team_id"], campaign.team_id
  end

  test "index" do
    # Fetch and ensure nothing is seriously broken.
    get "/api/v1/teams/#{@team.id}/campaigns", params: {access_token: access_token}
    assert_response :success

    # Make sure it's returning our resources.
    campaign_ids_returned = response.parsed_body.map { |campaign| campaign["id"] }
    assert_includes(campaign_ids_returned, @campaign.id)

    # But not returning other people's resources.
    assert_not_includes(campaign_ids_returned, @other_campaigns[0].id)

    # And that the object structure is correct.
    assert_proper_object_serialization response.parsed_body.first
  end

  test "show" do
    # Fetch and ensure nothing is seriously broken.
    get "/api/v1/campaigns/#{@campaign.id}", params: {access_token: access_token}
    assert_response :success

    # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # Also ensure we can't do that same action as another user.
    get "/api/v1/campaigns/#{@campaign.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end

  test "create" do
    # Use the serializer to generate a payload, but strip some attributes out.
    params = {access_token: access_token}
    campaign_data = JSON.parse(build(:campaign, team: nil).api_attributes.to_json)
    campaign_data.except!("id", "team_id", "created_at", "updated_at")
    params[:campaign] = campaign_data

    post "/api/v1/teams/#{@team.id}/campaigns", params: params
    assert_response :success

    # # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # Also ensure we can't do that same action as another user.
    post "/api/v1/teams/#{@team.id}/campaigns",
      params: params.merge({access_token: another_access_token})
    assert_response :not_found
  end

  test "update" do
    # Post an attribute update ensure nothing is seriously broken.
    put "/api/v1/campaigns/#{@campaign.id}", params: {
      access_token: access_token,
      campaign: {
        subject: "Alternative String Value",
        preheader: "Alternative String Value",
        body_mjml: "Alternative String Value",
        status: "Alternative String Value",
        # 🚅 super scaffolding will also insert new fields above this line.
      }
    }

    assert_response :success

    # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # But we have to manually assert the value was properly updated.
    @campaign.reload
    assert_equal @campaign.subject, "Alternative String Value"
    assert_equal @campaign.preheader, "Alternative String Value"
    assert_equal @campaign.body_mjml, "Alternative String Value"
    assert_equal @campaign.status, "Alternative String Value"
    # 🚅 super scaffolding will additionally insert new fields above this line.

    # Also ensure we can't do that same action as another user.
    put "/api/v1/campaigns/#{@campaign.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end

  test "destroy" do
    # Delete and ensure it actually went away.
    assert_difference("Campaign.count", -1) do
      delete "/api/v1/campaigns/#{@campaign.id}", params: {access_token: access_token}
      assert_response :success
    end

    # Also ensure we can't do that same action as another user.
    delete "/api/v1/campaigns/#{@another_campaign.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end
end
