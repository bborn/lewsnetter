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
    %i[sent delivered opened opened_automated opened_raw clicked clicks_total clicked_automated
      clicked_raw clicks_total_raw bounced complained unsubscribed failed].each do |k|
      assert_equal 0, stats[k], "expected #{k} = 0"
    end
  end

  test "delivery_stats aggregates across the delivery scopes" do
    subs = 6.times.map do |i|
      @team.subscribers.create!(email: "ds#{i}@example.com", external_id: "ds-#{i}", subscribed: true)
    end

    # Plain sent (delivered to MTA, opened, clicked twice by a person).
    clicker = Delivery.create!(
      campaign: @campaign, subscriber: subs[0],
      ses_message_id: "ds-1", sent_at: 1.hour.ago,
      delivered_at: 50.minutes.ago, opened_at: 40.minutes.ago,
      clicked_at: 30.minutes.ago, click_count: 2
    )
    clicker.open_events.create!(opened_at: 40.minutes.ago, user_agent: "Mozilla/5.0 (Macintosh) Firefox/130")
    clicker.click_events.create!(url: "https://example.com/a", clicked_at: 30.minutes.ago, user_agent: "Firefox")
    clicker.click_events.create!(url: "https://example.com/b", clicked_at: 29.minutes.ago, user_agent: "Firefox")
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
    assert_equal 2, stats[:clicks_total]
    assert_equal 1, stats[:bounced]
    assert_equal 1, stats[:complained]
    assert_equal 1, stats[:unsubscribed]
    assert_equal 1, stats[:failed]
  end

  test "delivery_stats reports human clicks/opens as the headline and machine traffic alongside" do
    subs = 4.times.map do |i|
      @team.subscribers.create!(email: "hm#{i}@example.com", external_id: "hm-#{i}", subscribed: true)
    end
    delivered = 2.hours.ago

    # Scanner only: every link hit seconds after delivery, raw columns set.
    scanned = Delivery.create!(campaign: @campaign, subscriber: subs[0], ses_message_id: "hm-1",
      sent_at: delivered, delivered_at: delivered, opened_at: delivered + 5.seconds,
      clicked_at: delivered + 10.seconds, click_count: 3, last_clicked_url: "https://example.com/c")
    scanned.open_events.create!(opened_at: delivered + 5.seconds, automated: true, automated_reason: "apple_mpp")
    %w[a b c].each_with_index do |path, i|
      scanned.click_events.create!(url: "https://example.com/#{path}", clicked_at: delivered + (10 + i).seconds,
        automated: true, automated_reason: "too_fast")
    end

    # Scanner pass, then the real reader an hour later on one link.
    mixed = Delivery.create!(campaign: @campaign, subscriber: subs[1], ses_message_id: "hm-2",
      sent_at: delivered, delivered_at: delivered, opened_at: delivered + 5.seconds,
      clicked_at: delivered + 10.seconds, click_count: 3, last_clicked_url: "https://example.com/a")
    mixed.open_events.create!(opened_at: delivered + 5.seconds, automated: true, automated_reason: "too_fast")
    mixed.click_events.create!(url: "https://example.com/a", clicked_at: delivered + 10.seconds,
      automated: true, automated_reason: "too_fast")
    mixed.click_events.create!(url: "https://example.com/b", clicked_at: delivered + 11.seconds,
      automated: true, automated_reason: "too_fast")
    mixed.click_events.create!(url: "https://example.com/a", clicked_at: delivered + 1.hour, user_agent: "Safari")

    # Apple MPP open only — no human signal at all.
    mpp = Delivery.create!(campaign: @campaign, subscriber: subs[2], ses_message_id: "hm-3",
      sent_at: delivered, delivered_at: delivered, opened_at: delivered + 3.seconds)
    mpp.open_events.create!(opened_at: delivered + 3.seconds, automated: true, automated_reason: "apple_mpp")

    # A real open, no click.
    reader = Delivery.create!(campaign: @campaign, subscriber: subs[3], ses_message_id: "hm-4",
      sent_at: delivered, delivered_at: delivered, opened_at: delivered + 30.minutes)
    reader.open_events.create!(opened_at: delivered + 30.minutes, user_agent: "Mozilla/5.0 (Windows NT 10.0) Thunderbird/128")

    stats = @campaign.delivery_stats
    assert_equal 1, stats[:clicked], "only the mixed recipient clicked as a person"
    assert_equal 1, stats[:clicks_total]
    assert_equal 1, stats[:clicked_automated], "scanner-only recipient"
    assert_equal 2, stats[:clicked_raw]
    assert_equal 6, stats[:clicks_total_raw]
    # Human opens: the real reader + the mixed recipient (a human click
    # implies an open even though their pixel fetch was a scanner).
    assert_equal 2, stats[:opened]
    assert_equal 2, stats[:opened_automated], "scanned + mpp"
    assert_equal 4, stats[:opened_raw]
  end

  test "top_links returns [] when no recipient has clicked a tracked URL" do
    @team.subscribers.create!(email: "noclick@example.com", external_id: "tl-noclick", subscribed: true)
    assert_equal [], @campaign.top_links
  end

  test "top_links counts human unique/total per URL from click events, crediting every link clicked" do
    subs = 3.times.map do |i|
      @team.subscribers.create!(email: "tl#{i}@example.com", external_id: "tl-#{i}", subscribed: true)
    end
    deliveries = subs.each_with_index.map do |sub, i|
      Delivery.create!(campaign: @campaign, subscriber: sub, ses_message_id: "tl-#{i}",
        sent_at: 2.hours.ago, delivered_at: 2.hours.ago)
    end
    foo = "https://foo.example.com/landing"
    bar = "https://bar.example.com/x"

    # Recipient 0 clicks foo twice and bar once — both links get credit.
    deliveries[0].click_events.create!(url: foo, clicked_at: 1.hour.ago, user_agent: "Firefox")
    deliveries[0].click_events.create!(url: foo, clicked_at: 50.minutes.ago, user_agent: "Firefox")
    deliveries[0].click_events.create!(url: bar, clicked_at: 40.minutes.ago, user_agent: "Firefox")
    # Recipient 1 clicks foo once.
    deliveries[1].click_events.create!(url: foo, clicked_at: 30.minutes.ago, user_agent: "Safari")
    # Recipient 2 is a scanner on both links.
    deliveries[2].click_events.create!(url: foo, clicked_at: 2.hours.ago, automated: true, automated_reason: "too_fast")
    deliveries[2].click_events.create!(url: bar, clicked_at: 2.hours.ago, automated: true, automated_reason: "too_fast")
    # Honeypot hits never show up as a link.
    deliveries[2].click_events.create!(clicked_at: 2.hours.ago, honeypot: true, automated: true, automated_reason: "honeypot")

    rows = @campaign.top_links

    assert_equal 2, rows.size
    assert_equal({url: foo, unique_clicks: 2, total_clicks: 3, automated_clicks: 1}, rows[0])
    assert_equal({url: bar, unique_clicks: 1, total_clicks: 1, automated_clicks: 1}, rows[1])
  end

  test "top_links lists scanner-only links below human-clicked ones" do
    sub = @team.subscribers.create!(email: "so@example.com", external_id: "so", subscribed: true)
    d = Delivery.create!(campaign: @campaign, subscriber: sub, ses_message_id: "so-1",
      sent_at: 2.hours.ago, delivered_at: 2.hours.ago)
    d.click_events.create!(url: "https://example.com/scanned", clicked_at: 2.hours.ago,
      automated: true, automated_reason: "scanner_user_agent")
    d.click_events.create!(url: "https://example.com/human", clicked_at: 1.hour.ago, user_agent: "Firefox")

    rows = @campaign.top_links
    assert_equal %w[https://example.com/human https://example.com/scanned], rows.map { |r| r[:url] }
    assert_equal 0, rows[1][:total_clicks]
    assert_equal 1, rows[1][:automated_clicks]
  end

  test "top_links honours the limit argument" do
    sub = @team.subscribers.create!(email: "lim@example.com", external_id: "lim", subscribed: true)
    d = Delivery.create!(campaign: @campaign, subscriber: sub, ses_message_id: "lim-1",
      sent_at: 2.hours.ago, delivered_at: 2.hours.ago)
    5.times do |i|
      (5 - i).times do |n|
        d.click_events.create!(url: "https://example.com/link-#{i}", clicked_at: (60 - n).minutes.ago, user_agent: "Firefox")
      end
    end

    rows = @campaign.top_links(limit: 3)
    assert_equal %w[https://example.com/link-0 https://example.com/link-1 https://example.com/link-2], rows.map { |r| r[:url] }
  end

  # ---------------------------------------------------------------------
  # PaperTrail audit-history wiring. These tests guard:
  #   1. Versions are created on create / update / destroy.
  #   2. The diff (object_changes) captures the actual edit so the
  #      History UI can render it.
  #   3. The `updated_at` ignore filter actually filters — a `touch` that
  #      only bumps updated_at must NOT create a version.
  # ---------------------------------------------------------------------
  test "paper_trail records a version on create" do
    assert_equal 1, @campaign.versions.count, "expected one :create version after setup"
    assert_equal "create", @campaign.versions.last.event
  end

  test "paper_trail records a version on update with the diff in object_changes" do
    assert_difference -> { @campaign.versions.count }, 1 do
      @campaign.update!(subject: "New subject")
    end
    v = @campaign.versions.last
    assert_equal "update", v.event
    changes = parse_paper_trail_changes(v.object_changes)
    assert_includes changes.keys, "subject"
    assert_equal ["Hello", "New subject"], changes["subject"]
  end

  test "paper_trail ignores updated_at-only saves" do
    # `touch` bumps only updated_at — that column is in `ignore:`, so no
    # version should land.
    assert_no_difference -> { @campaign.versions.count } do
      @campaign.touch
    end
  end

  # ---------------------------------------------------------------------
  # Plain-text-only campaigns
  # ---------------------------------------------------------------------
  test "plain_text_only campaign is valid with a markdown body and no template" do
    campaign = @team.campaigns.new(
      sender_address: @sender,
      subject: "Plain",
      plain_text_only: true,
      body_markdown: "Just text",
      status: "draft"
    )
    assert campaign.valid?, campaign.errors.full_messages.to_sentence
  end

  test "plain_text_only campaign requires a plain-text (markdown) body" do
    # body_mjml satisfies the generic body-presence check, so this isolates the
    # plain-text-specific rule: a plain-text campaign needs its own text body.
    campaign = @team.campaigns.new(
      email_template: @template,
      sender_address: @sender,
      subject: "Plain",
      body_mjml: @template.mjml_body,
      plain_text_only: true,
      body_markdown: ""
    )
    refute campaign.valid?
    assert(campaign.errors[:base].any? { |m| m =~ /plain.?text/i },
      "expected a base error about the missing plain-text body, got #{campaign.errors[:base].inspect}")
  end

  test "preview_html for a plain-text campaign returns escaped text, not MJML chrome" do
    @team.subscribers.create!(
      email: "pv@example.com", external_id: "pv", subscribed: true, name: "Pat Lee"
    )
    @campaign.update!(
      plain_text_only: true,
      body_markdown: "Hello {{first_name}}\n\nLine two",
      body_mjml: nil,
      email_template: nil
    )

    html = @campaign.preview_html

    assert_includes html, "Hello Pat"
    assert_includes html, "<pre"
    refute_includes html, "mj-", "preview must not render MJML for a plain-text campaign"
  end

  # ---------------------------------------------------------------------
  # delivery_format — the single "Format" control that unifies the template
  # choice and the plain-text option (no separate checkbox).
  # ---------------------------------------------------------------------
  test "delivery_format reports plain_text when plain_text_only" do
    @campaign.plain_text_only = true
    assert_equal "plain_text", @campaign.delivery_format
  end

  test "delivery_format reports the selected template id" do
    assert_equal @template.id.to_s, @campaign.delivery_format
  end

  test "delivery_format is blank when there is no template and not plain text" do
    @campaign.email_template = nil
    @campaign.plain_text_only = false
    assert_equal "", @campaign.delivery_format
  end

  test "setting delivery_format to plain_text enables plain text and clears the template" do
    @campaign.delivery_format = "plain_text"
    assert @campaign.plain_text_only?
    assert_nil @campaign.email_template_id
  end

  test "setting delivery_format to a template id selects it and disables plain text" do
    @campaign.update!(plain_text_only: true, body_markdown: "x")
    @campaign.delivery_format = @template.id.to_s
    assert_equal @template.id, @campaign.email_template_id
    refute @campaign.plain_text_only?
  end

  test "a plain-text campaign cannot also keep a template (single-axis invariant)" do
    @campaign.update!(email_template: @template, plain_text_only: true, body_markdown: "x")
    @campaign.reload
    assert @campaign.plain_text_only?
    assert_nil @campaign.email_template_id,
      "plain_text_only must clear email_template_id on save, even when set directly (MCP/API path)"
  end

  test "paper_trail records a version on destroy" do
    id = @campaign.id
    @campaign.destroy!
    destroy_version = PaperTrail::Version
      .where(item_type: "Campaign", item_id: id, event: "destroy")
      .last
    assert_not_nil destroy_version, "expected a :destroy version row to be persisted"
  end

  private

  # PaperTrail stores object_changes as YAML by default; round-trip it the
  # same way the History partial does. Permits the timestamp classes that
  # show up when AR auto-touches columns.
  def parse_paper_trail_changes(raw)
    return raw if raw.is_a?(Hash)
    YAML.safe_load(
      raw,
      permitted_classes: [Time, Date, DateTime, ActiveSupport::TimeWithZone, ActiveSupport::TimeZone, Symbol]
    )
  end
end
