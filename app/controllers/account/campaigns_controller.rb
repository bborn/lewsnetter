class Account::CampaignsController < Account::ApplicationController
  account_load_and_authorize_resource :campaign, through: :team, through_association: :campaigns

  # GET /account/teams/:team_id/campaigns
  # GET /account/teams/:team_id/campaigns.json
  def index
    delegate_json_to_api
  end

  # GET /account/campaigns/:id
  # GET /account/campaigns/:id.json
  def show
    delegate_json_to_api
  end

  # GET /account/teams/:team_id/campaigns/new
  def new
  end

  # GET /account/campaigns/:id/edit
  def edit
  end

  # POST /account/teams/:team_id/campaigns
  # POST /account/teams/:team_id/campaigns.json
  def create
    respond_to do |format|
      if @campaign.save
        format.html { redirect_to [:account, @campaign], notice: I18n.t("campaigns.notifications.created") }
        format.json { render :show, status: :created, location: [:account, @campaign] }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @campaign.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /account/campaigns/:id
  # PATCH/PUT /account/campaigns/:id.json
  def update
    respond_to do |format|
      if @campaign.update(campaign_params)
        format.html { redirect_to [:account, @campaign], notice: I18n.t("campaigns.notifications.updated") }
        format.json { render :show, status: :ok, location: [:account, @campaign] }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @campaign.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /account/campaigns/:id
  # DELETE /account/campaigns/:id.json
  def destroy
    @campaign.destroy
    respond_to do |format|
      format.html { redirect_to [:account, @team, :campaigns], notice: I18n.t("campaigns.notifications.destroyed") }
      format.json { head :no_content }
    end
  end

  private

  if defined?(Api::V1::ApplicationController)
    include strong_parameters_from_api
  end

  def process_params(strong_params)
    assign_date_and_time(strong_params, :scheduled_for)
    # 🚅 super scaffolding will insert processing for new fields above this line.
  end
end
