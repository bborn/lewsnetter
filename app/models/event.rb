class Event < ApplicationRecord
  belongs_to :team
  belongs_to :subscriber

  validates :name, presence: true
  validates :occurred_at, presence: true

  scope :named, ->(name) { where(name: name) }
  scope :since, ->(time) { where("occurred_at >= ?", time) }
end
