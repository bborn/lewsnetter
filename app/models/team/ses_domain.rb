# A sending domain a team has registered with AWS SES for DKIM-based
# verification. Created by the email-sending setup wizard's domain step
# (`Account::EmailSendingSetupController#submit_domain`) and managed via
# `Ses::DomainIdentityCreator` / `Ses::DomainIdentityChecker`.
#
# Phase 1: one domain per team (UI enforces single-domain via has_one),
# but the table allows many rows per team so multi-domain is a UI change
# only.
#
# Status enum:
#   unverified  — row exists, AWS hasn't been called yet (transient)
#   pending     — SES has the identity + DKIM tokens, DNS not yet propagated
#   verified    — SES reports DKIM SUCCESS; safe to send from this domain
#   failed      — SES reports DKIM FAILED (typically DNS missing or wrong)
class Team::SesDomain < ApplicationRecord
  self.table_name = "team_ses_domains"

  # 🚅 add concerns above.

  # 🚅 add attribute accessors above.

  belongs_to :team
  # 🚅 add belongs_to associations above.

  # 🚅 add has_many associations above.

  # 🚅 add has_one associations above.

  STATUSES = %w[unverified pending verified failed].freeze

  scope :verified, -> { where(status: "verified") }
  # 🚅 add scopes above.

  # RFC 1035-ish: lowercase letters, digits, hyphens, dots. No protocol,
  # no path, no port. Up to 253 chars total. We accept user input that
  # included `https://` or a trailing slash and strip it in a before_validation.
  DOMAIN_FORMAT = /\A[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+\z/

  validates :domain,
    presence: true,
    length: {maximum: 253},
    format: {with: DOMAIN_FORMAT, message: "must be a valid hostname (e.g. hey.example.com)"},
    uniqueness: {scope: :team_id, case_sensitive: false}
  validates :status, inclusion: {in: STATUSES}
  # 🚅 add validations above.

  before_validation :normalize_domain
  # 🚅 add callbacks above.

  # 🚅 add delegations above.

  STATUSES.each do |s|
    define_method("#{s}?") { status == s }
  end

  # Decoded DKIM tokens. Stored as a JSON-encoded string so we can run on
  # SQLite without the json column type.
  def dkim_token_list
    return [] if dkim_tokens.blank?
    parsed = JSON.parse(dkim_tokens)
    parsed.is_a?(Array) ? parsed : []
  rescue JSON::ParserError
    []
  end

  def dkim_token_list=(value)
    self.dkim_tokens = value.present? ? JSON.dump(Array(value)) : nil
  end

  # The three CNAME records the user needs to add to their DNS. SES's DKIM
  # scheme: `<token>._domainkey.<domain>` CNAME `<token>.dkim.amazonses.com`.
  # Returns an empty array until CreateEmailIdentity has populated dkim_tokens.
  def cname_records
    dkim_token_list.map do |token|
      {
        host: "#{token}._domainkey.#{domain}",
        value: "#{token}.dkim.amazonses.com",
        type: "CNAME"
      }
    end
  end

  # 🚅 add methods above.

  private

  def normalize_domain
    return if domain.blank?
    self.domain = domain.to_s.strip.downcase
      .sub(%r{\Ahttps?://}, "")
      .sub(%r{/+\z}, "")
      .sub(/\A@/, "")
  end
end
