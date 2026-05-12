class Subscribers::Import < ApplicationRecord
  self.table_name = "subscribers_imports"

  # 🚅 add concerns above.

  has_one_attached :csv
  # 🚅 add attribute accessors above.

  belongs_to :team
  # 🚅 add belongs_to associations above.

  # 🚅 add has_many associations above.

  # 🚅 add has_one associations above.

  STATUSES = %w[pending processing completed failed].freeze

  # 🚅 add scopes above.

  validates :status, inclusion: {in: STATUSES}
  validates :csv, presence: true
  # 🚅 add validations above.

  # 🚅 add callbacks above.

  # 🚅 add delegations above.

  STATUSES.each do |s|
    define_method("#{s}?") { status == s }
  end

  def label_string
    "Import ##{id} (#{status})"
  end
  # 🚅 add methods above.
end
