class Account::SearchController < Account::ApplicationController
  # Global Cmd+K palette endpoint. Returns grouped results across every
  # resource the team can see — subscribers, companies, segments, campaigns,
  # email templates, sender addresses. See app/services/account/search.rb
  # for the actual query orchestration.
  #
  # We deliberately don't use `account_load_and_authorize_resource` here —
  # there's no resource for "search" and the service object handles scoping
  # via `current_team` directly. We still authorize on Team membership via
  # the standard parent-load + authorize! flow.

  # GET /account/teams/:team_id/search.json?q=foo
  def index
    @team = current_user.teams.find(params[:team_id])
    authorize! :show, @team

    results = Account::Search.new(
      team: @team,
      query: params[:q].to_s,
      url_helpers: self
    ).call

    render json: results
  end
end
