# Public unsubscribe endpoint. Both GET (link click from email) and POST
# (RFC 8058 one-click "List-Unsubscribe-Post") hit the same #update action.
# No authentication — the signed token IS the credential.
class UnsubscribeController < ApplicationController
  # BulletTrain's base controller pulls in protect_from_forgery; the
  # one-click POST from email clients won't carry a CSRF token, so we skip
  # it for this public endpoint only.
  skip_before_action :verify_authenticity_token, raise: false
  skip_before_action :authenticate_user!, raise: false

  layout "unsubscribe"

  def update
    subscriber = find_subscriber

    if subscriber.nil?
      # We deliberately do NOT 404 here: a real subscriber clicking a stale or
      # malformed link must not be left thinking we lost track of them. Render
      # the friendly "this link is invalid or expired" page (still 200) with a
      # mailto fallback so they can get a human to remove them.
      @status = :invalid
      @unsubscribe_team_name = nil
      render :update
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
    @team = subscriber.team
    @unsubscribe_team_name = @team&.name
    @status = :ok
    render :update
  end

  private

  def find_subscriber
    token = params[:token].to_s
    return nil if token.blank?

    # Tokens MUST be signed global IDs. We previously fell back to
    # `Subscriber.find_by(id: token)` for "legacy / manual links" — that path
    # let any unauthenticated attacker iterate /unsubscribe/1, /unsubscribe/2,
    # etc., and mass-unsubscribe every team's subscribers. The signed token is
    # now the only acceptable credential. See docs/security/2026-05-19-data-isolation-audit.md (C1).
    GlobalID::Locator.locate_signed(token, for: "unsubscribe")
  rescue
    nil
  end
end
