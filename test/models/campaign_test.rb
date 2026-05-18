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

  test "top_links returns [] when no recipient has clicked a tracked URL" do
    @team.subscribers.create!(email: "noclick@example.com", external_id: "tl-noclick", subscribed: true)
    assert_equal [], @campaign.top_links
  end

  test "top_links aggregates unique + total clicks per URL, sorted by total desc" do
    subs = 5.times.map do |i|
      @team.subscribers.create!(email: "tl#{i}@example.com", external_id: "tl-#{i}", subscribed: true)
    end

    # foo.example.com — 3 unique recipients, with click_counts 5, 2, 1 → total 8
    Delivery.create!(campaign: @campaign, subscriber: subs[0], ses_message_id: "tl-1",
      sent_at: 1.hour.ago, clicked_at: 30.minutes.ago,
      click_count: 5, last_clicked_url: "https://foo.example.com/landing")
    Delivery.create!(campaign: @campaign, subscriber: subs[1], ses_message_id: "tl-2",
      sent_at: 1.hour.ago, clicked_at: 25.minutes.ago,
      click_count: 2, last_clicked_url: "https://foo.example.com/landing")
    Delivery.create!(campaign: @campaign, subscriber: subs[2], ses_message_id: "tl-3",
      sent_at: 1.hour.ago, clicked_at: 20.minutes.ago,
      click_count: 1, last_clicked_url: "https://foo.example.com/landing")
    # bar.example.com — 2 unique recipients, click_counts 4, 3 → total 7
    Delivery.create!(campaign: @campaign, subscriber: subs[3], ses_message_id: "tl-4",
      sent_at: 1.hour.ago, clicked_at: 15.minutes.ago,
      click_count: 4, last_clicked_url: "https://bar.example.com/x")
    Delivery.create!(campaign: @campaign, subscriber: subs[4], ses_message_id: "tl-5",
      sent_at: 1.hour.ago, clicked_at: 10.minutes.ago,
      click_count: 3, last_clicked_url: "https://bar.example.com/x")

    rows = @campaign.top_links

    assert_equal 2, rows.size
    assert_equal "https://foo.example.com/landing", rows[0][:url]
    assert_equal 3, rows[0][:unique_clicks]
    assert_equal 8, rows[0][:total_clicks]

    assert_equal "https://bar.example.com/x", rows[1][:url]
    assert_equal 2, rows[1][:unique_clicks]
    assert_equal 7, rows[1][:total_clicks]
  end

  test "top_links honours the limit argument" do
    10.times do |i|
      sub = @team.subscribers.create!(email: "lim#{i}@example.com", external_id: "lim-#{i}", subscribed: true)
      Delivery.create!(campaign: @campaign, subscriber: sub, ses_message_id: "lim-#{i}",
        sent_at: 1.hour.ago, clicked_at: 30.minutes.ago,
        click_count: 10 - i, # bigger i → fewer clicks → lower rank
        last_clicked_url: "https://example.com/link-#{i}")
    end

    rows = @campaign.top_links(limit: 3)
    assert_equal 3, rows.size
    # Top three should be the three with the largest click_counts (links 0..2).
    assert_equal "https://example.com/link-0", rows[0][:url]
    assert_equal "https://example.com/link-1", rows[1][:url]
    assert_equal "https://example.com/link-2", rows[2][:url]
  end

  test "top_links ignores deliveries with no last_clicked_url" do
    sub_a = @team.subscribers.create!(email: "tla@example.com", external_id: "tla", subscribed: true)
    sub_b = @team.subscribers.create!(email: "tlb@example.com", external_id: "tlb", subscribed: true)
    # Clicked → included
    Delivery.create!(campaign: @campaign, subscriber: sub_a, ses_message_id: "tl-c-a",
      sent_at: 1.hour.ago, clicked_at: 10.minutes.ago,
      click_count: 1, last_clicked_url: "https://present.example.com")
    # No click recorded → excluded
    Delivery.create!(campaign: @campaign, subscriber: sub_b, ses_message_id: "tl-c-b",
      sent_at: 1.hour.ago, delivered_at: 30.minutes.ago)

    rows = @campaign.top_links
    assert_equal 1, rows.size
    assert_equal "https://present.example.com", rows[0][:url]
  end
end
