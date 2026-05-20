# Serves an EmailImage to a recipient's inbox. The permanent `<mj-image src>`
# URL is GET /e/:id (built by EmailImage#public_url on the team's branded
# host). This action resolves the signed-id token and 302-redirects to a
# freshly-signed R2 URL.
#
# Why a redirect instead of streaming the bytes: the redirect target is
# generated per-request, so it can be a short-lived signed URL — the
# email_media bucket never needs public access or a custom domain. And a
# 302 is far cheaper for the app than proxying image bytes; mail-provider
# image proxies (Gmail especially) fetch each image once and cache, so the
# app sees only a handful of hits per campaign.
#
# Mounted outside the Account:: namespace + skips CSRF and Devise auth —
# email clients are not logged-in browsers. The signed-id token IS the
# credential; without the app's signing secret it can't be forged, and it's
# purpose-scoped so it can't be swapped for any other signed value.
class EmailImagesController < ApplicationController
  skip_before_action :verify_authenticity_token, raise: false
  skip_before_action :authenticate_user!, raise: false

  # Populates ActiveStorage::Current.url_options from the request. Needed
  # when email_media resolves to the Disk service — dev, test, and any
  # self-hoster who hasn't pointed it at S3 — because Disk URLs are Rails
  # routes that need a host. A no-op for the S3 path (presigned URLs carry
  # their own host), so it's safe to always include.
  include ActiveStorage::SetCurrent

  def show
    # find_by_token returns nil for a missing record OR a bad/forged token —
    # both collapse to a plain 404, so no rescue is needed here.
    image = EmailImage.find_by_token(params[:id])

    unless image&.file&.attached?
      return head :not_found
    end

    # Let the image client + caching proxies hold the redirect for a day so
    # repeat opens don't re-hit the app. The redirect TARGET (the signed R2
    # URL) is regenerated fresh every time this action runs, so a cached
    # 302 never points at a stale signature.
    response.set_header("Cache-Control", "public, max-age=86400")
    redirect_to image.file.blob.url, allow_other_host: true, status: :found
  end
end
