class SenderAddress < ApplicationRecord
  # 🚅 add concerns above.

  # 🚅 add attribute accessors above.

  belongs_to :team
  # 🚅 add belongs_to associations above.

  has_many :campaigns, dependent: :nullify
  has_many :sequences, dependent: :nullify
  # 🚅 add has_many associations above.

  # 🚅 add has_one associations above.

  # 🚅 add scopes above.

  validates :email, presence: true,
    format: {with: URI::MailTo::EMAIL_REGEXP, message: "must be a valid email address"}
  # 🚅 add validations above.

  before_destroy :keep_while_in_use, prepend: true
  # 🚅 add callbacks above.

  # 🚅 add delegations above.

  # 🚅 add methods above.

  private

  def keep_while_in_use
    if campaigns.where(status: %w[scheduled sending]).exists?
      errors.add(:base, "A scheduled or sending campaign uses this sender address. Cancel the schedule or wait for delivery to finish before deleting it.")
    elsif sequences.active.exists?
      errors.add(:base, "An active sequence uses this sender address. Pause the sequence or choose another sender before deleting it.")
    else
      return
    end
    throw :abort
  end
end
