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
  # 🚅 add methods above.
end
