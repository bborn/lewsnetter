class EmailTemplate < ApplicationRecord
  # 🚅 add concerns above.

  # 🚅 add attribute accessors above.

  belongs_to :team

  has_many :campaigns, dependent: :nullify

  validates :name, presence: true
  # 🚅 add belongs_to associations above.

  # 🚅 add has_many associations above.

  # 🚅 add has_one associations above.

  # 🚅 add scopes above.

  # 🚅 add validations above.

  # 🚅 add callbacks above.

  # 🚅 add delegations above.

  # 🚅 add methods above.
end
