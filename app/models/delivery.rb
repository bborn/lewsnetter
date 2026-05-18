# Per-recipient delivery record for a Campaign. Created at SES send time by
# SesSender, then enriched over the campaign's life by SNS event-publishing
# webhooks (Delivery / Bounce / Complaint) and, in Phase 2, by the open
# pixel + click-tracking routes.
#
# This is the source of truth for per-campaign engagement. Campaign.stats
# still exists (legacy + job-level progress), but reads should prefer
# aggregations over Delivery — see Mcp::Tools::Campaigns::Postmortem.
class Delivery < ApplicationRecord
  # 🚅 add concerns above.

  STATUSES = %w[sent delivered bounced complained failed].freeze

  # 🚅 add attribute accessors above.

  belongs_to :campaign
  belongs_to :subscriber
  # 🚅 add belongs_to associations above.

  # 🚅 add has_many associations above.

  # 🚅 add has_one associations above.

  # Scopes are "fact-based" — they trust the timestamp columns instead of
  # status, because a row can have e.g. been delivered AND then bounced
  # later (rare but possible — SES will emit both events). Status reflects
  # the *latest* terminal state; the timestamps preserve the history.
  scope :sent, -> { where.not(ses_message_id: nil) }
  scope :delivered, -> { where.not(delivered_at: nil) }
  scope :opened, -> { where.not(opened_at: nil) }
  scope :clicked, -> { where.not(clicked_at: nil) }
  scope :bounced, -> { where.not(bounced_at: nil).or(where(status: "bounced")) }
  scope :complained, -> { where.not(complained_at: nil).or(where(status: "complained")) }
  scope :failed, -> { where(status: "failed") }
  # 🚅 add scopes above.

  validates :status, presence: true, inclusion: {in: STATUSES}
  # campaign + subscriber presence is enforced by the belongs_to defaults.
  # 🚅 add validations above.

  # 🚅 add callbacks above.

  # 🚅 add delegations above.

  def opened?
    opened_at.present?
  end

  def clicked?
    clicked_at.present?
  end

  def bounced?
    bounced_at.present? || status == "bounced"
  end

  def complained?
    complained_at.present? || status == "complained"
  end

  def delivered?
    delivered_at.present? || status == "delivered"
  end

  def failed?
    status == "failed"
  end

  # Signed token used by the open-pixel + click-redirect routes to look this
  # delivery row up without exposing the integer primary key. The payload is
  # just `id` for the open pixel; for clicks we sign a hash with both the
  # delivery id and the destination URL via `.signed_click_token`.
  #
  # Both purposes use Rails' MessageVerifier rather than a SGID because:
  #   - we want a tight, opaque-looking URL component (SGIDs encode the model
  #     name + signs it, longer)
  #   - we don't need GlobalID-style polymorphic lookup; this is delivery-only
  def tracking_token
    Rails.application.message_verifier(:delivery_open).generate(id)
  end

  def self.find_by_tracking_token(token, purpose: :delivery_open)
    id = Rails.application.message_verifier(purpose).verify(token)
    find_by(id: id)
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  # Builds a click-tracking token that round-trips the destination URL. The
  # URL is signed alongside the delivery id so the click redirect controller
  # can trust the URL without consulting a database lookup table — this also
  # closes the open-redirect hole (an attacker would need our signing secret
  # to redirect to an arbitrary URL).
  def signed_click_token(url:)
    Rails.application.message_verifier(:delivery_click).generate({
      delivery_id: id,
      url: url
    })
  end
  # 🚅 add methods above.
end
