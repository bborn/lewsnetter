class Account::SegmentsController < Account::ApplicationController
  account_load_and_authorize_resource :segment, through: :team, through_association: :segments

  # GET /account/teams/:team_id/segments
  # GET /account/teams/:team_id/segments.json
  def index
    delegate_json_to_api
  end

  # GET /account/segments/:id
  # GET /account/segments/:id.json
  def show
    delegate_json_to_api
  end

  # GET /account/teams/:team_id/segments/new
  def new
  end

  # GET /account/segments/:id/edit
  def edit
  end

  # POST /account/teams/:team_id/segments
  # POST /account/teams/:team_id/segments.json
  def create
    respond_to do |format|
      if @segment.save
        format.html { redirect_to [:account, @segment], notice: I18n.t("segments.notifications.created") }
        format.json { render :show, status: :created, location: [:account, @segment] }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @segment.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /account/segments/:id
  # PATCH/PUT /account/segments/:id.json
  def update
    respond_to do |format|
      if @segment.update(segment_params)
        format.html { redirect_to [:account, @segment], notice: I18n.t("segments.notifications.updated") }
        format.json { render :show, status: :ok, location: [:account, @segment] }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @segment.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /account/segments/:id
  # DELETE /account/segments/:id.json
  def destroy
    @segment.destroy
    respond_to do |format|
      format.html { redirect_to [:account, @team, :segments], notice: I18n.t("segments.notifications.destroyed") }
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
