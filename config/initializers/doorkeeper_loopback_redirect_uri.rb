# frozen_string_literal: true

require "doorkeeper/oauth/helpers/uri_checker"

# RFC 8252 §7.3 lets an authorization server ignore the port when matching a
# loopback redirect URI, because such a callback can only reach the user's own
# machine. Doorkeeper implements this in URIChecker.matches? — but its
# loopback test is `IPAddr.new(uri.host).loopback?`, which raises for the
# *hostname* "localhost" (only IP literals parse) and is rescued to false. So
# the any-port exemption applies to http://127.0.0.1:<port> but NOT to
# http://localhost:<port>.
#
# MCP clients (Claude Code, Cursor) register a loopback callback shaped like
# http://localhost:<port>/callback and bind a fresh ephemeral port on each
# launch. Under exact-port matching that breaks re-authorization: the port in
# the authorize request stops matching the port captured at registration, and
# Doorkeeper rejects it with "The requested redirect uri is malformed or
# doesn't match client redirect URI."
#
# Treat the "localhost" hostname as loopback too, so the any-port exemption
# covers it. This only *widens* matching for loopback callbacks — which are
# safe to allow on any port, since no remote attacker can receive them — and
# leaves all non-loopback redirect-URI matching unchanged.
module Doorkeeper
  module OAuth
    module Helpers
      module URIChecker
        def self.loopback_uri?(uri)
          return true if uri.host == "localhost"

          IPAddr.new(uri.host).loopback?
        rescue IPAddr::Error
          # IPAddr::InvalidAddressError (raised for non-IP-literal hosts) is a
          # subclass of IPAddr::Error, so this catches it too.
          false
        end
      end
    end
  end
end
