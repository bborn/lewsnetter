# SesSender wraps AWS SES v2's SendEmail API. The job owns batching and stats;
# SesSender owns the per-recipient render + SES call.
#
# Per-tenant SES: the client comes from `Ses::ClientFor.call(campaign.team)`
# which reads that team's `Team::SesConfiguration`. Each tenant brings their
# own AWS credentials, so reputation is per-tenant and we don't need a global
# AWS account configured for MVP.
#
# Stub mode: when a team has no SES configured (dev/test or a brand-new
# tenant) we log a preview and return synthetic message ids so the rest of
# the pipeline (job, stats, status transitions) runs end-to-end. The
# `Rails.application.config.ses_client = :stub` override is also honored for
# tests that want to force stub behavior even when a config exists.
class SesSender
  Result = Struct.new(:message_ids, :failed, keyword_init: true)

  class << self
    # campaign: Campaign with a sender_address + body
    # subscribers: enumerable of Subscriber records
    def send_bulk(campaign:, subscribers:)
      subscribers = Array(subscribers)
      return Result.new(message_ids: [], failed: []) if subscribers.empty?

      team = campaign.team
      client, stub_mode = resolve_client(team)
      from_address = build_from_address(campaign)

      message_ids = []
      failed = []

      subscribers.each do |subscriber|
        rendered =
          begin
            CampaignRenderer.new(campaign: campaign, subscriber: subscriber).call
          rescue => e
            Rails.logger.warn(
              "[SesSender] render failed for subscriber=#{subscriber.id} " \
              "campaign=#{campaign.id}: #{e.class}: #{e.message}"
            )
            failed << {subscriber: subscriber, error: "render_failed: #{e.message}"}
            next
          end

        if stub_mode
          Rails.logger.info(
            %([SES STUB] to=#{subscriber.email} subject=#{rendered.subject.inspect} ) +
              %(html_preview=#{rendered.html.to_s[0, 200].inspect})
          )
          message_ids << "stub-#{SecureRandom.hex(8)}"
          next
        end

        begin
          response = client.send_email(
            from_email_address: from_address,
            destination: {to_addresses: [subscriber.email]},
            content: {
              simple: {
                subject: {data: rendered.subject},
                body: {
                  html: {data: rendered.html},
                  text: {data: rendered.text}
                }
              }
            }
          )
          message_ids << response.message_id
        rescue => e
          Rails.logger.warn(
            "[SesSender] SES send failed for subscriber=#{subscriber.id} " \
            "campaign=#{campaign.id}: #{e.class}: #{e.message}"
          )
          failed << {subscriber: subscriber, error: e.message}
        end
      end

      Result.new(message_ids: message_ids, failed: failed)
    end

    private

    # Returns [client_or_nil, stub_mode_bool]. We're in stub mode when either:
    #   1. The global override `Rails.application.config.ses_client = :stub`
    #      is set — preserved so existing tests can force stub mode.
    #   2. The team has no SES configuration (NotConfigured) — every brand-new
    #      team starts here until they paste credentials.
    def resolve_client(team)
      global = Rails.application.config.respond_to?(:ses_client) ? Rails.application.config.ses_client : nil
      return [nil, true] if global == :stub

      begin
        [Ses::ClientFor.call(team), false]
      rescue Ses::ClientFor::NotConfigured
        Rails.logger.info(
          "[SesSender] team #{team.id} has no SES config — running in stub mode."
        )
        [nil, true]
      end
    end

    def build_from_address(campaign)
      if campaign.sender_address&.name.present?
        %("#{campaign.sender_address.name}" <#{campaign.sender_address.email}>)
      else
        campaign.sender_address&.email
      end
    end
  end
end
