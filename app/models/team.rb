class Team < ApplicationRecord
  include Teams::Base
  include Webhooks::Outgoing::TeamSupport

  # 🚅 add concerns above.

  # 🚅 add belongs_to associations above.

  has_many :subscribers, dependent: :destroy
  has_many :companies, dependent: :destroy
  has_many :events, dependent: :destroy
  has_many :segments, dependent: :destroy
  has_many :email_templates, dependent: :destroy
  has_many :campaigns, dependent: :destroy
  has_many :sender_addresses, dependent: :destroy
  has_many :subscriber_imports, class_name: "Subscribers::Import", dependent: :destroy
  has_many :chats, dependent: :destroy
  # Per-team blocklist of addresses we will never send to. Auto-populated
  # from hard bounces + complaints; manually managed via the Suppressions
  # settings page. See app/models/suppression.rb.
  has_many :suppressions, class_name: "Suppression", dependent: :destroy
  # 🚅 add has_many associations above.

  # 🚅 add oauth providers above.

  has_one :ses_configuration, class_name: "Team::SesConfiguration", dependent: :destroy
  # Phase 1 of domain-verification is single-domain per team. The underlying
  # table allows many; the has_one keeps the wizard simple and reflects
  # today's product surface.
  has_one :ses_domain, class_name: "Team::SesDomain", dependent: :destroy
  # 🚅 add has_one associations above.

  # 🚅 add scopes above.

  # 🚅 add validations above.

  # Seed every brand-new team with sample subscribers + a draft campaign
  # so the first thing a user sees isn't an empty dashboard. Idempotent;
  # globally skippable via LEWSNETTER_SKIP_SEEDING for the test suite +
  # programmatic team-creation paths (e.g. seed scripts, factories).
  after_create_commit :seed_sample_data
  # 🚅 add callbacks above.

  # 🚅 add delegations above.

  def seed_sample_data
    Teams::SampleDataSeeder.call(self)
  end

  # The only paywalled action is connecting SES (saving AWS credentials).
  # Everything else in the app is free. A team passes the gate if it has
  # an active billing subscription, or if any of its members matches the
  # comma-separated BILLING_EXEMPT_EMAILS allowlist (operator accounts).
  #
  # Each entry is either:
  #   - an exact email           e.g. "bruno@influencekit.com"
  #   - or a domain wildcard     e.g. "@example.com" (matches any address
  #                                    ending in that domain — used in tests)
  def billing_exempt?
    entries = ENV.fetch("BILLING_EXEMPT_EMAILS", "").split(",").map { |e| e.strip.downcase }.reject(&:blank?)
    return false if entries.empty?
    patterns = entries.map { |e| e.start_with?("@") ? "%#{e}" : e }
    clause = (["LOWER(email) LIKE ?"] * patterns.length).join(" OR ")
    users.where(clause, *patterns).exists?
  end
  # 🚅 add methods above.
end
