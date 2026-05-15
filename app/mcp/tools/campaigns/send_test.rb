# frozen_string_literal: true

module Mcp
  module Tools
    module Campaigns
      class SendTest < Mcp::Tool::Base
        include Mcp::Tools::Serializers

        tool_name "campaigns_send_test"
        description <<~DESC
          Sends a test copy of the campaign to a recipient email (defaults to the
          calling user's email). Mirrors the test_send controller action: uses the same
          render pipeline, prefixes the subject with [TEST], and never changes campaign
          status or records stats.
        DESC
        arguments_schema(
          type: "object",
          additionalProperties: false,
          required: ["id"],
          properties: {
            id: {type: "integer"},
            recipient_email: {type: "string"}
          }
        )

        def call(arguments:, context:)
          campaign = context.team.campaigns.find(arguments["id"])

          recipient = arguments["recipient_email"] || context.user.email
          user_name = [context.user.first_name, context.user.last_name].compact.join(" ").presence || context.user.email

          fake = Subscriber.new(
            team: campaign.team,
            email: recipient,
            name: user_name,
            external_id: "mcp-test-#{context.user.id}",
            subscribed: true,
            custom_attributes: {}
          )

          original_subject = campaign.subject
          campaign.subject = "[TEST] #{original_subject}"

          begin
            result = SesSender.send_bulk(campaign: campaign, subscribers: [fake])
            {
              sent: result.failed.empty?,
              recipient_email: fake.email,
              message_ids: result.message_ids,
              errors: result.failed.map { |f| f[:error].to_s.sub(/\A(?:render_failed|send_failed):\s*/, "") }
            }
          ensure
            campaign.subject = original_subject
          end
        end
      end
    end
  end
end
