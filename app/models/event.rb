class Event < ApplicationRecord
  # 🚅 add concerns above.

  # 🚅 add attribute accessors above.

  belongs_to :team
  belongs_to :subscriber
  # 🚅 add belongs_to associations above.

  # 🚅 add has_many associations above.

  # 🚅 add has_one associations above.

  scope :named, ->(name) { where(name: name) }
  scope :since, ->(time) { where("occurred_at >= ?", time) }
  # 🚅 add scopes above.

  validates :name, presence: true
  validates :occurred_at, presence: true
  # 🚅 add validations above.

  # 🚅 add callbacks above.

  # 🚅 add delegations above.

  # 🚅 add methods above.
end
