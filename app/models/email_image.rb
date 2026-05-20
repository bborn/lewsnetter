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
# `:file` attachment lives in the `email_media` Active Storage service — a
# dedicated PRIVATE R2 bucket. Inboxes reach the image through a Rails
# redirect (GET /e/:id → EmailImagesController#show → 302 to a fresh signed
# R2 URL). The permanent URL is the Rails route itself, served on the team's
# OWN branded email host, so a tenant's email carries zero
# app.lewsnetter.dev references.
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
  # Signed-id purpose for the /e/:id route token. A purpose-scoped signed id
  # is unguessable (so /e/1, /e/2 enumeration can't reach another team's
  # images) and — with no expires_in — permanent, which a URL baked into a
  # sent email must be.
  SIGNED_ID_PURPOSE = :email_image

  # optional: true — an email image deliberately outlives its team. When a
  # team is destroyed the FK nullifies team_id (see the migration); the
  # image row, blob, and URL persist so a sent newsletter still renders.
  # A nil team is therefore a valid, expected state.
  belongs_to :team, optional: true

  # The image bytes. `service: :email_media` pins the blob to the dedicated
  # private R2 bucket. In test/development this resolves to local Disk (see
  # config/storage.yml).
  has_one_attached :file, service: :email_media

  validates :content_type, presence: true
  validate :file_must_be_an_attached_image

  # Resolve an EmailImage from the token in a /e/:id URL.
  def self.find_by_token(token)
    find_signed(token.to_s, purpose: SIGNED_ID_PURPOSE)
  end

  # The permanent URL baked into `<mj-image src>` / `![](…)` and shipped to
  # inboxes. It points at the Rails redirect route (GET /e/:id), NOT directly
  # at storage:
  #
  #   https://<team email host>/e/<signed id>
  #
  # The host is the team's branded email host — the SAME resolver that the
  # unsubscribe link + open pixel + click redirect use (UnsubscribeUrlHelper.
  # host_for). So every link in a tenant's email shares one host; recipients
  # never see app.lewsnetter.dev.
  #
  # The route is permanent because the signed id is permanent. Each request
  # to it 302-redirects to a freshly-signed (short-lived, fine) R2 URL — see
  # EmailImagesController. That's why the bucket can stay private.
  def public_url
    return nil unless file.attached?

    host = UnsubscribeUrlHelper.host_for(team: team)
    "https://#{host}/e/#{signed_id(purpose: SIGNED_ID_PURPOSE)}"
  end

  private

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
