# "Email Sending" is a singleton page under a Team — the team's SES
# configuration. We hand-roll this controller (rather than scaffolding it
# as a normal CRUD resource) because there's at most one record per team
# and the verb that matters is "verify these credentials," not "create
# another record."
#
# Authorization is loaded against the parent Team using BulletTrain's
# `account_load_and_authorize_resource`; we then ensure the
# Team::SesConfiguration exists via the has_one association and authorize
# the requested action against it.
class Account::EmailSendingController < Account::ApplicationController
  include Billing::RequiresSubscriptionForSes

  # CanCanCan loads @team from `params[:team_id]` and authorizes the current
  # user can :read it. Then `load_ses_configuration` materializes the
  # singleton-per-team Team::SesConfiguration record and we authorize the
  # action against that record explicitly (since CanCan only knows about the
  # Team here).
  load_and_authorize_resource :team, class: "Team", parent: false,
    id_param: :team_id

  before_action :load_ses_configuration
  # Paywall must run AFTER load_and_authorize_resource so @team is set.
  before_action :require_active_subscription_for_ses_if_credentials_present, only: :update

  # GET /account/teams/:team_id/email_sending
  def show
    authorize! :read, @ses_configuration
    @verifier_result = nil
    # If we just came back from a successful `verify` redirect, surface the
    # identities panel by re-running the verifier. We avoid this on cold loads
    # to keep the page snappy (list_email_identities is a network round-trip).
    if @ses_configuration.verified? && params[:show_identities].present?
      @verifier_result = Ses::Verifier.new(team: @team).call
    end
  end

  # PATCH /account/teams/:team_id/email_sending
  def update
    authorize! :manage, @ses_configuration

    if @ses_configuration.update(ses_configuration_params)
      # If credentials changed, run a fresh verification automatically.
      if creds_changed?
        @verifier_result = Ses::Verifier.new(team: @team).call
        write_verifier_result(@verifier_result)
        target = if @verifier_result.status == "verified"
          url_for([:account, @team, :email_sending, show_identities: 1])
        else
          url_for([:account, @team, :email_sending])
        end
        redirect_to target, notice: verification_notice(@verifier_result)
      else
        redirect_to [:account, @team, :email_sending],
          notice: I18n.t("email_sending.notifications.updated")
      end
    else
      render :show, status: :unprocessable_entity
    end
  end

  # POST /account/teams/:team_id/email_sending/verify
  def verify
    authorize! :manage, @ses_configuration

    @verifier_result = Ses::Verifier.new(team: @team).call
    write_verifier_result(@verifier_result)

    # On success: redirect with `show_identities=1` so the show action
    # re-fetches the identities list and renders the panel. On failure we
    # skip the identities re-fetch since SES wouldn't return any anyway.
    target = if @verifier_result.status == "verified"
      url_for([:account, @team, :email_sending, show_identities: 1])
    else
      url_for([:account, @team, :email_sending])
    end
    redirect_to target, notice: verification_notice(@verifier_result)
  end

  # POST /account/teams/:team_id/email_sending/verify_sns
  #
  # One-click SNS + SES configuration-set automation. Uses the team's
  # already-saved SES IAM credentials to create the three SNS topics
  # (bounces, complaints, deliveries), subscribe the Lewsnetter webhook
  # to each, ensure the SES configuration set + event destinations exist,
  # and write the topic ARNs back onto the team's ses_configuration so
  # the webhook can route incoming events. Idempotent — safe to re-run
  # to repair drift.
  def verify_sns
    authorize! :manage, @ses_configuration

    webhook_url = derive_webhook_url
    result = Ses::SnsAutoWire.new(team: @team, webhook_url: webhook_url).call

    if result.ok?
      redirect_to [:account, @team, :email_sending],
        notice: sns_auto_wire_notice(result)
    else
      redirect_to [:account, @team, :email_sending],
        alert: I18n.t("email_sending.notifications.sns_failed",
          default: "SNS setup hit an error: %{error}",
          error: result.error_message.to_s)
    end
  end

  # POST /account/teams/:team_id/email_sending/import_identity
  #
  # Body: { identity: "newsletter@example.com" } — comes from a checkbox
  # next to a verified SES identity in the verifier panel. Creates a
  # SenderAddress on this team so it shows up in the campaign composer.
  def import_identity
    authorize! :manage, @ses_configuration

    identity = params[:identity].to_s.strip
    if identity.blank?
      redirect_to([:account, @team, :email_sending],
        alert: I18n.t("email_sending.notifications.import_blank")) and return
    end

    existing = @team.sender_addresses.find_by(email: identity)
    if existing
      redirect_to [:account, @team, :email_sending],
        notice: I18n.t("email_sending.notifications.import_existing", email: identity)
    else
      @team.sender_addresses.create!(
        email: identity,
        verified: true,
        ses_status: "verified"
      )
      redirect_to [:account, @team, :email_sending],
        notice: I18n.t("email_sending.notifications.imported", email: identity)
    end
  end

  private

  # The webhook URL we register with SNS must be the public, AWS-reachable
  # one. In prod, BASE_URL is set; in dev/test, fall back to request.base_url
  # (won't actually receive AWS POSTs but lets the wire-up succeed against
  # stubbed clients in tests).
  def derive_webhook_url
    base = ENV["BASE_URL"].presence || request.base_url
    "#{base.chomp("/")}/webhooks/ses/sns"
  end

  def sns_auto_wire_notice(result)
    created = result.summary[:topics].values.count { |t| t[:action] == :created }
    existed = result.summary[:topics].values.count { |t| t[:action] == :exists }
    parts = []
    parts << "Created #{created} topic(s)" if created.positive?
    parts << "verified #{existed} existing" if existed.positive?
    parts << "configuration set #{result.summary.dig(:configuration_set, :action) || "ready"}"
    "SNS wiring complete: #{parts.join(", ")}."
  end

  def load_ses_configuration
    @ses_configuration = @team.ses_configuration || @team.build_ses_configuration
  end

  def ses_configuration_params
    permitted = params.require(:team_ses_configuration).permit(
      :encrypted_access_key_id,
      :encrypted_secret_access_key,
      :region,
      :configuration_set_name,
      :sns_bounce_topic_arn,
      :sns_complaint_topic_arn,
      :unsubscribe_host
    )
    # Blank credential fields mean "keep the existing value" — the form hides
    # the saved key behind a masked placeholder so an empty submit shouldn't
    # null out the stored credentials.
    permitted.delete(:encrypted_access_key_id) if permitted[:encrypted_access_key_id].blank?
    permitted.delete(:encrypted_secret_access_key) if permitted[:encrypted_secret_access_key].blank?
    permitted
  end

  def creds_changed?
    @ses_configuration.saved_change_to_encrypted_access_key_id? ||
      @ses_configuration.saved_change_to_encrypted_secret_access_key? ||
      @ses_configuration.saved_change_to_region?
  end

  def write_verifier_result(result)
    @ses_configuration.update!(
      status: result.status,
      quota_max_send_24h: result.quota_max,
      quota_sent_last_24h: result.quota_sent,
      sandbox: result.sandbox.nil? ? @ses_configuration.sandbox : result.sandbox,
      last_verified_at: (result.status == "verified") ? Time.current : @ses_configuration.last_verified_at
    )
  end

  def verification_notice(result)
    case result.status
    when "verified"
      I18n.t("email_sending.notifications.verified")
    when "failed"
      I18n.t("email_sending.notifications.failed", error: result.error)
    when "unconfigured"
      I18n.t("email_sending.notifications.unconfigured")
    else
      I18n.t("email_sending.notifications.verifying")
    end
  end
end
