# Guided 4-step SES setup wizard. Reachable at /account/teams/:slug/
# email_sending/setup and from the dashboard onboarding banner. Auto-
# advances based on the team's current SesConfiguration + SenderAddress
# state so users can leave and resume without losing their place.
#
# Steps:
#   1. credentials   — paste AWS access key / secret / region (auto-verify)
#   2. sender        — pick from already-verified SES identities OR add new
#   3. verify_sender — wait for the user to click the AWS verification link
#   4. test          — send a real "you're wired up" email through their SES
#   done            — terminal state, redirect to the management view
#
# Step computation lives in `current_step` — every action calls it after
# any mutation and the view branches off it.
class Account::EmailSendingSetupController < Account::ApplicationController
  load_and_authorize_resource :team, class: "Team", parent: false, id_param: :team_id

  before_action :load_ses_configuration

  STEPS = %i[credentials sender verify_sender test done].freeze

  # GET /account/teams/:team_id/email_sending/setup
  def show
    authorize! :manage, @ses_configuration
    @step = current_step
    @pending_sender = pending_sender
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
        redirect_to account_team_setup_email_sending_path(@team), notice: "Credentials verified — pick a sender next."
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

  # POST /account/teams/:team_id/email_sending/setup/sender
  # Step 2 submit. Two paths: pick an existing verified identity (import),
  # or add a new email (we ask SES to send a verification link).
  def select_sender
    authorize! :manage, @ses_configuration

    if params[:identity].present?
      # Import an already-verified SES identity as a SenderAddress.
      sender = @team.sender_addresses.create!(
        email: params[:identity],
        name: params[:name].presence,
        verified: true,
        ses_status: "verified",
        last_verified_at: Time.current
      )
      redirect_to account_team_setup_email_sending_path(@team), notice: "Imported #{sender.email}."
    elsif params[:new_email].present?
      sender = @team.sender_addresses.new(email: params[:new_email], name: params[:name].presence)
      if sender.save
        result = Ses::IdentityCreator.new(sender_address: sender).call
        if result.ok?
          redirect_to account_team_setup_email_sending_path(@team),
            notice: "Verification email sent to #{sender.email}. Click the link, then come back here."
        else
          sender.destroy
          flash.now[:alert] = result.message
          @step = :sender
          render :show, status: :unprocessable_entity
        end
      else
        flash.now[:alert] = sender.errors.full_messages.to_sentence
        @step = :sender
        render :show, status: :unprocessable_entity
      end
    else
      redirect_to account_team_setup_email_sending_path(@team), alert: "Pick an identity or enter a new email."
    end
  end

  # GET /account/teams/:team_id/email_sending/setup/sender_status
  # Step 3 polling endpoint. The wizard JS hits this every few seconds
  # while waiting on AWS verification. Returns JSON the front-end uses
  # to decide whether to advance to step 4.
  def sender_status
    authorize! :manage, @ses_configuration
    sender = pending_sender
    if sender.nil?
      render json: {state: "no_sender"}
    else
      result = Ses::IdentityChecker.new(sender_address: sender).call rescue nil
      render json: {
        state: sender.reload.verified? ? "verified" : "pending",
        ses_status: sender.ses_status,
        checked: !result.nil?
      }
    end
  end

  # POST /account/teams/:team_id/email_sending/setup/test
  # Step 4 — fires a real send through the user's SES to their own inbox.
  def send_test
    authorize! :manage, @ses_configuration
    sender = verified_sender
    if sender.nil?
      redirect_to account_team_setup_email_sending_path(@team), alert: "No verified sender yet."
      return
    end
    result = Ses::TestSender.new(team: @team, sender_address: sender, to_email: current_user.email).call
    if result.ok?
      redirect_to account_team_setup_email_sending_path(@team),
        notice: "Test sent to #{current_user.email}. Check your inbox — that's your last setup step."
    else
      flash.now[:alert] = result.error_message
      @step = :test
      @pending_sender = sender
      render :show, status: :unprocessable_entity
    end
  end

  private

  def load_ses_configuration
    @ses_configuration = @team.ses_configuration || @team.build_ses_configuration
  end

  # Drives the view. Reads the team's current state to decide which step
  # to show. Recomputed after every mutation so the wizard auto-advances.
  def current_step
    return :credentials  unless @ses_configuration.persisted? && @ses_configuration.verified?
    return :sender        if pending_sender.nil?
    return :verify_sender unless pending_sender.verified?
    return :done          if @ses_configuration.last_test_sent_at.present?
    :test
  end

  # The sender we're currently shepherding through verification. We pick
  # the most-recently-created sender so a user adding a 2nd address after
  # completing the wizard once flows through verification cleanly.
  def pending_sender
    @team.sender_addresses.order(created_at: :desc).first
  end

  def verified_sender
    @team.sender_addresses.where(verified: true).order(created_at: :desc).first
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
end
