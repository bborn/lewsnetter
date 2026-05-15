# frozen_string_literal: true

module Mcp
  # Rack middleware that validates `Authorization: Bearer <token>` against
  # Doorkeeper::AccessToken (Lewsnetter's Platform::AccessToken). On success
  # it places the resolved user + their current team in the Rack env so the
  # MCP server can build an Mcp::Tool::Context. On failure it returns a
  # JSON-RPC 401 with code -32001 (server-defined "invalid token") plus a
  # WWW-Authenticate header per RFC 9728 pointing at the protected-resource
  # metadata document, so OAuth-aware MCP clients (Claude Desktop, etc.)
  # can discover the auth flow automatically.
  class DoorkeeperAuth
    JSONRPC_INVALID_TOKEN = -32001

    def initialize(app)
      @app = app
    end

    def call(env)
      header = env["HTTP_AUTHORIZATION"]
      return error(env, 401, "Missing Bearer token") if header.blank?

      match = header.match(/\ABearer\s+(.+)\z/)
      return error(env, 401, "Invalid Authorization header") unless match

      token = Doorkeeper::AccessToken.by_token(match[1])
      return error(env, 401, "Invalid token") unless token&.acceptable?(nil)

      user = User.find_by(id: token.resource_owner_id)
      return error(env, 401, "Token resource owner not found") if user.nil?

      team = user.current_team
      return error(env, 401, "Token resource owner has no current team") if team.nil?

      env["mcp.user"] = user
      env["mcp.team"] = team
      @app.call(env)
    end

    private

    def error(env, status, message)
      body = {
        jsonrpc: "2.0",
        error: {code: JSONRPC_INVALID_TOKEN, message: message},
        id: nil
      }.to_json
      headers = {
        "content-type" => "application/json",
        "www-authenticate" => %(Bearer resource_metadata="#{resource_metadata_url(env)}")
      }
      [status, headers, [body]]
    end

    def resource_metadata_url(env)
      scheme = env["HTTP_X_FORWARDED_PROTO"] || env["rack.url_scheme"] || "https"
      host = env["HTTP_HOST"] || "localhost"
      "#{scheme}://#{host}/.well-known/oauth-protected-resource"
    end
  end
end
