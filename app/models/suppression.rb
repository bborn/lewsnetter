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
#   - Repeated soft bounces  (reason: "repeated_soft_bounce") — an address
#     that soft-bounced (SES bounceType "Transient": mailbox full, mailbox
#     disabled, receiving server deferring…) on SOFT_BOUNCE_THRESHOLD
#     consecutive campaigns with no successful delivery, open, or click in
#     between. A single soft bounce is never enough: those are often
#     temporary. Several in a row across separate campaigns means the
#     mailbox is effectively dead, and continuing to mail it hurts sender
#     reputation. See `.suppress_after_repeated_soft_bounces`.
#
# Manually populated from:
#   - Operator add via the Suppressions UI  (reason: "manual")
#   - GDPR erasure requests                 (reason: "gdpr_request")
#
# Email is deterministic-encrypted, matching the Subscriber pattern, so
# `where(email: q)` still hits the unique index. Reason + source + note are
# plaintext — low-stakes, useful for operator debugging.
class Suppression < ApplicationRecord
  REASONS = %w[hard_bounce complaint repeated_soft_bounce manual gdpr_request].freeze

  # How many consecutive campaigns must soft-bounce before an address is
  # suppressed. Self-hosters can override with SOFT_BOUNCE_SUPPRESSION_THRESHOLD.
  SOFT_BOUNCE_THRESHOLD = Integer(ENV.fetch("SOFT_BOUNCE_SUPPRESSION_THRESHOLD", 3))

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
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
    # Race with a concurrent SNS event for the same address: DB-level
    # uniqueness raises RecordNotUnique; Rails' case-insensitive uniqueness
    # validator raises RecordInvalid first. Both mean "row already exists" —
    # refetch and return. Re-raise if it really was something else (e.g. a
    # malformed email from a quirky bounce payload).
    existing = where(team_id: team.id, email: normalized).first
    raise e if existing.nil?
    existing
  end

  # Called by the SNS webhook after a Transient bounce is recorded. Looks at
  # the subscriber's most recent SOFT_BOUNCE_THRESHOLD deliveries on this
  # team (one per campaign) and suppresses the address only when every one
  # of them soft-bounced and none was opened or clicked. Any delivery in
  # that run that wasn't a soft bounce (delivered cleanly, opened, clicked)
  # breaks the streak, so this only fires on N bounces in a row.
  #
  # Deliveries that never went out (status "suppressed" / "failed") are
  # skipped — they don't say anything about the mailbox.
  #
  # Returns the Suppression row when one was created (or already existed),
  # nil otherwise.
  def self.suppress_after_repeated_soft_bounces(team:, subscriber:, threshold: SOFT_BOUNCE_THRESHOLD)
    return nil if subscriber.nil? || threshold.to_i < 1

    recent = Delivery.joins(:campaign)
      .where(campaigns: {team_id: team.id}, subscriber_id: subscriber.id)
      .where.not(status: %w[suppressed failed])
      .order(Arel.sql("COALESCE(deliveries.sent_at, deliveries.created_at) DESC"), id: :desc)
      .limit(threshold)
      .to_a

    return nil if recent.size < threshold
    return nil unless recent.all? { |d| soft_bounce?(d) }

    suppress(
      team: team,
      email: subscriber.email,
      reason: "repeated_soft_bounce",
      source: recent.first.bounce_subtype.presence || "Transient",
      note: "Soft-bounced on #{threshold} consecutive campaigns"
    )
  end

  # A delivery counts toward the streak when SES reported a Transient bounce
  # and the recipient never opened or clicked it. `delivered_at` alone
  # doesn't break it: SES "Delivery" only means the receiving server
  # accepted the message, and an asynchronous bounce can follow.
  def self.soft_bounce?(delivery)
    delivery.bounce_type == "Transient" &&
      delivery.opened_at.nil? &&
      delivery.clicked_at.nil?
  end

  private

  def normalize_email
    self.email = email.to_s.strip.downcase if email.present?
  end

  def default_suppressed_at
    self.suppressed_at ||= Time.current
  end
end
