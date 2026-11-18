require "controllers/api/v1/test"

class Api::V1::CampaignLifecycleTest < Api::V1::Test
  setup do
    @campaign = @team.campaigns.create!(subject: "Broadcast", body_markdown: "Hi", status: "sent")
  end

  test "a completed campaign cannot be changed back to draft through the API" do
    update_status("draft")
    assert_response :unprocessable_entity
    assert_equal "sent", @campaign.reload.status
  end

  test "a failed campaign can still be redrafted explicitly through the API" do
    @campaign = @team.campaigns.create!(subject: "Failed broadcast", body_markdown: "Hi", status: "failed")

    update_status("draft")
    assert_response :success
    assert_equal "draft", @campaign.reload.status
  end

  private

  def update_status(status)
    patch "/api/v1/campaigns/#{@campaign.id}",
      params: {campaign: {status: status}},
      headers: {"Authorization" => "Bearer #{access_token}"},
      as: :json
  end
end
