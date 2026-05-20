# Compute the canonical unsubscribe URL for a subscriber.
#
# This is intentionally a PORO module — NOT an ActionView helper — so it can
# be called from both ApplicationMailer (instance method context) AND
# CampaignRenderer (service object context) without dragging in route helper
# baggage. The hostname is per-team (Team::SesConfiguration#unsubscribe_host)
# with a fallback to the app-wide default.
#
# `host_for` is the SINGLE host-resolver for everything that puts an absolute
# link in an outbound campaign email — the unsubscribe link, the open-tracking
# pixel, and the click-tracking redirect. Keeping it here (rather than three
# copies across UnsubscribeUrlHelper / CampaignRenderer / ApplicationMailer)
# means a team's branded email subdomain is decided in exactly one place.
#
# Token format mirrors what UnsubscribeController#find_subscriber expects:
# a Rails signed GlobalID with purpose "unsubscribe", scoped to 30 days.
module UnsubscribeUrlHelper
  # Resolves the hostname all of this team's outbound email links should use.
  #
  # If the team has configured a branded unsubscribe subdomain (a CNAME to the
  # Lewsnetter app, e.g. "email.influencekit.com"), every email link — unsub,
  # open pixel, click redirect — uses it so the whole message shares one host
  # aligned with the From: domain. Otherwise we fall back to the app-wide
  # default (BASE_URL → action_mailer.default_url_options[:host]).
  #
  # @param team [Team] the sending team
  # @param default_host [String, nil] fallback hostname; if nil we read
  #   Rails.application.config.action_mailer.default_url_options[:host]
  # @return [String] a bare hostname (no scheme), e.g. "email.influencekit.com"
  def self.host_for(team:, default_host: nil)
    team_host = team&.ses_configuration&.unsubscribe_host
    team_host.presence ||
      default_host.presence ||
      Rails.application.config.action_mailer.default_url_options&.dig(:host)
  end

  # @param subscriber [Subscriber] the recipient
  # @param default_host [String, nil] fallback hostname; if nil we read
  #   Rails.application.config.action_mailer.default_url_options[:host]
  # @return [String] e.g. "https://email.influencekit.com/unsubscribe/<sgid>"
  def self.url_for(subscriber:, default_host: nil)
    host = host_for(team: subscriber.team, default_host: default_host)

    # Test-send + preview paths render with an in-memory Subscriber.new (no
    # id), but SGID requires a persisted model. Return a visibly-fake URL the
    # author recognizes as "this is a preview, not a live unsubscribe link".
    unless subscriber.persisted?
      return "https://#{host}/unsubscribe/preview-only"
    end

    token = subscriber.to_sgid(for: "unsubscribe", expires_in: 30.days).to_s
    "https://#{host}/unsubscribe/#{token}"
  end
end
