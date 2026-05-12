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
    team.sender_addresses
  end
  # 🚅 add methods above.
end
