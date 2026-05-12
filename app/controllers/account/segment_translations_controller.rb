class Account::SegmentTranslationsController < Account::ApplicationController
  # POST /account/teams/:team_id/segments/translate
  #
  # Runs AI::SegmentTranslator against the team's subscriber schema and renders
  # a preview frame (predicate + a handful of matching subscribers).
  #
  # Singleton-style action with no persisted record yet — `account_load_and_
  # authorize_resource` doesn't apply cleanly here, so we resolve the team
  # manually + authorize against Segment.new(team:) using the standard ability
  # rules.
  def create
    @team = current_user.teams.find(params[:team_id])
    authorize! :create, @team.segments.new

    @natural_language = params[:natural_language].to_s
    @result = AI::SegmentTranslator.new(
      team: @team,
      natural_language: @natural_language
    ).call

    respond_to do |format|
      format.html { render partial: "account/segments/preview", locals: {result: @result, natural_language: @natural_language} }
      format.turbo_stream { render partial: "account/segments/preview", formats: [:html], locals: {result: @result, natural_language: @natural_language} }
    end
  end
end
