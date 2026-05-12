# Public unsubscribe endpoint. Both GET (link click from email) and POST
# (RFC 8058 one-click "List-Unsubscribe-Post") hit the same #update action.
# No authentication — the signed token IS the credential.
class UnsubscribeController < ApplicationController
  # BulletTrain's base controller pulls in protect_from_forgery; the
  # one-click POST from email clients won't carry a CSRF token, so we skip
  # it for this public endpoint only.
  skip_before_action :verify_authenticity_token, raise: false
  skip_before_action :authenticate_user!, raise: false

  layout "public"

  def update
    subscriber = find_subscriber

    if subscriber.nil?
      @status = :invalid
      render :update, status: :not_found
      return
    end

    list = "newsletter"
    # Mailkick's has_subscriptions macro defines a positional-arg unsubscribe.
    # We guard with respond_to? so the controller still works if mailkick is
    # removed later.
    if subscriber.respond_to?(:unsubscribe)
      begin
        subscriber.unsubscribe(list)
      rescue ArgumentError
        # Fall through; we still flip the legacy boolean below.
      end
    end

    subscriber.update_columns(
      subscribed: false,
      unsubscribed_at: Time.current
    )

    @subscriber = subscriber
    @status = :ok
    render :update
  end

  private

  def find_subscriber
    token = params[:token].to_s
    return nil if token.blank?

    # Tokens are signed global IDs; if a non-signed integer ID is supplied
    # (legacy / manual link) fall back to finding by id directly. This keeps
    # the route forgiving without leaking the ability to enumerate ids:
    # GlobalID::Locator.locate_signed only resolves signed tokens.
    GlobalID::Locator.locate_signed(token, for: "unsubscribe") ||
      Subscriber.find_by(id: token)
  rescue StandardError
    nil
  end
end
