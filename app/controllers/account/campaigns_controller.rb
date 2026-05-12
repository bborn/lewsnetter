class Account::CampaignsController < Account::ApplicationController
  account_load_and_authorize_resource :campaign,
    through: :team,
    through_association: :campaigns,
    member_actions: [:send_now, :test_send]

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

  # POST /account/campaigns/:id/send_now
  def send_now
    if @campaign.draft?
      SendCampaignJob.perform_later(@campaign.id)
      redirect_to [:account, @campaign], notice: "Campaign queued for sending."
    else
      redirect_to [:account, @campaign], alert: "Only draft campaigns can be sent."
    end
  end

  # POST /account/campaigns/:id/test_send
  #
  # Sends a single rendered copy of the campaign to the current user using the
  # same render pipeline as a real send (MJML → HTML → premailer-inlined +
  # variable substitution). What lands in the inbox is exactly what subscribers
  # would see. Bypasses segment + subscribed checks; never transitions the
  # campaign status; never records anything in stats. Subject is prefixed
  # [TEST] so a stray test in your inbox is obvious.
  def test_send
    fake_subscriber = Subscriber.new(
      team: @campaign.team,
      email: current_user.email,
      name: [current_user.first_name, current_user.last_name].compact.join(" "),
      external_id: "test-#{current_user.id}",
      subscribed: true,
      custom_attributes: {}
    )

    original_subject = @campaign.subject
    @campaign.subject = "[TEST] #{original_subject}"

    begin
      result = SesSender.send_bulk(campaign: @campaign, subscribers: [fake_subscriber])

      if result.failed.empty? && result.message_ids.any?
        redirect_to [:account, @campaign], notice: "Test email sent to #{current_user.email}."
      else
        error = result.failed.first&.dig(:error) || "Unknown error"
        redirect_to [:account, @campaign], alert: "Test send failed: #{error}"
      end
    ensure
      @campaign.subject = original_subject
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
