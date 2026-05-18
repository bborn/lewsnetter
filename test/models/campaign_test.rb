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

  test "delivery_stats returns zero counts when there are no deliveries" do
    stats = @campaign.delivery_stats
    %i[sent delivered opened clicked bounced complained unsubscribed failed click_total].each do |k|
      assert_equal 0, stats[k], "expected #{k} = 0"
    end
  end

  test "delivery_stats aggregates across the delivery scopes" do
    subs = 6.times.map do |i|
      @team.subscribers.create!(email: "ds#{i}@example.com", external_id: "ds-#{i}", subscribed: true)
    end

    # Plain sent (delivered to MTA, opened, clicked twice).
    Delivery.create!(
      campaign: @campaign, subscriber: subs[0],
      ses_message_id: "ds-1", sent_at: 1.hour.ago,
      delivered_at: 50.minutes.ago, opened_at: 40.minutes.ago,
      clicked_at: 30.minutes.ago, click_count: 2
    )
    # Sent + delivered only.
    Delivery.create!(
      campaign: @campaign, subscriber: subs[1],
      ses_message_id: "ds-2", sent_at: 1.hour.ago,
      delivered_at: 50.minutes.ago, status: "delivered"
    )
    # Bounced (has ses_message_id, so still counts as sent).
    Delivery.create!(
      campaign: @campaign, subscriber: subs[2],
      ses_message_id: "ds-3", sent_at: 1.hour.ago,
      bounced_at: 20.minutes.ago, status: "bounced"
    )
    # Complained.
    Delivery.create!(
      campaign: @campaign, subscriber: subs[3],
      ses_message_id: "ds-4", sent_at: 1.hour.ago,
      complained_at: 10.minutes.ago, status: "complained"
    )
    # Unsubscribed via in-email link.
    Delivery.create!(
      campaign: @campaign, subscriber: subs[4],
      ses_message_id: "ds-5", sent_at: 1.hour.ago,
      delivered_at: 50.minutes.ago, unsubscribed_at: 5.minutes.ago
    )
    # Failed (no message id).
    Delivery.create!(
      campaign: @campaign, subscriber: subs[5],
      status: "failed", error_message: "boom"
    )

    stats = @campaign.delivery_stats
    assert_equal 5, stats[:sent]         # rows with ses_message_id
    assert_equal 3, stats[:delivered]    # rows with delivered_at
    assert_equal 1, stats[:opened]
    assert_equal 1, stats[:clicked]
    assert_equal 2, stats[:click_total]
    assert_equal 1, stats[:bounced]
    assert_equal 1, stats[:complained]
    assert_equal 1, stats[:unsubscribed]
    assert_equal 1, stats[:failed]
  end
end
