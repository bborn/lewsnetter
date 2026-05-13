# Compute the canonical unsubscribe URL for a subscriber.
#
# This is intentionally a PORO module — NOT an ActionView helper — so it can
# be called from both ApplicationMailer (instance method context) AND
# CampaignRenderer (service object context) without dragging in route helper
# baggage. The hostname is per-team (Team::SesConfiguration#unsubscribe_host)
# with a fallback to the app-wide default.
#
# Token format mirrors what UnsubscribeController#find_subscriber expects:
# a Rails signed GlobalID with purpose "unsubscribe", scoped to 30 days.
module UnsubscribeUrlHelper
  # @param subscriber [Subscriber] the recipient
  # @param default_host [String, nil] fallback hostname; if nil we read
  #   Rails.application.config.action_mailer.default_url_options[:host]
  # @return [String] e.g. "https://email.influencekit.com/unsubscribe/<sgid>"
  def self.url_for(subscriber:, default_host: nil)
    team_host = subscriber.team.ses_configuration&.unsubscribe_host
    host = team_host.presence ||
      default_host.presence ||
      Rails.application.config.action_mailer.default_url_options[:host]

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
