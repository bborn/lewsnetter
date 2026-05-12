class Template < ApplicationRecord
  belongs_to :team

  has_many :campaigns, dependent: :nullify

  validates :name, presence: true
end
