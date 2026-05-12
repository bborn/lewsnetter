class Account::EmailTemplatesController < Account::ApplicationController
  account_load_and_authorize_resource :email_template, through: :team, through_association: :email_templates

  # GET /account/teams/:team_id/email_templates
  # GET /account/teams/:team_id/email_templates.json
  def index
    delegate_json_to_api
  end

  # GET /account/email_templates/:id
  # GET /account/email_templates/:id.json
  def show
    delegate_json_to_api
  end

  # GET /account/teams/:team_id/email_templates/new
  def new
  end

  # GET /account/email_templates/:id/edit
  def edit
  end

  # POST /account/teams/:team_id/email_templates
  # POST /account/teams/:team_id/email_templates.json
  def create
    respond_to do |format|
      if @email_template.save
        format.html { redirect_to [:account, @email_template], notice: I18n.t("email_templates.notifications.created") }
        format.json { render :show, status: :created, location: [:account, @email_template] }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @email_template.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /account/email_templates/:id
  # PATCH/PUT /account/email_templates/:id.json
  def update
    respond_to do |format|
      if @email_template.update(email_template_params)
        format.html { redirect_to [:account, @email_template], notice: I18n.t("email_templates.notifications.updated") }
        format.json { render :show, status: :ok, location: [:account, @email_template] }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @email_template.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /account/email_templates/:id
  # DELETE /account/email_templates/:id.json
  def destroy
    @email_template.destroy
    respond_to do |format|
      format.html { redirect_to [:account, @team, :email_templates], notice: I18n.t("email_templates.notifications.destroyed") }
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
