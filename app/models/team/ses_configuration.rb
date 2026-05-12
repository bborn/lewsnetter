class Team::SesConfiguration < ApplicationRecord
  # 🚅 add concerns above.

  encrypts :encrypted_access_key_id, :encrypted_secret_access_key
  # 🚅 add attribute accessors above.

  belongs_to :team
  # 🚅 add belongs_to associations above.

  # 🚅 add has_many associations above.

  # 🚅 add has_one associations above.

  STATUSES = %w[unconfigured verifying verified failed].freeze

  scope :verified, -> { where(status: "verified") }
  # 🚅 add scopes above.

  validates :region, presence: true
  validates :status, inclusion: {in: STATUSES}
  validates :unsubscribe_host,
    format: {with: /\A[a-z0-9.\-]+\z/i, allow_blank: true},
    length: {maximum: 253}
  # 🚅 add validations above.

  # 🚅 add callbacks above.

  # 🚅 add delegations above.

  STATUSES.each do |s|
    define_method("#{s}?") { status == s }
  end

  def configured?
    encrypted_access_key_id.present? && encrypted_secret_access_key.present?
  end

  def access_key_id_last_four
    encrypted_access_key_id.to_s.last(4)
  end

  # Display-only helper consumed by app/views/account/email_sending/show.html.erb
  # (the BulletTrain shared/attributes/text partial calls `object.public_send(:quota)`
  # to decide whether to render the row).
  def quota
    return nil unless quota_max_send_24h
    "#{quota_sent_last_24h.to_i} / #{quota_max_send_24h}"
  end

  # Returns this team's configured unsubscribe_host if present, otherwise the
  # caller-supplied default. Callers (ApplicationMailer, CampaignRenderer,
  # UnsubscribeUrlHelper) pass in the app-wide default rather than us
  # hard-coding "lewsnetter.whinynil.co" in the model.
  def resolved_unsubscribe_host(default:)
    unsubscribe_host.presence || default
  end
  # 🚅 add methods above.
end
