# Guided 4-step SES setup wizard. Reachable at /account/teams/:slug/
# email_sending/setup and from the dashboard onboarding banner. Auto-
# advances based on the team's current SesConfiguration + SesDomain
# state so users can leave and resume without losing their place.
#
# Steps:
#   1. credentials    — paste AWS access key / secret / region (auto-verify)
#   2. domain         — enter sending domain + (optional) postal address
#   3. verify_domain  — display 3 DKIM CNAMEs, poll SES until DKIM SUCCESS
#   4. test           — send a real "you're wired up" email through their SES
#   done             — terminal state, redirect to the management view
#
# Step computation lives in `current_step` — every action calls it after
# any mutation and the view branches off it.
#
# Per-email identity verification (the older Ses::IdentityCreator code path)
# is intentionally still wired up via Account::SenderAddressesController,
# but no longer surfaced in the wizard's primary track. Domain is the
# blessed onboarding path.
class Account::EmailSendingSetupController < Account::ApplicationController
  include Billing::RequiresSubscriptionForSes
  load_and_authorize_resource :team, class: "Team", parent: false, id_param: :team_id

  before_action :load_ses_configuration
  before_action :load_ses_domain
  # Paywall must run AFTER load_and_authorize_resource so @team is set.
  before_action :require_active_subscription_for_ses, only: :update_credentials

  STEPS = %i[credentials domain verify_domain test done].freeze

  # GET /account/teams/:team_id/email_sending/setup
  def show
    authorize! :manage, @ses_configuration
    @step = current_step
    @verifier_result = nil
  end

  # PATCH /account/teams/:team_id/email_sending/setup
  # Step 1 submit. Mirrors EmailSendingController#update — saves creds,
  # immediately verifies, advances on success.
  def update_credentials
    authorize! :manage, @ses_configuration
    if @ses_configuration.update(credentials_params)
      @verifier_result = Ses::Verifier.new(team: @team).call
      write_verifier_result(@verifier_result)
      if @verifier_result.status == "verified"
        redirect_to account_team_setup_email_sending_path(@team), notice: "Credentials verified — let's set up your sending domain."
      else
        flash.now[:alert] = "SES rejected those credentials: #{@verifier_result.error}"
        @step = :credentials
        render :show, status: :unprocessable_entity
      end
    else
      @step = :credentials
      render :show, status: :unprocessable_entity
    end
  end

  # POST /account/teams/:team_id/email_sending/setup/domain
  # Step 2 submit. Persists the domain + postal address, asks SES to
  # create the DKIM identity, then advances to the verify-DKIM step where
  # the user installs the 3 CNAMEs.
  def submit_domain
    authorize! :manage, @ses_configuration

    # Save postal address on the SES configuration regardless of domain
    # outcome — partial progress should stick. Postal address is optional
    # so a blank value is fine.
    @ses_configuration.update(physical_postal_address: postal_address_param)

    domain_attr = params.dig(:team_ses_domain, :domain).to_s.strip
    if domain_attr.blank?
      flash.now[:alert] = "Enter a sending domain (e.g. hey.example.com)."
      @step = :domain
      render :show, status: :unprocessable_entity
      return
    end

    @ses_domain = @team.ses_domain || @team.build_ses_domain
    @ses_domain.domain = domain_attr

    if @ses_domain.save
      result = Ses::DomainIdentityCreator.new(ses_domain: @ses_domain).call
      if result.ok?
        redirect_to account_team_setup_email_sending_path(@team),
          notice: "Add the three CNAMEs below — we'll detect DKIM verification automatically."
      else
        flash.now[:alert] = result.message
        @step = :domain
        render :show, status: :unprocessable_entity
      end
    else
      flash.now[:alert] = @ses_domain.errors.full_messages.to_sentence
      @step = :domain
      render :show, status: :unprocessable_entity
    end
  end

  # GET /account/teams/:team_id/email_sending/setup/domain_status
  # Step 3 polling endpoint. The wizard JS hits this every few seconds
  # while waiting on DKIM verification. Returns JSON the front-end uses
  # to decide whether to advance to step 4.
  def domain_status
    authorize! :manage, @ses_configuration
    if @ses_domain.nil?
      render json: {state: "no_domain"}
      return
    end
    result = Ses::DomainIdentityChecker.new(ses_domain: @ses_domain).call
    render json: {
      state: @ses_domain.reload.status,
      verification_status: @ses_domain.verification_status,
      dkim_status: @ses_domain.dkim_status,
      checked: result.ok?
    }
  end

  # POST /account/teams/:team_id/email_sending/setup/test
  # Step 4 — fires a real send through the user's SES to their own inbox.
  def send_test
    authorize! :manage, @ses_configuration
    sender = verified_sender
    if sender.nil?
      redirect_to account_team_setup_email_sending_path(@team), alert: "No verified sender yet — wait for DKIM to finish propagating."
      return
    end
    result = Ses::TestSender.new(team: @team, sender_address: sender, to_email: current_user.email).call
    if result.ok?
      redirect_to account_team_setup_email_sending_path(@team),
        notice: "Test sent to #{current_user.email}. Check your inbox — that's your last setup step."
    else
      flash.now[:alert] = result.error_message
      @step = :test
      render :show, status: :unprocessable_entity
    end
  end

  private

  def load_ses_configuration
    @ses_configuration = @team.ses_configuration || @team.build_ses_configuration
  end

  def load_ses_domain
    @ses_domain = @team.ses_domain
  end

  # Drives the view. Reads the team's current state to decide which step
  # to show. Recomputed after every mutation so the wizard auto-advances.
  def current_step
    return :credentials   unless @ses_configuration.persisted? && @ses_configuration.verified?
    return :domain        if @ses_domain.nil?
    return :verify_domain unless @ses_domain.verified?
    return :done          if @ses_configuration.last_test_sent_at.present?
    :test
  end

  # First verified sender on the verified domain — auto-provisioned by
  # Ses::DomainIdentityChecker. May still be nil if the provisioning hit
  # an unexpected error (rare; the checker logs + carries on).
  def verified_sender
    return nil if @ses_domain.nil? || !@ses_domain.verified?
    @team.sender_addresses
      .where(verified: true)
      .where("LOWER(email) LIKE ?", "%@#{@ses_domain.domain}")
      .order(created_at: :asc)
      .first
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

  def credentials_params
    params.require(:team_ses_configuration).permit(
      :encrypted_access_key_id,
      :encrypted_secret_access_key,
      :region
    ).tap do |p|
      # Mirror EmailSendingController's masking logic — blank means "keep
      # what's already saved" so a user editing the form doesn't have to
      # re-paste the secret every time.
      p.delete(:encrypted_access_key_id)     if p[:encrypted_access_key_id].blank?     && @ses_configuration.configured?
      p.delete(:encrypted_secret_access_key) if p[:encrypted_secret_access_key].blank? && @ses_configuration.configured?
      p[:status] = "verifying"
    end
  end

  def postal_address_param
    params.dig(:team_ses_configuration, :physical_postal_address).to_s
  end
end
