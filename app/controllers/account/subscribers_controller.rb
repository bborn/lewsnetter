class Account::SubscribersController < Account::ApplicationController
  account_load_and_authorize_resource :subscriber, through: :team, through_association: :subscribers

  # GET /account/teams/:team_id/subscribers
  # GET /account/teams/:team_id/subscribers.json
  def index
    delegate_json_to_api
  end

  # GET /account/subscribers/:id
  # GET /account/subscribers/:id.json
  def show
    delegate_json_to_api
  end

  # GET /account/teams/:team_id/subscribers/new
  def new
  end

  # GET /account/subscribers/:id/edit
  def edit
  end

  # POST /account/teams/:team_id/subscribers
  # POST /account/teams/:team_id/subscribers.json
  def create
    respond_to do |format|
      if @subscriber.save
        format.html { redirect_to [:account, @subscriber], notice: I18n.t("subscribers.notifications.created") }
        format.json { render :show, status: :created, location: [:account, @subscriber] }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @subscriber.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /account/subscribers/:id
  # PATCH/PUT /account/subscribers/:id.json
  def update
    respond_to do |format|
      if @subscriber.update(subscriber_params)
        format.html { redirect_to [:account, @subscriber], notice: I18n.t("subscribers.notifications.updated") }
        format.json { render :show, status: :ok, location: [:account, @subscriber] }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @subscriber.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /account/subscribers/:id
  # DELETE /account/subscribers/:id.json
  def destroy
    @subscriber.destroy
    respond_to do |format|
      format.html { redirect_to [:account, @team, :subscribers], notice: I18n.t("subscribers.notifications.destroyed") }
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
