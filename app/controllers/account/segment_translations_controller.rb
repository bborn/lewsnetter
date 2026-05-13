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
      format.json { render json: result_as_json(@result) }
    end
  end

  private

  # Shape the translator's Result struct into a plain JSON payload that the
  # `segment_translator_controller.js` Stimulus controller can render inline.
  def result_as_json(result)
    {
      sql_predicate: result.sql_predicate,
      human_description: result.human_description,
      estimated_count: result.estimated_count,
      sample_subscribers: Array(result.sample_subscribers).map { |s|
        {id: s.id, email: s.email, name: s.name}
      },
      errors: Array(result.errors),
      stub: result.stub?
    }
  end
end
