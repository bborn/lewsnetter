class Subscriber < ApplicationRecord
  # 🚅 add concerns above.

  # 🚅 add attribute accessors above.

  belongs_to :team
  # 🚅 add belongs_to associations above.

  has_many :events, dependent: :destroy
  # 🚅 add has_many associations above.

  # 🚅 add has_one associations above.

  scope :subscribed, -> { where(subscribed: true) }
  scope :unsubscribed, -> { where(subscribed: false) }
  # 🚅 add scopes above.

  validates :email, presence: true
  validates :external_id, uniqueness: {scope: :team_id, allow_nil: true}
  # 🚅 add validations above.

  # 🚅 add callbacks above.

  # 🚅 add delegations above.

  # 🚅 add methods above.
end
