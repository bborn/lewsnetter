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

  # The consent page says mcp:read only reads (doorkeeper.en.yml), so a token
  # granted mcp:read without mcp:write or admin may only GET. Tokens without
  # mcp:* scopes (sync, platform agent, admin) keep full access.
  WRITE_SCOPES = %w[mcp:write admin].freeze
  before_action :enforce_read_only_token_scopes

  private

  def enforce_read_only_token_scopes
    return unless doorkeeper_token
    return if request.get? || request.head?

    scopes = doorkeeper_token.scopes
    return unless scopes.exists?("mcp:read") && WRITE_SCOPES.none? { scopes.exists?(it) }

    render json: {error: "This access token is read-only (mcp:read). Writing needs mcp:write."}, status: :forbidden
  end

  def enforce_token_team_matches_url_team
    # No-op for unauthenticated endpoints (currently none under api/v1) and
    # for routes that don't carry a :team_id in the URL.
    return unless doorkeeper_token
    return if params[:team_id].blank?

    token_team = doorkeeper_token.application&.team
    if token_team.nil?
      # Tokens from /oauth/register have no team binding — refuse rather than
      # silently let them target any team the user happens to belong to.
      render json: {error: "Access token is not bound to a team. Provision a sync token at /account/teams/:id/developers."}, status: :forbidden
      return
    end

    # URLs use BulletTrain's obfuscated_id (a short alphanumeric string),
    # NOT the raw integer PK. Team.find handles both — it tries the
    # obfuscates_id deobfuscation first, then falls back to integer lookup.
    url_team =
      begin
        Team.find(params[:team_id])
      rescue ActiveRecord::RecordNotFound
        nil
      end

    if url_team.nil?
      render json: {error: "Team '#{params[:team_id]}' not found."}, status: :not_found
      return
    end

    return if token_team.id == url_team.id

    render json: {
      error: "Access token is bound to team '#{token_team.name}' but the URL targets team '#{url_team.name}'. " \
             "Check LEWSNETTER_TEAM_SLUG matches the team your sync token was provisioned under.",
      token_team_id: token_team.to_param,
      url_team_id: url_team.to_param
    }, status: :forbidden
  end
end
