class Team < ApplicationRecord
  include Teams::Base
  include Webhooks::Outgoing::TeamSupport

  # 🚅 add concerns above.

  # 🚅 add belongs_to associations above.

  has_many :subscribers, dependent: :destroy
  has_many :events, dependent: :destroy
  has_many :segments, dependent: :destroy
  has_many :email_templates, dependent: :destroy
  has_many :campaigns, dependent: :destroy
  has_many :sender_addresses, dependent: :destroy
  # 🚅 add has_many associations above.

  # 🚅 add oauth providers above.

  has_one :ses_configuration, class_name: "Team::SesConfiguration", dependent: :destroy
  # 🚅 add has_one associations above.

  # 🚅 add scopes above.

  # 🚅 add validations above.

  # 🚅 add callbacks above.

  # 🚅 add delegations above.

  # 🚅 add methods above.
end
