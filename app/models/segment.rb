class Segment < ApplicationRecord
  belongs_to :team

  has_many :campaigns, dependent: :restrict_with_error

  validates :name, presence: true
end
