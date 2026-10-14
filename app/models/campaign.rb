class Campaign < ApplicationRecord
  # 🚅 add concerns above.

  # Audit trail — every create/update/destroy creates a `versions` row with a
  # column-level diff in `object_changes`. Lets the campaign show page (and
  # later: forensic SQL) answer "what was the exact body when this sent? who
  # edited it? when?" `updated_at` is filtered so save noise doesn't dilute
  # the history. See ApplicationController#user_for_paper_trail for whodunnit.
  has_paper_trail on: [:create, :update, :destroy],
    ignore: [:updated_at]

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
  has_many :click_events, through: :deliveries
  has_many :open_events, through: :deliveries

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
  validate :plain_text_requires_markdown_body
  validate :assets_must_be_images_under_max_size
  # 🚅 add validations above.

  # Single-axis invariant for the Format control: a plain-text campaign never
  # carries a template. Enforced as a callback (not just in the form) so the
  # MCP/API path can't persist the contradictory state either.
  before_validation :clear_template_when_plain_text
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

    rendered = CampaignRenderer.new(campaign: self, subscriber: subscriber).call
    # Plain-text campaigns have no HTML part; wrap the rendered text in a <pre>
    # so the live-preview iframe shows exactly what subscribers will read,
    # whitespace and line breaks intact.
    return plain_text_preview_html(rendered.text) if plain_text_only?

    rendered.html
  rescue => _e
    nil
  end

  # Whether the markdown authoring path is in use. Drives the preview pipeline
  # + AI drafter output target.
  def markdown_body?
    body_markdown.present?
  end

  # The single "Format" control on the edit form folds the template choice and
  # the plain-text option into one select, so they can't contradict. Values:
  #   "plain_text" → pure text/plain (no template, no HTML, no tracking)
  #   ""           → no template (raw MJML / HTML body)
  #   "<id>"       → that EmailTemplate provides the header/footer chrome
  # The underlying columns (plain_text_only + email_template_id) stay the
  # source of truth — this is just a humane single-axis projection of them,
  # so the renderer, MCP tools, and API keep using the real attributes.
  def delivery_format
    return "plain_text" if plain_text_only?
    email_template_id&.to_s || ""
  end

  def delivery_format=(value)
    if value.to_s == "plain_text"
      self.plain_text_only = true
      self.email_template_id = nil
    else
      self.plain_text_only = false
      self.email_template_id = value.presence
    end
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
  #
  # Opens + clicks are reported as HUMAN numbers first, with the machine
  # share alongside so nothing is hidden (see ClickEvent / OpenEvent for the
  # classification rules):
  #
  # - `clicked`: recipients with at least one human click.
  # - `clicks_total`: human clicks across all links.
  # - `clicked_automated`: recipients whose clicks were ALL machine traffic
  #   (scanners, honeypot hits) — they're not in `clicked`.
  # - `clicked_raw` / `clicks_total_raw`: the unfiltered Delivery counters,
  #   i.e. what this card showed before filtering existed.
  # - `opened`: recipients with a human open OR a human click (a click
  #   proves the email was opened even when images were blocked or Apple
  #   MPP hid the real open).
  # - `opened_automated`: recipients with only machine opens.
  # - `opened_raw`: the unfiltered first-pixel-fetch count.
  def delivery_stats
    rel = deliveries
    human_click_ids = click_events.links.human.select(:delivery_id)
    human_open_ids = open_events.human.select(:delivery_id)
    opened_ids = rel.where(id: human_open_ids).or(rel.where(id: human_click_ids))

    {
      sent: rel.sent.count,
      delivered: rel.delivered.count,
      opened: opened_ids.count,
      opened_automated: rel.where(id: open_events.select(:delivery_id))
        .where.not(id: opened_ids.select(:id)).count,
      opened_raw: rel.opened.count,
      clicked: rel.where(id: human_click_ids).count,
      clicks_total: click_events.links.human.count,
      clicked_automated: rel.where(id: click_events.select(:delivery_id))
        .where.not(id: human_click_ids).count,
      clicked_raw: rel.clicked.count,
      clicks_total_raw: rel.sum(:click_count),
      bounced: rel.bounced.count,
      complained: rel.complained.count,
      unsubscribed: rel.where.not(unsubscribed_at: nil).count,
      failed: rel.failed.count
    }
  end

  # Top clicked URLs for this campaign, aggregated from ClickEvent rows so
  # a recipient who clicked several links is credited on each one (the old
  # Delivery#last_clicked_url rollup could only attribute one).
  #
  #   - `unique_clicks`: distinct recipients with a human click on the URL.
  #   - `total_clicks`: human clicks on the URL.
  #   - `automated_clicks`: machine clicks on the URL (scanners etc.).
  #
  # Links that only machines clicked are still listed (with zero human
  # counts) so the scanner traffic is visible, sorted below the rest. The
  # honeypot link is never listed.
  #
  # Returns an Array of Hashes (NOT an AR relation) so callers can chain
  # `.first(25)`, `to_json`, CSV, etc. without surprising lazy reloads.
  def top_links(limit: 25)
    rows = click_events.links
      .where.not(url: nil)
      .group(:url)
      .pluck(
        :url,
        Arel.sql("COUNT(DISTINCT CASE WHEN click_events.automated = 0 THEN click_events.delivery_id END)"),
        Arel.sql("SUM(CASE WHEN click_events.automated = 0 THEN 1 ELSE 0 END)"),
        Arel.sql("SUM(CASE WHEN click_events.automated = 1 THEN 1 ELSE 0 END)")
      )

    rows
      .map { |url, unique_count, human_count, automated_count|
        {
          url: url,
          unique_clicks: unique_count.to_i,
          total_clicks: human_count.to_i,
          automated_clicks: automated_count.to_i
        }
      }
      .sort_by { |row| [-row[:total_clicks], -row[:unique_clicks], -row[:automated_clicks], row[:url]] }
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

    parse = ->(s) { Time.zone.parse(s) }
    if use_hourly
      bucket_size = 1.hour
      bucket_count = (7 * 24)
      sql_expr = "strftime('%Y-%m-%d %H:00:00', opened_at)"
    else
      bucket_size = 1.day
      bucket_count = 7
      sql_expr = "strftime('%Y-%m-%d 00:00:00', opened_at)"
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

  # See the `before_validation` above — keeps plain-text campaigns from also
  # carrying a template, the contradictory state the unified Format control
  # is meant to make unrepresentable.
  def clear_template_when_plain_text
    self.email_template_id = nil if plain_text_only?
  end

  # Plain-text campaigns send `body_markdown` verbatim as the text body, so it
  # must be present — an MJML body or template can't stand in for it.
  def plain_text_requires_markdown_body
    return unless plain_text_only?
    return if body_markdown.present?
    errors.add(:base, "Plain-text campaigns need a plain-text body.")
  end

  # Renders the plain-text body inside a <pre> for the in-app preview iframe.
  # Escapes the text so a stray "<" in the copy can't inject markup.
  def plain_text_preview_html(text)
    <<~HTML
      <pre style="font-family: ui-sans-serif, system-ui, sans-serif; font-size: 14px; line-height: 1.5; white-space: pre-wrap; word-break: break-word; margin: 0; padding: 16px; color: #111;">#{ERB::Util.html_escape(text)}</pre>
    HTML
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
