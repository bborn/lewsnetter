# Per-team address blocklist. We will NEVER send to an address that has a
# Suppression row, regardless of which segment it appears in or whether
# the Subscriber row still says `subscribed: true`. This is reputation-
# protection infrastructure: SES auto-suspends accounts that drift over
# ~5% bounce rate, and the way to prevent that is to never re-attempt
# addresses we already know are bad.
#
# Auto-populated from:
#   - SES Permanent bounces  (reason: "hard_bounce")
#   - SES Complaints         (reason: "complaint")
#
# Manually populated from:
#   - Operator add via the Suppressions UI  (reason: "manual")
#   - GDPR erasure requests                 (reason: "gdpr_request")
#
# Email is deterministic-encrypted, matching the Subscriber pattern, so
# `where(email: q)` still hits the unique index. Reason + source + note are
# plaintext — low-stakes, useful for operator debugging.
class Suppression < ApplicationRecord
  REASONS = %w[hard_bounce complaint manual gdpr_request].freeze

  # PII at rest. Deterministic so we can do exact-match lookups for the
  # SesSender skip-list and the SNS auto-add upsert. `support_unencrypted_data`
  # is kept on so any legacy plaintext rows would still be readable, mirroring
  # Subscriber's pragma.
  encrypts :email, deterministic: true, support_unencrypted_data: true

  belongs_to :team

  validates :email, presence: true, format: {with: URI::MailTo::EMAIL_REGEXP}
  validates :reason, presence: true, inclusion: {in: REASONS}
  validates :email, uniqueness: {scope: :team_id, case_sensitive: false}

  # Normalize before encryption so the unique index + lookups all hit the
  # same ciphertext. Subscriber stores plain-as-typed for legacy reasons;
  # Suppression is new code so we get to be strict.
  before_validation :normalize_email
  before_validation :default_suppressed_at, on: :create

  # Returns the subset of `emails` that are suppressed on this team. Used by
  # SesSender to skip sends BEFORE we hand off to SES, so a bad address never
  # gets a second chance to count against our bounce rate.
  #
  # Returns a Set of downcased emails so callers can do O(1) membership
  # checks while iterating the per-batch subscriber list.
  def self.for_team_emails(team, emails)
    list = Array(emails).compact.map { |e| e.to_s.strip.downcase }.uniq
    return Set.new if list.empty?

    where(team_id: team.id, email: list).pluck(:email).map(&:downcase).to_set
  end

  # Idempotent upsert. The SNS webhook can re-fire the same bounce/complaint
  # event — we don't want a uniqueness violation to crash the webhook handler.
  # Returns the row (created or pre-existing). If a row already exists we
  # leave reason/source untouched; the FIRST event that flagged this address
  # is the most useful breadcrumb for "why is this person suppressed."
  def self.suppress(team:, email:, reason:, source: nil, note: nil)
    normalized = email.to_s.strip.downcase
    return nil if normalized.blank?

    existing = where(team_id: team.id, email: normalized).first
    return existing if existing

    create!(
      team: team,
      email: normalized,
      reason: reason,
      source: source,
      note: note,
      suppressed_at: Time.current
    )
  rescue ActiveRecord::RecordNotUnique
    # Race with a concurrent SNS event for the same address. Refetch + return.
    where(team_id: team.id, email: normalized).first
  end

  private

  def normalize_email
    self.email = email.to_s.strip.downcase if email.present?
  end

  def default_suppressed_at
    self.suppressed_at ||= Time.current
  end
end
