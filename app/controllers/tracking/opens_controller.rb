# Open-tracking pixel endpoint. Every campaign email has a 1x1 transparent
# GIF appended just before `</body>` whose `src` points here. When the
# recipient opens the email, the image client fetches this URL and we stamp
# `Delivery#opened_at` (idempotent — only first open counts so we don't
# overwrite the historical record).
#
# Mounted outside the Account:: namespace + skips both CSRF and Devise auth,
# because email clients are not logged-in browsers. The signed token IS the
# credential — without the app's signing secret, an attacker can't forge an
# open for someone else's delivery.
#
# Always responds with the GIF, even on bad/expired/missing tokens, so we
# don't leak which deliveries exist (and so a misconfigured image blocker
# doesn't cascade into a broken-looking email).
class Tracking::OpensController < ApplicationController
  skip_before_action :verify_authenticity_token, raise: false
  skip_before_action :authenticate_user!, raise: false

  # Standard 1x1 transparent GIF (43 bytes). Encoded as a binary string
  # constant so we don't reach for File.read on every request. ASCII-8BIT
  # encoding is important — these bytes are NOT UTF-8 and Rails will mangle
  # the response otherwise.
  TRANSPARENT_GIF = (
    "GIF89a\x01\x00\x01\x00\x00\x00\x00!\xF9\x04\x01\x00\x00\x00\x00," \
    "\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02\x01D\x00;"
  ).force_encoding(Encoding::ASCII_8BIT).freeze

  def show
    delivery = Delivery.find_by_tracking_token(params[:token].to_s, purpose: :delivery_open)

    if delivery && delivery.opened_at.nil?
      # Idempotent: only the FIRST open updates the row. Subsequent fetches
      # (caching proxies, "show images" twice in Gmail) leave the original
      # timestamp alone. We use update_columns to skip validations + callbacks
      # — there's no business rule on opened_at and we want this hot path to
      # stay cheap.
      delivery.update_columns(opened_at: Time.current, updated_at: Time.current)
    end

    send_pixel
  end

  private

  def send_pixel
    # Aggressively forbid caching so image-cache proxies (e.g. Gmail's image
    # proxy) don't suppress repeat opens on the same delivery — but note we
    # still stamp only on the first open, by design. The headers are belt +
    # suspenders for non-Gmail clients that respect Cache-Control.
    response.set_header("Cache-Control", "no-store, no-cache, must-revalidate, private")
    response.set_header("Pragma", "no-cache")
    response.set_header("Expires", "0")
    send_data TRANSPARENT_GIF, type: "image/gif", disposition: "inline"
  end
end
