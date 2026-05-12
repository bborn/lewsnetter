class ApplicationMailer < ActionMailer::Base
  include Mailers::Base

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

    host = Rails.application.config.action_mailer.default_url_options&.dig(:host)
    return if host.blank?

    token = subscriber.to_signed_global_id(for: "unsubscribe").to_s
    one_click_url = Rails.application.routes.url_helpers.unsubscribe_url(token: token, host: host)

    headers["List-Unsubscribe"] = "<#{one_click_url}>, <mailto:unsubscribe@#{host}>"
    headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"
  end
end
