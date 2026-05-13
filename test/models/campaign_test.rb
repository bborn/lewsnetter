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

  test "accepts an attached image asset" do
    @campaign.assets.attach(
      io: File.open(Rails.root.join("test/fixtures/files/test-logo.png")),
      filename: "test-logo.png",
      content_type: "image/png"
    )

    assert @campaign.valid?, @campaign.errors.full_messages.to_sentence
    assert_predicate @campaign.assets, :attached?
    assert_equal 1, @campaign.assets.count
  end

  test "rejects a non-image asset" do
    @campaign.assets.attach(
      io: File.open(Rails.root.join("test/fixtures/files/not-an-image.txt")),
      filename: "not-an-image.txt",
      content_type: "text/plain"
    )

    refute @campaign.valid?
    assert(@campaign.errors[:assets].any? { |m| m =~ /image/i },
      "expected an :assets error mentioning 'image', got #{@campaign.errors[:assets].inspect}")
  end

  test "rejects an asset that exceeds the size limit" do
    @campaign.assets.attach(
      io: File.open(Rails.root.join("test/fixtures/files/test-logo.png")),
      filename: "huge.png",
      content_type: "image/png"
    )
    blob = @campaign.assets.last.blob
    blob.update_column(:byte_size, Campaign::ASSET_MAX_BYTES + 1)

    refute @campaign.valid?
    assert(@campaign.errors[:assets].any? { |m| m =~ /smaller|MB|size/i },
      "expected a size error, got #{@campaign.errors[:assets].inspect}")
  end
end
