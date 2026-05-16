# frozen_string_literal: true

module Ses
  # Sends a hardcoded "you're wired up" test email through the team's own
  # SES configuration. Used as the final step of the SES setup wizard so
  # the user closes the loop with a real, verified send before building a
  # campaign.
  #
  # Returns a Result with ok:, message_id:, and an error_message: on
  # failure. Never raises — the wizard surfaces failures inline.
  class TestSender
    Result = Struct.new(:ok, :message_id, :error_message, keyword_init: true) do
      def ok? = ok
    end

    def initialize(team:, sender_address:, to_email:)
      @team = team
      @sender_address = sender_address
      @to_email = to_email
    end

    def call
      client = Ses::ClientFor.call(@team)
      from = build_from_address
      response = client.send_email(
        from_email_address: from,
        destination: {to_addresses: [@to_email]},
        content: {
          simple: {
            subject: {data: "Lewsnetter is wired up"},
            body:    {html: {data: html_body}, text: {data: text_body}}
          }
        }
      )
      @team.ses_configuration&.update_column(:last_test_sent_at, Time.current)
      Result.new(ok: true, message_id: response.message_id)
    rescue Ses::ClientFor::NotConfigured => e
      Result.new(ok: false, error_message: "SES credentials aren't configured yet (#{e.message}).")
    rescue Aws::Errors::ServiceError, Aws::SESV2::Errors::ServiceError => e
      Result.new(ok: false, error_message: "Amazon SES rejected the test send: #{e.message}")
    end

    private

    def build_from_address
      if @sender_address.name.present?
        %("#{@sender_address.name}" <#{@sender_address.email}>)
      else
        @sender_address.email
      end
    end

    def html_body
      <<~HTML
        <!doctype html>
        <html><body style="font-family: -apple-system, system-ui, sans-serif; max-width: 480px; margin: 40px auto; color: #18181b;">
          <h1 style="font-size: 22px; font-weight: 600; letter-spacing: -0.01em;">Lewsnetter is wired up.</h1>
          <p style="font-size: 15px; line-height: 1.5; color: #52525b;">
            This message came through your own SES account from
            <code style="background: #f4f4f5; padding: 1px 6px; border-radius: 4px;">#{@sender_address.email}</code>.
            Bounce + complaint tracking, per-recipient sends, and the unsubscribe footer all work the same way for real campaigns.
          </p>
          <p style="font-size: 13px; line-height: 1.5; color: #71717a; margin-top: 24px;">
            You can compose your first campaign whenever you're ready.
          </p>
        </body></html>
      HTML
    end

    def text_body
      <<~TEXT
        Lewsnetter is wired up.

        This message came through your own SES account from #{@sender_address.email}.
        Bounce + complaint tracking, per-recipient sends, and the unsubscribe footer
        all work the same way for real campaigns.

        You can compose your first campaign whenever you're ready.
      TEXT
    end
  end
end
