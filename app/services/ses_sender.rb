# SesSender wraps AWS SES v2's SendBulkEmail API. It is intentionally tiny —
# the job is responsible for batching (50 at a time), the campaign owns
# content + sender, and SesSender just translates that into the SES payload.
#
# In stub mode (no AWS credentials), we log and return synthetic message ids
# so the rest of the pipeline (job, stats, status transitions) can run
# end-to-end in development.
class SesSender
  Result = Struct.new(:message_ids, :failed, keyword_init: true)

  class << self
    # campaign: Campaign with a sender_address + body
    # subscribers: enumerable of Subscriber records
    def send_bulk(campaign:, subscribers:)
      subscribers = Array(subscribers)
      return Result.new(message_ids: [], failed: []) if subscribers.empty?

      client = Rails.application.config.ses_client

      if client == :stub || client.nil?
        Rails.logger.info(%([SES STUB] would send "#{campaign.subject}" to #{subscribers.size} recipients))
        return Result.new(
          message_ids: subscribers.map { |s| "stub-#{SecureRandom.hex(8)}" },
          failed: []
        )
      end

      body_html = campaign.body_html.presence || campaign.body_mjml
      from_address = if campaign.sender_address&.name.present?
        %("#{campaign.sender_address.name}" <#{campaign.sender_address.email}>)
      else
        campaign.sender_address&.email
      end

      response = client.send_bulk_email(
        from_email_address: from_address,
        default_content: {
          template: {
            template_content: {
              subject: campaign.subject,
              html: body_html,
              text: campaign.preheader.to_s
            },
            template_data: "{}"
          }
        },
        bulk_email_entries: subscribers.map { |s|
          {
            destination: {to_addresses: [s.email]},
            replacement_email_content: {
              replacement_template: {template_data: "{}"}
            }
          }
        }
      )

      message_ids = []
      failed = []
      response.bulk_email_entry_results.each_with_index do |result, i|
        if result.status.to_s == "SUCCESS"
          message_ids << result.message_id
        else
          failed << {subscriber: subscribers[i], error: result.error}
        end
      end

      Result.new(message_ids: message_ids, failed: failed)
    end
  end
end
