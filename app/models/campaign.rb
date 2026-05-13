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
