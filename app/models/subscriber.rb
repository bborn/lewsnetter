class Subscriber < ApplicationRecord
  belongs_to :team

  has_many :events, dependent: :destroy

  validates :email, presence: true
  validates :external_id, uniqueness: {scope: :team_id, allow_nil: true}

  scope :subscribed, -> { where(subscribed: true) }
  scope :unsubscribed, -> { where(subscribed: false) }
end
