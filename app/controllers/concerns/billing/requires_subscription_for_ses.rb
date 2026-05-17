# Narrow paywall: saving Amazon SES credentials requires either an active
# Pro subscription or a member on the BILLING_EXEMPT_EMAILS allowlist.
# Everything else in the app stays free.
#
# Mixed into the two controllers that can write SES credentials:
#   - Account::EmailSendingSetupController (4-step wizard)
#   - Account::EmailSendingController     (settings page)
#
# Assumes @team has already been loaded by `account_load_and_authorize_resource`.
module Billing::RequiresSubscriptionForSes
  extend ActiveSupport::Concern

  private

  def require_active_subscription_for_ses
    return if @team.billing_exempt?
    return if @team.current_billing_subscription.present?

    redirect_to account_team_billing_subscriptions_path(@team),
      alert: "Connecting Amazon SES requires a Pro subscription ($10/month). Pick a plan to continue."
  end

  # Settings page's #update accepts both credential and non-credential
  # changes (region, unsubscribe_host, etc.) in one payload. Only gate
  # the request when the submitter is actually trying to set new AWS keys.
  def require_active_subscription_for_ses_if_credentials_present
    submitted_creds = [
      params.dig(:team_ses_configuration, :encrypted_access_key_id),
      params.dig(:team_ses_configuration, :encrypted_secret_access_key)
    ]
    return unless submitted_creds.any?(&:present?)

    require_active_subscription_for_ses
  end
end
