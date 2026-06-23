class Subscriber < ApplicationRecord
  include Mailkick::Model

  has_subscriptions
  # 🚅 add concerns above.

  # PII at rest — only `email` is encrypted (deterministic so find_by + the
  # lewsnetter-rails upsert path still work). `name` is plaintext: it's
  # low-stakes PII (LinkedIn, bylines, business cards) and non-deterministic
  # encryption made search/LIKE impossible, breaking subscriber search,
  # cmd-K, and any segment filtering on name. The DecryptSubscriberNames
  # migration (2026-05-18) backfilled all existing rows to plaintext.
  #
  # `custom_attributes` is also intentionally plaintext: the segment compiler
  # runs json_extract() at the SQL layer, which would return ciphertext junk
  # if the column were encrypted. The tradeoff is documented in /privacy:
  # email is encrypted; everything else is filesystem-encrypted only
  # (Hetzner volume + Cloudflare R2 server-side encryption).
  #
  # support_unencrypted_data on email keeps reads working for any legacy
  # plaintext rows from before the email encryption rollout.
  encrypts :email, deterministic: true, support_unencrypted_data: true

  # 🚅 add attribute accessors above.

  belongs_to :team
  belongs_to :company, optional: true
  # 🚅 add belongs_to associations above.

  has_many :events, dependent: :destroy
  # Per-campaign delivery rows for this subscriber. Lets us answer "what
  # have we sent this person, and how did it land?" — and they cascade so
  # GDPR-style subscriber deletes don't leave orphan delivery rows.
  has_many :deliveries, dependent: :destroy
  # 🚅 add has_many associations above.

  # 🚅 add has_one associations above.

  scope :subscribed, -> { where(subscribed: true) }
  scope :unsubscribed, -> { where(subscribed: false) }
  # 🚅 add scopes above.

  validates :email, presence: true
  validates :external_id, uniqueness: {scope: :team_id, allow_nil: true}
  # 🚅 add validations above.

  before_save :set_email_domain
  # 🚅 add callbacks above.

  # 🚅 add delegations above.

  # 🚅 add methods above.

  private

  # Derive the email's domain into a plaintext, indexable column so segments
  # can filter by domain (e.g. everyone @acme.com) without decrypting the
  # `email` column. The full address stays encrypted (deterministic); only the
  # lower-stakes domain part is materialized for querying. Runs on every save
  # so it tracks email changes.
  def set_email_domain
    self.email_domain = email.to_s.split("@", 2)[1]&.downcase
  end
end
