class Account::EmailTemplatesController < Account::ApplicationController
  account_load_and_authorize_resource :email_template, through: :team, through_association: :email_templates,
    member_actions: [:preview_frame, :destroy_asset]

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

  # GET /account/email_templates/:id/preview_frame
  #
  # Renders the template chrome filled with a placeholder body so authors can
  # SEE what their reusable layout looks like before they commit to using it
  # on a real campaign. Built around an in-memory Campaign + sample
  # Subscriber so we don't pollute the DB.
  def preview_frame
    fake_subscriber = Subscriber.new(
      team: @email_template.team,
      email: current_user.email,
      name: [current_user.first_name, current_user.last_name].compact.join(" "),
      external_id: "template-preview-#{current_user.id}",
      subscribed: true,
      custom_attributes: sample_custom_attributes
    )

    fake_campaign = Campaign.new(
      team: @email_template.team,
      email_template: @email_template,
      subject: "Subject preview",
      preheader: "Preheader preview",
      body_markdown: sample_body_markdown,
      body_mjml: nil,
      status: "draft"
    )

    html =
      begin
        CampaignRenderer.new(campaign: fake_campaign, subscriber: fake_subscriber).call.html
      rescue => e
        Rails.logger.warn("[EmailTemplate#preview_frame] render failed: #{e.class}: #{e.message}")
        <<~HTML
          <!doctype html>
          <html><body style="font-family: system-ui, sans-serif; padding: 32px; color: #b91c1c;">
            <h1>Template preview failed</h1>
            <p>Couldn't render this MJML. Open <em>Edit</em> and check the source for syntax errors.</p>
            <pre style="white-space: pre-wrap; color: #6b7280;">#{ERB::Util.html_escape(e.message)}</pre>
          </body></html>
        HTML
      end

    render html: html.html_safe, layout: false # rubocop:disable Rails/OutputSafety
  end

  private

  def sample_body_markdown
    <<~MD
      ## Section heading

      This is sample body content so you can see how the template chrome wraps a
      campaign. The real campaign body goes here when this template is used.

      - Lists render in the template's body font
      - **Bold**, *italic*, and [links](https://example.com) get the chrome's typography

      [Sample call to action →](https://example.com)
    MD
  end

  def sample_custom_attributes
    # Pull a real subscriber's custom_attributes shape if any exist; otherwise
    # fall back to a tiny synthetic set so {{plan}} / {{subdomain}} placeholders
    # in the template don't render blank.
    sample = @email_template.team.subscribers.where.not(custom_attributes: {}).first
    return sample.custom_attributes if sample
    {"plan" => "growth", "subdomain" => "acme", "tenant_type" => "brand"}
  end

  public

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

  # DELETE /account/email_templates/:id/assets/:asset_id
  #
  # Removes a single ActiveStorage attachment from this template. Scoped to
  # @email_template.assets.attachments so a hand-crafted asset_id can't
  # purge a blob attached to a different record. `purge_later` enqueues the
  # R2 delete on the Active Storage purge queue so the redirect is snappy
  # even when the storage backend is slow.
  def destroy_asset
    attachment = @email_template.assets.attachments.find_by(id: params[:asset_id])
    if attachment
      attachment.purge_later
      redirect_to [:edit, :account, @email_template], notice: "Asset removed."
    else
      redirect_to [:edit, :account, @email_template], alert: "Asset not found."
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
