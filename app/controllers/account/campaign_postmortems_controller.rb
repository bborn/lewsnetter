class Account::CampaignPostmortemsController < Account::ApplicationController
  account_load_and_authorize_resource :campaign, through: :team, through_association: :campaigns

  # GET /account/campaigns/:id/postmortem
  #
  # Runs AI::PostSendAnalyst against the campaign's stats + body, returning
  # the rendered markdown inside a turbo-frame so the show view can lazy-load it.
  def show
    @markdown = AI::PostSendAnalyst.new(campaign: @campaign).call

    respond_to do |format|
      format.html { render partial: "account/campaigns/postmortem", locals: {campaign: @campaign, markdown: @markdown} }
    end
  end
end
