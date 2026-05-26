class Account::CampaignPostmortemsController < Account::ApplicationController
  # GET /account/campaigns/:id/postmortem
  #
  # Like CampaignDraftsController, this is a member action on the campaigns
  # resource that lives in a sibling controller — `account_load_and_authorize_resource`
  # doesn't pick up `params[:id]` as the campaign id from a sibling controller
  # and leaves `@campaign` nil, so we resolve + authorize manually.
  #
  # Runs AI::PostSendAnalyst against the campaign's stats + body, returning
  # the rendered markdown inside a turbo-frame so the show view can lazy-load it.
  def show
    @campaign = Campaign.find(params[:id])
    authorize! :read, @campaign

    @markdown = AI::PostSendAnalyst.new(campaign: @campaign).call

    respond_to do |format|
      format.html { render partial: "account/campaigns/postmortem", locals: {campaign: @campaign, markdown: @markdown} }
    end
  end
end
