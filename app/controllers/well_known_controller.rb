# frozen_string_literal: true

# Serves OAuth 2.1 / RFC 9728 metadata at the standardized /.well-known
# locations. Clients (Claude Desktop, Cursor, etc.) discover the OAuth
# endpoints from the resource-metadata document, then authorize against
# the authorization-server document.
#
# This controller is mounted before the Devise/BulletTrain auth chain so
# the documents are publicly readable (no token required).
class WellKnownController < ActionController::Base
  # GET /.well-known/oauth-protected-resource
  # RFC 9728 — describes the protected resource (i.e. /mcp/messages).
  def oauth_protected_resource
    render json: {
      resource: app_origin,
      authorization_servers: [app_origin],
      bearer_methods_supported: ["header"],
      scopes_supported: ["mcp:read", "mcp:write"]
    }
  end

  # GET /.well-known/oauth-authorization-server
  # RFC 8414 — advertises the OAuth endpoints + supported flows.
  def oauth_authorization_server
    render json: {
      issuer: app_origin,
      authorization_endpoint: "#{app_origin}/oauth/authorize",
      token_endpoint: "#{app_origin}/oauth/token",
      registration_endpoint: "#{app_origin}/oauth/register",
      response_types_supported: ["code"],
      grant_types_supported: ["authorization_code", "refresh_token"],
      code_challenge_methods_supported: ["S256"],
      scopes_supported: ["mcp:read", "mcp:write"],
      token_endpoint_auth_methods_supported: ["client_secret_post", "none"]
    }
  end

  private

  def app_origin
    @app_origin ||= "#{request.protocol}#{request.host_with_port}"
  end
end
