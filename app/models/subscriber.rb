class Subscriber < ApplicationRecord
  include Mailkick::Model
  has_subscriptions
  # 🚅 add concerns above.

  # PII at rest — encrypted via Rails 8 ActiveRecord Encryption with keys
  # stored in config/credentials.yml.enc. Email is :deterministic so we can
  # still `find_by(email:)` + idempotent upsert by email (LewsnetterRails
  # gem depends on this). Name is non-deterministic — we never query by it.
  #
  # `custom_attributes` is intentionally NOT encrypted: the segment compiler
  # runs json_extract() at the SQL layer, which would return ciphertext junk
  # if the column were encrypted. The tradeoff is documented in /privacy:
  # email + name are encrypted; segmentation metadata is filesystem-encrypted
  # only (Hetzner volume + Cloudflare R2 server-side encryption).
  #
  # support_unencrypted_data: true keeps reads working during the rollout —
  # existing plaintext rows are returned as-is; new writes are encrypted; a
  # backfill task (see db/seeds + ops doc) re-saves every row to upgrade
  # them in place.
  encrypts :email, deterministic: true, support_unencrypted_data: true
  encrypts :name,  support_unencrypted_data: true

  # 🚅 add attribute accessors above.

  belongs_to :team
  belongs_to :company, optional: true
  # 🚅 add belongs_to associations above.

  has_many :events, dependent: :destroy
  # 🚅 add has_many associations above.

  # 🚅 add has_one associations above.

  scope :subscribed, -> { where(subscribed: true) }
  scope :unsubscribed, -> { where(subscribed: false) }
  # 🚅 add scopes above.

  validates :email, presence: true
  validates :external_id, uniqueness: {scope: :team_id, allow_nil: true}
  # 🚅 add validations above.

  # 🚅 add callbacks above.

  # 🚅 add delegations above.

  # 🚅 add methods above.
end
