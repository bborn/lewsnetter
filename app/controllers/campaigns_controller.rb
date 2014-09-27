class CampaignsController < ApplicationController
  load_and_authorize_resource
  skip_load_and_authorize_resource :only => [:webview]
  skip_before_action :authenticate_user!, :only => [:webview]
  skip_authorization_check :only => [:webview]

  skip_load_resource :only => [:create, :webview]


  # GET /campaigns
  def index
    @campaigns = Campaign.all
  end

  # GET /campaigns/1
  def show
    respond_to do |format|
      format.html
      format.json {
        opened = @campaign.deliveries.where(opened: true)
        bounced = @campaign.deliveries.where("bounced_at IS NOT NULL")
        render json: [
            {name: "Opened", data: opened.group_by_hour(:opened_at).count}
          ]

      }
    end
  end

  def webview
    @delivery = Delivery.where(key: params[:id]).first
    @campaign = Campaign.find(@delivery.mail_campaign)
    render text: @campaign.body_html, layout: false
  end

  # GET /campaigns/new
  def new
    @campaign = Campaign.new
  end

  # GET /campaigns/1/edit
  def edit
  end

  def get_feed
    if url = params[:url]
      @campaign.mailing_list.update_attribute(:feed, url)
      @feed = Feedjira::Feed.fetch_and_parse(url)
    end
    render layout: false
  end

  def edit_content_iframe
    @template_content = @campaign.template.html
    render layout: 'edit_email_content'
  end

  def edit_content
  end

  def update_content
    @campaign.update(campaign_params)

    redirect_to edit_content_campaign_path(@campaign), notice: 'Saved'
  end

  def send_preview
    @campaign.preview_recipients = params[:campaign][:preview_recipients]

    unless @campaign.preview_recipients.blank?
      @campaign.send_preview
      flash[:notice] = 'Preview sent'
    else
      flash[:notice] = 'No recipients provided'
    end

    redirect_to @campaign
  end



  # POST /campaigns
  def create
    @campaign = Campaign.new(campaign_params)

    if @campaign.save
      redirect_to @campaign, notice: 'Campaign was successfully created.'
    else
      render :new
    end
  end

  # PATCH/PUT /campaigns/1
  def update
    if @campaign.update(campaign_params)
      redirect_to @campaign, notice: 'Campaign was successfully updated.'
    else
      render :edit
    end
  end

  # DELETE /campaigns/1
  def destroy
    @campaign.destroy
    redirect_to campaigns_url, notice: 'Campaign was successfully destroyed.'
  end

  def queue
    @campaign.queue!
    redirect_to @campaign, notice: 'Campaign is queueing.'
  end

  def send_campaign
    @campaign.send_campaign!
    redirect_to @campaign, notice: 'Campaign is sending.'
  end


  private
    # Only allow a trusted parameter "white list" through.
    def campaign_params
      params[:campaign].permit(:from, :subject, :body_html, :body_text, :mailing_list_id, :template_id, :content_json)
    end

end
