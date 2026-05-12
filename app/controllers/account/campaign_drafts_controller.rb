class Account::CampaignDraftsController < Account::ApplicationController
  account_load_and_authorize_resource :campaign, through: :team, through_association: :campaigns

  # POST /account/campaigns/:id/draft
  #
  # Runs AI::CampaignDrafter against the brief + (optional) segment and renders
  # a "draft" frame containing subject candidates + body, which the campaign
  # form merges into the current form fields.
  def create
    brief = params[:brief].to_s
    segment = @campaign.segment || @campaign.team.segments.find_by(id: params[:segment_id])
    tone = params[:tone].to_s.presence

    @draft = AI::CampaignDrafter.new(
      team: @campaign.team,
      brief: brief,
      segment: segment,
      tone: tone
    ).call

    respond_to do |format|
      format.html { render partial: "account/campaigns/draft", locals: {draft: @draft, campaign: @campaign} }
      format.turbo_stream { render partial: "account/campaigns/draft", locals: {draft: @draft, campaign: @campaign} }
    end
  end
end
