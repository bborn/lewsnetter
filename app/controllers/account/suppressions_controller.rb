# Per-team blocklist UI. The bulk of the suppression list is auto-populated
# by the SNS webhook (Webhooks::Ses::SnsController) — operators come here
# to audit it, paste a few manual adds (vendors who said "stop emailing me
# directly"), or undo a mistaken entry. Intentionally minimal: index +
# create + destroy. No edit (the row is meaningful as-recorded; if a reason
# is wrong, remove + re-add).
class Account::SuppressionsController < Account::ApplicationController
  before_action :load_team_and_suppression
  before_action :authorize_team_access

  # GET /account/teams/:team_id/suppressions
  def index
    scope = @team.suppressions.order(suppressed_at: :desc)
    @pagy, @suppressions = pagy(scope, page_param: :suppressions_page)
    @suppression = Suppression.new(team: @team, reason: "manual")
  end

  # POST /account/teams/:team_id/suppressions
  def create
    # Manual adds always carry the operator's user id in `source` so the
    # postmortem on the index row can answer "who added this?"
    @suppression = Suppression.new(
      team: @team,
      email: suppression_params[:email],
      reason: suppression_params[:reason].presence || "manual",
      source: "user:#{current_user.id}",
      note: suppression_params[:note],
      suppressed_at: Time.current
    )

    if @suppression.save
      redirect_to account_team_suppressions_path(@team),
        notice: "#{@suppression.email} added to the suppression list."
    else
      scope = @team.suppressions.order(suppressed_at: :desc)
      @pagy, @suppressions = pagy(scope, page_param: :suppressions_page)
      render :index, status: :unprocessable_entity
    end
  end

  # DELETE /account/suppressions/:id  (shallow)
  def destroy
    email = @suppression.email
    @suppression.destroy
    redirect_to account_team_suppressions_path(@team),
      notice: "#{email} removed from the suppression list."
  end

  private

  # Shallow routes mean destroy gets :id only, while index/create get :team_id.
  # Loading both up front keeps the action methods clean — and scoping the
  # destroy lookup to the team the user can access blocks cross-tenant URL
  # tampering (a user can't destroy team B's suppression even if they know
  # the id).
  def load_team_and_suppression
    if params[:id].present?
      @suppression = Suppression.find(params[:id])
      @team = @suppression.team
    else
      @team = current_user.teams.find(params[:team_id])
    end
  end

  # The Suppression model isn't in roles.yml — admins can do everything on
  # their teams; non-admins shouldn't see the page at all. We piggy-back on
  # the Team#manage ability admins get via roles.yml; if you can manage the
  # team, you can manage its suppression list. Will raise CanCan::AccessDenied
  # for a different team's resource (the user has no Team#manage there).
  def authorize_team_access
    authorize! :manage, @team
  end

  def suppression_params
    params.require(:suppression).permit(:email, :reason, :note)
  end
end
