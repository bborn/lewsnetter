# SesSender wraps AWS SES v2's SendEmail API. The job owns batching and stats;
# SesSender owns the per-recipient render + SES call.
#
# For MVP each subscriber gets their own rendered html/text/subject — we pay
# one SES API call per recipient instead of batching with template_data. This
# keeps the surface area tiny and the rendering correct (variable substitution
# happens per subscriber in CampaignRenderer). We can switch to SES
# SendBulkEmail with replacement_template_data later for cost.
#
# In stub mode (no AWS credentials), we log a preview of the rendered HTML and
# return synthetic message ids so the rest of the pipeline (job, stats, status
# transitions) can run end-to-end in development.
class SesSender
  Result = Struct.new(:message_ids, :failed, keyword_init: true)

  class << self
    # campaign: Campaign with a sender_address + body
    # subscribers: enumerable of Subscriber records
    def send_bulk(campaign:, subscribers:)
      subscribers = Array(subscribers)
      return Result.new(message_ids: [], failed: []) if subscribers.empty?

      client = Rails.application.config.ses_client
      stub_mode = client == :stub || client.nil?

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

    def build_from_address(campaign)
      if campaign.sender_address&.name.present?
        %("#{campaign.sender_address.name}" <#{campaign.sender_address.email}>)
      else
        campaign.sender_address&.email
      end
    end
  end
end
