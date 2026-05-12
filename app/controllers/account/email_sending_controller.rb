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
  # CanCanCan loads @team from `params[:team_id]` and authorizes the current
  # user can :read it. Then `load_ses_configuration` materializes the
  # singleton-per-team Team::SesConfiguration record and we authorize the
  # action against that record explicitly (since CanCan only knows about the
  # Team here).
  load_and_authorize_resource :team, class: "Team", parent: false,
    id_param: :team_id

  before_action :load_ses_configuration

  # GET /account/teams/:team_id/email_sending
  def show
    authorize! :read, @ses_configuration
    @verifier_result = nil
  end

  # PATCH /account/teams/:team_id/email_sending
  def update
    authorize! :manage, @ses_configuration

    if @ses_configuration.update(ses_configuration_params)
      # If credentials changed, run a fresh verification automatically.
      if creds_changed?
        @verifier_result = Ses::Verifier.new(team: @team).call
        write_verifier_result(@verifier_result)
        redirect_to [:account, @team, :email_sending],
          notice: verification_notice(@verifier_result)
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

    redirect_to [:account, @team, :email_sending],
      notice: verification_notice(@verifier_result)
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

  def load_ses_configuration
    @ses_configuration = @team.ses_configuration || @team.build_ses_configuration
  end

  def ses_configuration_params
    params.require(:team_ses_configuration).permit(
      :encrypted_access_key_id,
      :encrypted_secret_access_key,
      :region,
      :sns_bounce_topic_arn,
      :sns_complaint_topic_arn,
      :unsubscribe_host
    )
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
