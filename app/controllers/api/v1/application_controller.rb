class Api::V1::ApplicationController < ActionController::API
  include Api::Controllers::Base

  # H1 — enforce that a Doorkeeper access token can only act on its OWN
  # bound team, regardless of what `:team_id` segment the caller puts in the
  # URL. BulletTrain's stock `current_team` is `current_user.teams.first`,
  # which means a user-who-belongs-to-multiple-teams could POST to
  # /api/v1/teams/<any_other_team_id>/subscribers/bulk with a token issued
  # for a different team and the write would succeed. We fix that at OUR
  # seam (NOT in the bullet_train-api gem) — see
  # docs/security/2026-05-19-data-isolation-audit.md (H1).
  before_action :enforce_token_team_matches_url_team

  private

  def enforce_token_team_matches_url_team
    # No-op for unauthenticated endpoints (currently none under api/v1) and
    # for routes that don't carry a :team_id in the URL.
    return unless doorkeeper_token
    return if params[:team_id].blank?

    token_team_id = doorkeeper_token.application&.team_id
    if token_team_id.nil?
      # Tokens from /oauth/register have no team binding — refuse rather than
      # silently let them target any team the user happens to belong to.
      render json: {error: "Access token is not bound to a team. Provision a sync token at /account/teams/:id/developers."}, status: :forbidden
      return
    end

    # Teams in this app are looked up by integer primary key in URLs.
    # `Team.find(params[:team_id])`-style routes always carry a numeric id.
    return if token_team_id == params[:team_id].to_i

    render json: {error: "Access token is bound to a different team than the one in this URL."}, status: :forbidden
  end
end
