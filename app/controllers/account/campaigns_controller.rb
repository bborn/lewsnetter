class Account::CampaignsController < Account::ApplicationController
  account_load_and_authorize_resource :campaign,
    through: :team,
    through_association: :campaigns,
    member_actions: [:send_now, :test_send, :preview_frame]

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
  #
  # Gated on Campaign#sendable? so we don't allow a re-send of a campaign
  # that's already in flight, completed, or failed. The job itself sets
  # `sent_at` + `status = 'sent'` on success.
  def send_now
    if @campaign.sendable?
      SendCampaignJob.perform_later(@campaign.id)
      redirect_to [:account, @campaign], notice: "Campaign queued for sending."
    else
      redirect_to [:account, @campaign], alert: "Only draft or scheduled campaigns can be sent."
    end
  end

  # GET  /account/campaigns/:id/preview_frame
  # POST /account/campaigns/:id/preview_frame
  #
  # Returns the rendered HTML preview of the campaign, suitable for embedding
  # in an iframe on the edit form.
  #
  # GET renders the *persisted* campaign state — that's what direct iframe
  # `src` access loads on first paint and the legacy "Refresh preview" button
  # depended on. POST accepts the *in-memory* form values from the editor
  # (body_markdown, body_mjml, subject, preheader, email_template_id) and
  # renders without saving, so authors see their changes live without
  # round-tripping through update. Body is read as either JSON or
  # form-encoded, so the live editor can post JSON directly.
  #
  # The render result is bare email HTML — the iframe owns chrome via
  # `srcdoc` (POST) or its standard sandbox (GET). On any render failure we
  # serve a minimal error page so the iframe shows the user *why* rather than
  # 500ing or going blank.
  def preview_frame
    response.headers["X-Frame-Options"] = "SAMEORIGIN"
    response.headers["Content-Security-Policy"] = "frame-ancestors 'self'"

    html = if request.post?
      preview_html_for_in_memory_changes
    else
      @campaign.preview_html
    end

    if html.present?
      render html: html.html_safe, layout: false, content_type: "text/html"
    else
      render html: preview_error_html.html_safe, layout: false, content_type: "text/html"
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

  # Renders the campaign with the in-memory form values applied, without
  # persisting anything. Uses the existing preview_html pipeline so the output
  # matches what a real send would render.
  def preview_html_for_in_memory_changes
    overrides = preview_overrides_params

    # We mutate attributes in-memory and call preview_html, then roll back so
    # ActiveRecord stays clean. We deliberately do NOT `assign_attributes`
    # email_template_id without reloading the association — Rails caches the
    # belongs_to lookup until the FK changes, but to be safe we explicitly
    # nil the loaded association before reading the new template.
    original = {
      body_markdown: @campaign.body_markdown,
      body_mjml: @campaign.body_mjml,
      subject: @campaign.subject,
      preheader: @campaign.preheader,
      email_template_id: @campaign.email_template_id
    }

    begin
      @campaign.body_markdown = overrides[:body_markdown] if overrides.key?(:body_markdown)
      @campaign.body_mjml = overrides[:body_mjml] if overrides.key?(:body_mjml)
      @campaign.subject = overrides[:subject] if overrides.key?(:subject)
      @campaign.preheader = overrides[:preheader] if overrides.key?(:preheader)
      if overrides.key?(:email_template_id)
        @campaign.email_template_id = overrides[:email_template_id].presence
        @campaign.email_template = nil # bust the belongs_to cache
      end

      @campaign.preview_html
    ensure
      original.each { |k, v| @campaign.send("#{k}=", v) }
      @campaign.email_template = nil # force fresh load on next access
    end
  end

  # Reads preview overrides from JSON body (preferred by the live editor) or
  # form-encoded params. Blank values pass through so callers can clear a
  # field for the preview.
  def preview_overrides_params
    json_body = nil
    if request.content_type.to_s.start_with?("application/json")
      raw = request.raw_post
      if raw.present?
        json_body = begin
          JSON.parse(raw)
        rescue JSON::ParserError
          nil
        end
      end
    end

    src = json_body.is_a?(Hash) ? json_body : params.to_unsafe_h

    {}.tap do |h|
      %w[body_markdown body_mjml subject preheader email_template_id].each do |key|
        h[key.to_sym] = src[key].to_s if src.key?(key)
      end
    end
  end

  def preview_error_html
    <<~HTML
      <!DOCTYPE html>
      <html>
        <head>
          <meta charset="utf-8">
          <title>Preview unavailable</title>
          <style>
            body { font-family: ui-sans-serif, system-ui, sans-serif; padding: 24px; color: #92400e; background: #fffbeb; }
            h1 { font-size: 16px; margin: 0 0 8px; }
            p { font-size: 14px; margin: 0; }
          </style>
        </head>
        <body>
          <h1>Preview could not be rendered.</h1>
          <p>Check that the campaign has a body (markdown or MJML) and a valid email template. Save your changes and click Refresh preview to retry.</p>
        </body>
      </html>
    HTML
  end
end
