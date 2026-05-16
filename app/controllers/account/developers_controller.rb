# Developer setup hub. Two responsibilities:
#
# 1. Show the team's existing Lewsnetter sync apps + tokens so the user
#    can revoke or copy them.
# 2. Provide a one-click path to provision a new Platform::Application +
#    Doorkeeper::AccessToken for the lewsnetter-rails gem, with the
#    resulting credentials rendered as a paste-ready initializer snippet.
#
# The raw BulletTrain Platform UI is still available at
# /account/teams/:slug/platform/applications for users who need to manage
# OAuth apps directly. This page is the curated on-ramp for the common
# case: "I want my source app to push subscribers into Lewsnetter."
class Account::DevelopersController < Account::ApplicationController
  load_and_authorize_resource :team, class: "Team", parent: false, id_param: :team_id

  # GET /account/teams/:team_id/developers
  def show
    @applications = team_applications
    @access_tokens = Doorkeeper::AccessToken
      .where(application_id: @applications.pluck(:id), revoked_at: nil)
      .order(created_at: :desc)
    # Surface the just-created token once (and only once) via flash so the
    # user can copy it. After this load it's masked forever.
    @new_token_plaintext = flash[:new_token_plaintext]
  end

  # POST /account/teams/:team_id/developers/create_sync_app
  # One-click: create a Platform::Application named for this team's sync,
  # then mint an access token under the current user. Redirects back to
  # show with the plaintext token in flash so it can be displayed once.
  def create_sync_app
    authorize! :create, Platform::Application.new(team: @team)

    application = nil
    token = nil
    ActiveRecord::Base.transaction do
      application = Platform::Application.create!(
        team: @team,
        name: params[:label].presence || default_app_name,
        # Server-to-server tokens — no redirect-flow needed. Doorkeeper
        # requires a redirect_uri be present but accepts urn:ietf for the
        # "no browser" case.
        redirect_uri: "urn:ietf:wg:oauth:2.0:oob",
        scopes: "read write delete",
        confidential: true
      )
      token = Doorkeeper::AccessToken.create!(
        application: application,
        resource_owner_id: current_user.id,
        scopes: "read write delete"
      )
    end

    redirect_to account_team_developers_path(@team),
      notice: "Sync token created. Copy it now — we won't show it again.",
      flash: {new_token_plaintext: token.token}
  end

  # DELETE /account/teams/:team_id/developers/tokens/:id
  def revoke_token
    token = Doorkeeper::AccessToken.find(params[:id])
    authorize! :destroy, token.application
    token.revoke
    redirect_to account_team_developers_path(@team), notice: "Token revoked."
  end

  private

  def team_applications
    Platform::Application.where(team_id: @team.id).order(created_at: :desc)
  end

  def default_app_name
    "Lewsnetter sync · #{Time.current.strftime("%Y-%m-%d %H:%M")}"
  end
end
