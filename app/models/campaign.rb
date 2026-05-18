class Campaign < ApplicationRecord
  # 🚅 add concerns above.

  STATUSES = %w[draft scheduled sending sent failed].freeze

  # Mirror of EmailTemplate::ASSET_MAX_BYTES — keep these in lockstep.
  # Per-attachment cap, not aggregate; uploading several small images
  # is fine.
  ASSET_MAX_BYTES = 5.megabytes

  # 🚅 add attribute accessors above.

  belongs_to :team
  belongs_to :email_template, optional: true
  belongs_to :segment, optional: true
  belongs_to :sender_address, optional: true
  # 🚅 add belongs_to associations above.

  # Per-campaign image attachments (logos, hero images, inline content).
  # See EmailTemplate#assets for the design rationale (rails_storage_proxy_url,
  # validation strategy, 5 MB cap).
  has_many_attached :assets

  # Per-recipient delivery rows. Source of truth for engagement aggregations
  # (sent / delivered / bounced / complained / failed; opens + clicks land in
  # Phase 2). Destroyed with the campaign so postmortem data dies with it —
  # we don't keep an audit trail of deleted campaigns by design.
  has_many :deliveries, dependent: :destroy

  # 🚅 add has_many associations above.

  # 🚅 add has_one associations above.

  scope :draft, -> { where(status: "draft") }
  scope :scheduled, -> { where(status: "scheduled") }
  scope :sent, -> { where(status: "sent") }
  # 🚅 add scopes above.

  validates :subject, presence: true
  validates :status, inclusion: {in: STATUSES}
  validates :email_template, scope: true
  validates :segment, scope: true
  validate :body_present_in_some_form
  validate :assets_must_be_images_under_max_size
  # 🚅 add validations above.

  # 🚅 add callbacks above.

  # 🚅 add delegations above.

  STATUSES.each do |s|
    define_method("#{s}?") { status == s }
  end

  # Can this campaign be sent now? Only draft and scheduled campaigns are
  # sendable — anything that is already in flight, completed, or failed should
  # require an explicit re-draft or duplication step before going out again.
  # The send-now flow + view buttons gate on this.
  def sendable?
    draft? || scheduled?
  end

  def valid_email_templates
    team.email_templates
  end

  def valid_segments
    team.segments
  end

  def valid_sender_addresses
    team.sender_addresses.where(verified: true)
  end

  # Count of subscribers who will actually receive this campaign when sent.
  # Mirrors the audience resolution in SendCampaignJob:
  #   - If a segment is attached, the segment's predicate narrows the base scope.
  #   - Otherwise, every subscribed team subscriber.
  # If the segment's predicate is invalid we surface nil; callers should treat
  # that as "we don't know" rather than a real zero.
  def recipient_count
    base = team.subscribers.subscribed
    return base.count if segment.blank?

    begin
      segment.applies_to(base).count
    rescue Segment::InvalidPredicate
      nil
    end
  end

  # Renders the campaign body to HTML for an in-app preview. Uses the first
  # subscribed subscriber on the team as a stand-in so variable substitution
  # shows the user what a real recipient would see. If there are no
  # subscribed subscribers we build a transient placeholder subscriber so the
  # author can still see their work-in-progress design rendered. Returns nil
  # only if rendering blows up (bad MJML/markdown/template) so the view can
  # show a placeholder.
  def preview_html(for_subscriber: nil)
    subscriber = for_subscriber ||
      team.subscribers.subscribed.order(:id).first ||
      placeholder_preview_subscriber

    CampaignRenderer.new(campaign: self, subscriber: subscriber).call.html
  rescue => _e
    nil
  end

  # Whether the markdown authoring path is in use. Drives the preview pipeline
  # + AI drafter output target.
  def markdown_body?
    body_markdown.present?
  end

  # Aggregated per-recipient stats sourced from the Delivery table. This is
  # what the campaign show page renders into its stats card and what an
  # external dashboard or webhook payload should reach for. The previous
  # `Campaign#stats` JSON column tracks JOB progress (how many rows the
  # background send loop got through), not engagement — keep them separate.
  #
  # - `sent`: deliveries with a SES message id assigned (covers stub, real,
  #   delivered, bounced, complained — anything that left the queue with an id).
  # - `failed`: deliveries that never got a message id (render error / SES
  #   reject), distinct from `sent` so attempts add up to `sent + failed`.
  # - The remaining counts are simple presence-of-timestamp scopes.
  def delivery_stats
    rel = deliveries
    {
      sent: rel.sent.count,
      delivered: rel.delivered.count,
      opened: rel.opened.count,
      clicked: rel.clicked.count,
      bounced: rel.bounced.count,
      complained: rel.complained.count,
      unsubscribed: rel.where.not(unsubscribed_at: nil).count,
      failed: rel.failed.count,
      click_total: rel.sum(:click_count)
    }
  end

  # Top clicked URLs for this campaign, aggregated from the per-recipient
  # Delivery rows. `last_clicked_url` is set on a Delivery the first time the
  # tracking-click route resolves that URL, and `click_count` increments on
  # every subsequent click of any link. So:
  #
  #   - `unique_clicks` is the number of distinct recipients who clicked
  #     this URL (one Delivery row per recipient).
  #   - `total_clicks` is the sum of `click_count` across those recipients.
  #     Because click_count is a per-recipient counter rolled up across all
  #     links, this slightly over-counts when a recipient clicks multiple
  #     different URLs — we attribute their full click_count to whatever
  #     URL was last clicked. The Delivery schema doesn't keep a per-URL
  #     click counter, and we deliberately don't add one (see the build
  #     spec — no schema changes). Treat total_clicks as "engagement
  #     intensity" rather than an exact per-URL hit count.
  #
  # Returns an Array of Hashes (NOT an AR relation) so callers can chain
  # `.first(25)`, `to_json`, CSV, etc. without surprising lazy reloads.
  # The hashes have symbol keys: :url, :unique_clicks, :total_clicks.
  def top_links(limit: 25)
    rows = deliveries
      .where.not(last_clicked_url: nil)
      .group(:last_clicked_url)
      .pluck(
        :last_clicked_url,
        Arel.sql("COUNT(*)"),
        Arel.sql("COALESCE(SUM(click_count), 0)")
      )

    rows
      .map { |url, unique_count, total_count|
        {url: url, unique_clicks: unique_count.to_i, total_clicks: total_count.to_i}
      }
      .sort_by { |row| [-row[:total_clicks], -row[:unique_clicks], row[:url]] }
      .first(limit)
  end

  # Opens-over-time bucketed for the engagement sparkline. Picks an hour
  # bucket when the campaign was sent recently (≤ 3 days ago) and a day
  # bucket otherwise; either way the series is capped at the first 7 days
  # post-send so a 6-month-old campaign doesn't produce a 180-bar chart.
  #
  # Returns an Array of [Time, Integer] tuples sorted ascending, with zero
  # entries filled in for empty buckets — so the SVG renderer can iterate
  # straight through without gap-handling. Returns [] when no opens have
  # landed yet (caller should hide the chart).
  def opens_over_time
    rel = deliveries.where.not(opened_at: nil)
    return [] unless rel.exists?

    anchor = sent_at || rel.minimum(:opened_at) || Time.current
    use_hourly = (Time.current - anchor) <= 3.days

    if use_hourly
      bucket_size = 1.hour
      bucket_count = (7 * 24)
      sql_expr = "strftime('%Y-%m-%d %H:00:00', opened_at)"
      parse = ->(s) { Time.zone.parse(s) }
    else
      bucket_size = 1.day
      bucket_count = 7
      sql_expr = "strftime('%Y-%m-%d 00:00:00', opened_at)"
      parse = ->(s) { Time.zone.parse(s) }
    end

    raw = rel.group(Arel.sql(sql_expr)).count
    counts = raw.transform_keys(&parse)

    start = parse.call(
      if use_hourly
        anchor.utc.strftime("%Y-%m-%d %H:00:00")
      else
        anchor.utc.strftime("%Y-%m-%d 00:00:00")
      end
    )

    bucket_count.times.map { |i|
      t = start + (bucket_size * i)
      [t, counts[t].to_i]
    }
  end
  # 🚅 add methods above.

  private

  # In-memory subscriber used when there are no real subscribers yet — lets
  # authors see their work-in-progress preview before they've imported anyone.
  def placeholder_preview_subscriber
    Subscriber.new(
      team: team,
      email: "preview@example.com",
      name: "Preview Recipient",
      external_id: "preview",
      subscribed: true,
      custom_attributes: {}
    )
  end

  def body_present_in_some_form
    return if body_markdown.present? || body_mjml.present? || email_template&.mjml_body.present?
    errors.add(:base, "Campaign needs a body (markdown), a raw MJML body, or an email template with body content.")
  end

  # See EmailTemplate#assets_must_be_images_under_max_size — kept parallel.
  def assets_must_be_images_under_max_size
    return unless assets.attached?

    assets.each do |asset|
      blob = asset.blob
      content_type = blob.content_type.to_s
      unless content_type.start_with?("image/")
        errors.add(:assets, "must be an image (got #{content_type.presence || "unknown type"})")
      end

      if blob.byte_size > ASSET_MAX_BYTES
        size_mb = (ASSET_MAX_BYTES / 1.megabyte.to_f).round
        errors.add(:assets, "must be smaller than #{size_mb}MB")
      end
    end
  end
end
