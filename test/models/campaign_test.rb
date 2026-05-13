require "test_helper"

class CampaignTest < ActiveSupport::TestCase
  setup do
    @team = create(:team)
    @sender = @team.sender_addresses.create!(
      email: "from@example.com", name: "Sender", verified: true, ses_status: "verified"
    )
    @template = @team.email_templates.create!(
      name: "T",
      mjml_body: "<mjml><mj-body><mj-section><mj-column><mj-text>Hi {{first_name}}</mj-text></mj-column></mj-section></mj-body></mjml>"
    )
    @campaign = @team.campaigns.create!(
      email_template: @template,
      sender_address: @sender,
      subject: "Hello",
      body_mjml: @template.mjml_body,
      status: "draft"
    )
  end

  test "sendable? is true for draft and scheduled, false otherwise" do
    @campaign.status = "draft"
    assert @campaign.sendable?

    @campaign.status = "scheduled"
    assert @campaign.sendable?

    %w[sending sent failed].each do |s|
      @campaign.status = s
      refute @campaign.sendable?, "expected sendable? to be false for #{s}"
    end
  end

  test "send_now transitions to sent and sets sent_at" do
    @team.subscribers.create!(email: "ann@example.com", external_id: "campaign-test-a", subscribed: true)

    original = Rails.application.config.ses_client
    Rails.application.config.ses_client = :stub
    begin
      SendCampaignJob.perform_now(@campaign.id)
    ensure
      Rails.application.config.ses_client = original
    end

    @campaign.reload
    assert_equal "sent", @campaign.status
    assert_not_nil @campaign.sent_at, "expected sent_at to be populated after a successful send"
    assert_in_delta Time.current, @campaign.sent_at, 5.seconds
  end

  test "status validation rejects values outside STATUSES" do
    @campaign.status = "draftish"
    refute @campaign.valid?
    assert @campaign.errors[:status].any?
  end

  test "STATUSES constant covers the documented state machine values" do
    assert_equal %w[draft scheduled sending sent failed], Campaign::STATUSES
  end
end
