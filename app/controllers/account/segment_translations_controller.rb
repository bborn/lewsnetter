class Account::SegmentTranslationsController < Account::ApplicationController
  account_load_and_authorize_resource :team, through: :user, through_association: :teams

  # POST /account/teams/:team_id/segments/translate
  #
  # Runs AI::SegmentTranslator against the team's subscriber schema and renders
  # a preview frame (predicate + a handful of matching subscribers).
  def create
    @natural_language = params[:natural_language].to_s
    @result = AI::SegmentTranslator.new(
      team: @team,
      natural_language: @natural_language
    ).call

    respond_to do |format|
      format.html { render partial: "account/segments/preview", locals: {result: @result, natural_language: @natural_language} }
      format.turbo_stream { render partial: "account/segments/preview", locals: {result: @result, natural_language: @natural_language} }
    end
  end
end
