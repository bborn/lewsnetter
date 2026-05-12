class Campaign < ApplicationRecord
  STATUSES = %w[draft scheduled sending sent failed].freeze

  belongs_to :team
  belongs_to :template, optional: true
  belongs_to :segment, optional: true

  validates :status, inclusion: {in: STATUSES}

  scope :draft, -> { where(status: "draft") }
  scope :scheduled, -> { where(status: "scheduled") }
  scope :sent, -> { where(status: "sent") }

  STATUSES.each do |status|
    define_method("#{status}?") { self.status == status }
  end
end
