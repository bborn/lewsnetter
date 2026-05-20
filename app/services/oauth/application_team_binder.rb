# frozen_string_literal: true

module Oauth
  # Binds a Platform::Application to a team at OAuth authorize-time.
  #
  # MCP clients (Claude Desktop, claude.ai) register through RFC 7591 dynamic
  # client registration (POST /oauth/register), which creates a
  # Platform::Application with no team. Mcp::DoorkeeperAuth rejects any token
  # whose application has no team — so a purely dynamically-registered client
  # can never reach the MCP: every /mcp/messages call 401s and the connector
  # loops, re-registering a fresh teamless app each time.
  #
  # This binds the application to a team the first time a user authorizes it.
  # The team is the authorizing user's current_team, captured ONCE and frozen
  # on the application record. Per the C2 data-isolation finding, the MCP
  # boundary must key off this stable application.team, never the mutable
  # per-request user.current_team — capturing it once here is exactly that: a
  # stable binding decided at authorize-time.
  #
  # Wired into the Doorkeeper flow via before_successful_authorization
  # (config/initializers/doorkeeper.rb).
  module ApplicationTeamBinder
    module_function

    # Entry point for the Doorkeeper hook. Pulls the application + resource
    # owner out of the authorizations controller and binds.
    #
    # Never raises: a failure here must not break the OAuth grant. Worst case
    # we fall back to the pre-existing teamless-app behavior.
    def from_authorization_request(controller)
      client_id = controller.params[:client_id].presence
      return unless client_id

      bind(
        application: Platform::Application.by_uid(client_id),
        resource_owner: controller.send(:current_resource_owner)
      )
    rescue => e
      Rails.logger.error("[Oauth::ApplicationTeamBinder] #{e.class}: #{e.message}")
      nil
    end

    # Binds `application` to the resource owner's current team — but only when
    # the application has no team yet. An application's team is permanent once
    # set: re-authorization by a different user never reassigns it.
    def bind(application:, resource_owner:)
      return if application.nil?
      return if application.team_id.present?
      return unless resource_owner.respond_to?(:current_team)

      team = resource_owner.current_team
      return if team.nil?

      application.update!(team: team)
    end
  end
end
