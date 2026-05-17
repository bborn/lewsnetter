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
  # 🚅 add has_many associations above.

  # 🚅 add oauth providers above.

  has_one :ses_configuration, class_name: "Team::SesConfiguration", dependent: :destroy
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
  # an active billing subscription, or if any of its members is on the
  # comma-separated BILLING_EXEMPT_EMAILS allowlist (operator accounts).
  def billing_exempt?
    emails = ENV.fetch("BILLING_EXEMPT_EMAILS", "").split(",").map { |e| e.strip.downcase }.reject(&:blank?)
    return false if emails.empty?
    users.where("LOWER(email) IN (?)", emails).exists?
  end
  # 🚅 add methods above.
end
