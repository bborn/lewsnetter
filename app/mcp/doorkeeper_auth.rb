# frozen_string_literal: true

module Mcp
  # Rack middleware that validates `Authorization: Bearer <token>` against
  # Doorkeeper::AccessToken (Lewsnetter's Platform::AccessToken). On success
  # it places the resolved user + their current team in the Rack env so the
  # MCP server can build an Mcp::Tool::Context. On failure it returns a
  # JSON-RPC 401 with code -32001 (server-defined "invalid token").
  class DoorkeeperAuth
    JSONRPC_INVALID_TOKEN = -32001

    def initialize(app)
      @app = app
    end

    def call(env)
      header = env["HTTP_AUTHORIZATION"]
      return error(401, "Missing Bearer token") if header.blank?

      match = header.match(/\ABearer\s+(.+)\z/)
      return error(401, "Invalid Authorization header") unless match

      token = Doorkeeper::AccessToken.by_token(match[1])
      return error(401, "Invalid token") unless token&.acceptable?(nil)

      user = User.find_by(id: token.resource_owner_id)
      return error(401, "Token resource owner not found") if user.nil?

      team = user.current_team
      return error(401, "Token resource owner has no current team") if team.nil?

      env["mcp.user"] = user
      env["mcp.team"] = team
      @app.call(env)
    end

    private

    def error(status, message)
      body = {
        jsonrpc: "2.0",
        error: {code: JSONRPC_INVALID_TOKEN, message: message},
        id: nil
      }.to_json
      [status, {"content-type" => "application/json"}, [body]]
    end
  end
end
