class User < ApplicationRecord
  include Users::Base
  include Roles::User
  # 🚅 add concerns above.

  # 🚅 add belongs_to associations above.

  has_many :chats, dependent: :destroy
  # 🚅 add has_many associations above.

  # 🚅 add oauth providers above.

  # 🚅 add has_one associations above.

  # 🚅 add scopes above.

  # 🚅 add validations above.

  # 🚅 add callbacks above.

  # 🚅 add delegations above.

  # 🚅 add methods above.
end
