# frozen_string_literal: true

require "test_helper"

# Locks in the config/initializers/doorkeeper_loopback_redirect_uri.rb patch:
# loopback redirect URIs (including the "localhost" hostname) match on any port
# per RFC 8252 §7.3, while every other redirect-URI match stays exact.
class DoorkeeperLoopbackRedirectUriTest < ActiveSupport::TestCase
  URIChecker = Doorkeeper::OAuth::Helpers::URIChecker

  test "localhost is recognized as a loopback host" do
    assert URIChecker.loopback_uri?(URI.parse("http://localhost:1234/callback"))
  end

  test "localhost redirect matches regardless of port (the MCP re-auth case)" do
    assert URIChecker.matches?(
      "http://localhost:51888/callback",
      "http://localhost:49222/callback"
    )
  end

  test "127.0.0.1 loopback still matches regardless of port" do
    assert URIChecker.matches?(
      "http://127.0.0.1:51888/callback",
      "http://127.0.0.1:49222/callback"
    )
  end

  test "non-loopback hosts still require an exact port match" do
    refute URIChecker.matches?(
      "https://app.example.com:8443/callback",
      "https://app.example.com:443/callback"
    )
  end

  test "loopback matching does not relax the path" do
    refute URIChecker.matches?(
      "http://localhost:5000/evil",
      "http://localhost:5000/callback"
    )
  end
end
