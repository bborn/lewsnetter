class ApplicationMailer < ActionMailer::Base
  include Mailers::Base

  default from: -> { I18n.t("application.support_email") }

  # RFC 8058 one-click unsubscribe support. Mailers that send to a specific
  # Subscriber should `mail(to: subscriber.email, subscriber: subscriber, ...)`
  # — we'll pull the subscriber out of the headers and rewrite the
  # List-Unsubscribe headers with a per-subscriber signed token.
  before_action :set_list_unsubscribe_headers

  private

  def set_list_unsubscribe_headers
    subscriber = headers[:subscriber] || @subscriber
    return unless subscriber.respond_to?(:to_signed_global_id)

    headers.delete(:subscriber) if headers.respond_to?(:delete)

    default_host = Rails.application.config.action_mailer.default_url_options&.dig(:host)
    return if default_host.blank?

    # Per-team unsubscribe subdomain — falls back to the app-wide default
    # if the team hasn't configured one.
    one_click_url = UnsubscribeUrlHelper.url_for(
      subscriber: subscriber,
      default_host: default_host
    )

    resolved_host = subscriber.team.ses_configuration&.unsubscribe_host.presence || default_host

    headers["List-Unsubscribe"] = "<#{one_click_url}>, <mailto:unsubscribe@#{resolved_host}>"
    headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"
  end
end
