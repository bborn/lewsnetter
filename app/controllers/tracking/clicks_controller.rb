# Click-tracking redirect endpoint. CampaignRenderer rewrites every trackable
# `<a href>` in outbound campaign HTML to a `/track/c/:token` URL whose token
# carries a signed payload of `{delivery_id, url}`. When the recipient clicks,
# we stamp Delivery#clicked_at (first click only), bump click_count, record
# the URL as last_clicked_url, then 302 to the real destination.
#
# Why 302, not 301: a 301 would let browsers cache the redirect and skip the
# tracking call on subsequent clicks. We want every click recorded.
#
# Open-redirect safety: the destination URL is part of a signed payload, so
# attackers can't construct a tracking URL that 302s to arbitrary places —
# they'd need the app's signing secret. If anything is malformed, we fall
# back to the root URL so a broken email doesn't take recipients to 404.
class Tracking::ClicksController < ApplicationController
  skip_before_action :verify_authenticity_token, raise: false
  skip_before_action :authenticate_user!, raise: false

  def show
    payload = decode_token(params[:token].to_s)
    delivery = payload && Delivery.find_by(id: payload[:delivery_id])
    url = payload && payload[:url].to_s

    if delivery && url.present?
      record_click(delivery, url)
      redirect_to url, allow_other_host: true, status: :found
    else
      # Token bad, delivery gone, or URL missing → quietly bounce to root.
      # We don't surface an error page because the recipient has no way to
      # act on it; the campaign owner sees the missing click in the stats.
      redirect_to root_url, allow_other_host: false, status: :found
    end
  end

  private

  def decode_token(token)
    return nil if token.blank?
    raw = Rails.application.message_verifier(:delivery_click).verify(token)
    return nil unless raw.is_a?(Hash)
    {
      delivery_id: raw["delivery_id"] || raw[:delivery_id],
      url: raw["url"] || raw[:url]
    }
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  def record_click(delivery, url)
    # `update_columns` to bypass validations + callbacks (and skip a row-load
    # round-trip). `click_count` is a counter we increment in-place — using
    # SQL arithmetic to avoid lost-update races between simultaneous clicks.
    now = Time.current
    Delivery
      .where(id: delivery.id)
      .update_all([
        "clicked_at = COALESCE(clicked_at, ?), click_count = click_count + 1, " \
          "last_clicked_url = ?, updated_at = ?",
        now,
        url[0, 2048], # truncate defensively — text columns are unbounded but
        # we don't want a 10MB URL.
        now
      ])
  rescue => e
    # Don't break the redirect over a stats write failure. The recipient
    # still gets where they were going; we just lose this click event.
    Rails.logger.warn(
      "[Tracking::Clicks] failed to record click for delivery=#{delivery.id}: #{e.class}: #{e.message}"
    )
  end
end
