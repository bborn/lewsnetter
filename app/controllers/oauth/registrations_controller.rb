# frozen_string_literal: true

module Oauth
  # RFC 7591 — OAuth Dynamic Client Registration.
  #
  # Lets MCP clients (Claude Desktop, Cursor, Codex) register themselves
  # without manual setup. They POST a JSON body with `redirect_uris` and
  # we return a `client_id` (+ `client_secret` if confidential).
  #
  # Mounted at POST /oauth/register, public, no CSRF (it's an API for
  # browser-less clients).
  class RegistrationsController < ActionController::Base
    skip_before_action :verify_authenticity_token

    def create
      params_hash = JSON.parse(request.body.read)

      redirect_uris = Array(params_hash["redirect_uris"]).join("\n")
      if redirect_uris.blank?
        render json: {error: "redirect_uris is required"}, status: :bad_request
        return
      end

      client_name = params_hash["client_name"].presence || "MCP client"
      confidential = params_hash["token_endpoint_auth_method"] != "none"

      # Platform::Application is BulletTrain's Doorkeeper::Application class.
      # `team:` and `user:` are optional — for dynamic clients they're nil
      # until a user authorizes; the resulting access token's
      # resource_owner_id is what binds the token to a user.
      application = Platform::Application.create!(
        name: client_name,
        redirect_uri: redirect_uris,
        scopes: "mcp:read mcp:write",
        confidential: confidential
      )

      response_body = {
        client_id: application.uid,
        client_name: application.name,
        redirect_uris: application.redirect_uri.split("\n"),
        grant_types: ["authorization_code", "refresh_token"],
        response_types: ["code"],
        token_endpoint_auth_method: confidential ? "client_secret_post" : "none"
      }
      response_body[:client_secret] = application.secret if confidential

      render json: response_body, status: :created
    rescue JSON::ParserError
      render json: {error: "Invalid JSON body"}, status: :bad_request
    rescue ActiveRecord::RecordInvalid => e
      render json: {error: e.message}, status: :unprocessable_entity
    end
  end
end
