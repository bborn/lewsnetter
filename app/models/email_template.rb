class EmailTemplate < ApplicationRecord
  # 🚅 add concerns above.

  # Max attached asset size, kept in sync with Campaign#assets validation.
  # Recipients open emails days/weeks after we send them, so we host the
  # blobs on R2 + serve them through the rails_storage_proxy_url so the
  # URL is stable and non-expiring. 5 MB is generous for logos + hero
  # images while keeping email weight sane.
  ASSET_MAX_BYTES = 5.megabytes

  # 🚅 add attribute accessors above.

  belongs_to :team

  has_many :campaigns, dependent: :nullify

  # Image-only attachments (logos, hero images) for embedding in MJML +
  # markdown bodies. Stored via Active Storage; on production this maps
  # to the `:amazon` (Cloudflare R2) service. We validate each blob is
  # an image and under ASSET_MAX_BYTES on the model so it holds for
  # API + direct-upload paths, not just the form submit.
  has_many_attached :assets

  validates :name, presence: true
  validate :assets_must_be_images_under_max_size
  # 🚅 add belongs_to associations above.
  # 🚅 add belongs_to associations above.

  # 🚅 add has_many associations above.

  # 🚅 add has_one associations above.

  # 🚅 add scopes above.

  # 🚅 add validations above.

  # 🚅 add callbacks above.

  # 🚅 add delegations above.

  # 🚅 add methods above.

  private

  # Hand-rolled validator (vs. ActiveStorage::Validations gem) because we
  # only need two rules and want to avoid pulling another dep. Runs over
  # both already-persisted attachments AND any blobs newly attached in
  # the current save cycle.
  def assets_must_be_images_under_max_size
    return unless assets.attached?

    assets.each do |asset|
      blob = asset.blob
      content_type = blob.content_type.to_s
      unless content_type.start_with?("image/")
        errors.add(:assets, "must be an image (got #{content_type.presence || "unknown type"})")
      end

      if blob.byte_size > ASSET_MAX_BYTES
        size_mb = (ASSET_MAX_BYTES / 1.megabyte.to_f).round
        errors.add(:assets, "must be smaller than #{size_mb}MB")
      end
    end
  end
end
