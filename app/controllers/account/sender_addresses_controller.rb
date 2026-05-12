class Account::SenderAddressesController < Account::ApplicationController
  account_load_and_authorize_resource :sender_address,
    through: :team,
    through_association: :sender_addresses,
    member_actions: [:recheck]

  # GET /account/teams/:team_id/sender_addresses
  # GET /account/teams/:team_id/sender_addresses.json
  def index
    delegate_json_to_api
  end

  # GET /account/sender_addresses/:id
  # GET /account/sender_addresses/:id.json
  def show
    delegate_json_to_api
  end

  # GET /account/teams/:team_id/sender_addresses/new
  def new
  end

  # GET /account/sender_addresses/:id/edit
  def edit
  end

  # POST /account/teams/:team_id/sender_addresses
  # POST /account/teams/:team_id/sender_addresses.json
  def create
    respond_to do |format|
      if @sender_address.save
        # Verified + ses_status are derived from SES, not from user input.
        Ses::IdentityChecker.new(sender_address: @sender_address).call
        format.html { redirect_to [:account, @sender_address], notice: I18n.t("sender_addresses.notifications.created") }
        format.json { render :show, status: :created, location: [:account, @sender_address] }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @sender_address.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /account/sender_addresses/:id
  # PATCH/PUT /account/sender_addresses/:id.json
  def update
    respond_to do |format|
      if @sender_address.update(sender_address_params)
        # Re-check SES if the email changed (or always — cheap call).
        Ses::IdentityChecker.new(sender_address: @sender_address).call
        format.html { redirect_to [:account, @sender_address], notice: I18n.t("sender_addresses.notifications.updated") }
        format.json { render :show, status: :ok, location: [:account, @sender_address] }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @sender_address.errors, status: :unprocessable_entity }
      end
    end
  end

  # POST /account/sender_addresses/:id/recheck
  #
  # Re-queries SES for verification status and writes the result back.
  # Used by the show page's "Re-check" button.
  def recheck
    Ses::IdentityChecker.new(sender_address: @sender_address).call
    redirect_to [:account, @sender_address], notice: I18n.t("sender_addresses.notifications.rechecked")
  end

  # DELETE /account/sender_addresses/:id
  # DELETE /account/sender_addresses/:id.json
  def destroy
    @sender_address.destroy
    respond_to do |format|
      format.html { redirect_to [:account, @team, :sender_addresses], notice: I18n.t("sender_addresses.notifications.destroyed") }
      format.json { head :no_content }
    end
  end

  private

  if defined?(Api::V1::ApplicationController)
    include strong_parameters_from_api
  end

  def process_params(strong_params)
    # 🚅 super scaffolding will insert processing for new fields above this line.
  end
end
