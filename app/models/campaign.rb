class Campaign < ApplicationRecord
  # 🚅 add concerns above.

  STATUSES = %w[draft scheduled sending sent failed].freeze

  # 🚅 add attribute accessors above.

  belongs_to :team
  belongs_to :email_template, optional: true
  belongs_to :segment, optional: true
  belongs_to :sender_address, optional: true
  # 🚅 add belongs_to associations above.

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
  # 🚅 add validations above.

  # 🚅 add callbacks above.

  # 🚅 add delegations above.

  STATUSES.each do |s|
    define_method("#{s}?") { status == s }
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

  # Renders the campaign's MJML body to HTML for an in-app preview. Uses the
  # first subscribed subscriber on the team as a stand-in so variable
  # substitution shows the user what a real recipient would see. Returns nil
  # if the team has no subscribers OR rendering blows up (bad MJML, etc.) so
  # the view can show a placeholder.
  def preview_html(for_subscriber: nil)
    subscriber = for_subscriber || team.subscribers.subscribed.order(:id).first
    return nil unless subscriber

    CampaignRenderer.new(campaign: self, subscriber: subscriber).call.html
  rescue => _e
    nil
  end
  # 🚅 add methods above.
end
