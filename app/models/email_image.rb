# An EmailImage is a permanent home for an image embedded in a sent email.
#
# WHY THIS MODEL EXISTS
# ---------------------
# Campaign/EmailTemplate images used to be `has_many_attached :assets` blobs
# whose `<mj-image src>` pointed at an Active Storage *proxy* URL. Active
# Storage's attachment lifecycle is ORM-coupled: destroy the record (or churn
# the attachment) and the blob gets purged. When that happens, every email
# that embedded the URL breaks — INCLUDING emails already sitting in
# recipients' inboxes. An image in a sent email must outlive everything.
#
# EmailImage decouples the blob's lifecycle from any editable record. Its
# `:file` attachment lives in the `email_media` Active Storage service, which
# is configured `public: true` (see config/storage.yml) and backed by a
# dedicated public R2 bucket. The image is served directly from a custom
# domain — no expiring signature, no proxy controller, no app round-trip.
#
# NEVER DESTROYED BY THE APP — DELIBERATE
# ---------------------------------------
# There is intentionally NO `dependent: :destroy` reaching EmailImage:
#   - Team `has_many :email_images` WITHOUT `dependent: :destroy`
#   - Templates/campaigns do not own EmailImages at all
# Destroying a template, a campaign, or even a whole team must NOT delete its
# email images, because already-sent emails reference them forever. These
# rows (and their blobs) are kept on purpose. Cleanup, if ever needed, is an
# explicit, deliberate operator action — never an app-driven cascade.
class EmailImage < ApplicationRecord
  belongs_to :team

  # The image bytes. `service: :email_media` routes the blob to the
  # `public: true` R2 bucket so the object is world-readable and its URL is
  # permanent. In test/development this is overridden by the `:test`/`:local`
  # disk services per config/environments.
  has_one_attached :file, service: :email_media

  validates :content_type, presence: true
  validate :file_must_be_an_attached_image

  # The permanent, non-expiring, public URL for this image — the value that
  # gets baked into `<mj-image src>` / `![](…)` and shipped to inboxes.
  #
  # THE R2 PUBLIC-URL WRINKLE
  # -------------------------
  # Cloudflare R2's S3-compatible endpoint (`*.r2.cloudflarestorage.com`) is
  # NOT publicly readable even for a "public" bucket — it always requires
  # SigV4 auth. A public R2 bucket is served via an `r2.dev` subdomain or a
  # bound custom domain. So Active Storage's default `blob.url` for a
  # `public: true` S3 service (built off the configured `endpoint`) would
  # produce a URL that 403s.
  #
  # We sidestep Active Storage's URL builder entirely and construct the URL
  # against the custom domain ourselves: `https://EMAIL_MEDIA_HOST/<key>`.
  # `EMAIL_MEDIA_HOST` is an env var so self-hosters point it at their own
  # bucket's public host. If it's blank (unconfigured), we fall back to the
  # Active Storage proxy URL and log a warning — functional, but the proxy
  # URL is app-coupled and not as durable, so operators should set the host.
  def public_url
    blob = file.blob
    return nil if blob.nil?

    host = ENV["EMAIL_MEDIA_HOST"].to_s.strip
    if host.present?
      "https://#{host}/#{blob.key}"
    else
      Rails.logger.warn(
        "[EmailImage##{id}] EMAIL_MEDIA_HOST is not set — falling back to the " \
        "Active Storage proxy URL. Set EMAIL_MEDIA_HOST to the public bucket " \
        "host (e.g. media.lewsnetter.dev) so sent-email image URLs are permanent."
      )
      Rails.application.routes.url_helpers.rails_storage_proxy_url(
        blob, only_path: false, host: default_url_host
      )
    end
  end

  private

  # Host used only for the proxy-URL fallback when EMAIL_MEDIA_HOST is unset.
  def default_url_host
    Rails.application.config.action_mailer.default_url_options&.dig(:host) ||
      Rails.application.routes.default_url_options[:host] ||
      "localhost"
  end

  def file_must_be_an_attached_image
    unless file.attached?
      errors.add(:file, "must be attached")
      return
    end

    type = file.blob.content_type.to_s
    unless type.start_with?("image/")
      errors.add(:file, "must be an image (got #{type.presence || "unknown type"})")
    end
  end
end
