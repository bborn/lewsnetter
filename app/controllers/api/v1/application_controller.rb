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

  # Shallow routes (/api/v1/subscribers/:id, /api/v1/subscribers/:id/events,
  # /api/v1/teams/:id, ...) carry no :team_id for the check above, and the
  # user's CanCan ability spans every team they belong to, with each team's
  # role. So on those routes every record CanCan authorizes, including the
  # parent of a nested collection, must also belong to the token's team, and
  # unnested indexes (/api/v1/teams, /api/v1/users) only list that team.
  # URLs with a :team_id are left to enforce_token_team_matches_url_team.
  #
  # Runs after the resource is loaded (subclasses prepend their loaders
  # later, so theirs come first) and before filters and pagination.
  prepend_before_action :scope_unnested_index_to_token_team, only: :index

  def authorize!(action, subject, *args)
    if token_team_check_applies?
      records = subject.is_a?(Hash) ? subject.keys : [subject]
      records.each do |record|
        # Class-level checks (index, new) carry no record; the collection is
        # narrowed in scope_unnested_index_to_token_team.
        next if record.is_a?(Module) || record.is_a?(Symbol)
        raise CanCan::AccessDenied.new(nil, action, subject) unless token_may_reach?(record)
      end
    end

    super
  end

  private

  def token_team_check_applies?
    doorkeeper_token.present? && params[:team_id].blank?
  end

  def token_team
    doorkeeper_token.application&.team
  end

  # A token bound to no team reaches no team records. Records without a team
  # of their own are judged by the record they belong to, and refused when
  # none of them leads to a team.
  def token_may_reach?(record)
    case record
    when User
      record == current_user || (token_team.present? && token_team.memberships.exists?(user_id: record.id))
    else
      team = team_of(record)
      # A record built through a shallow parent (POST /subscribers/:id/events)
      # has no team yet. Its parent is authorized as a subject of its own.
      return true if team.nil? && record.try(:new_record?)

      token_team.present? && team == token_team
    end
  end

  def team_of(record, depth = 0)
    return record if record.is_a?(Team)
    return record.team if record.respond_to?(:team)
    return nil if depth >= 2 || !record.class.respond_to?(:reflect_on_all_associations)

    record.class.reflect_on_all_associations(:belongs_to).each do |association|
      parent = record.public_send(association.name)
      team = parent && team_of(parent, depth + 1)
      return team if team
    end
    nil
  end

  def scope_unnested_index_to_token_team
    return unless token_team_check_applies?
    return unless collection.is_a?(ActiveRecord::Relation)

    model = collection.model
    self.collection =
      if model <= Team
        collection.where(id: token_team&.id)
      elsif model <= User
        member_ids = token_team ? token_team.memberships.where.not(user_id: nil).select(:user_id) : User.none.select(:id)
        collection.where(id: current_user.id).or(collection.where(id: member_ids))
      elsif model.column_names.include?("team_id")
        collection.where(team_id: token_team&.id)
      else
        collection
      end
  end

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
