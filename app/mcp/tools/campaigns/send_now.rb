# frozen_string_literal: true

module Mcp
  module Tools
    module Campaigns
      class SendNow < Mcp::Tool::Base
        include Mcp::Tools::Serializers

        tool_name "campaigns_send_now"
        description <<~DESC
          Enqueues the campaign for immediate delivery via SendCampaignJob. Only draft
          or scheduled campaigns are sendable — any other status returns an error.
          Returns the enqueued status and the expected status_after ("sending") plus the
          subscriber count that will receive the campaign.
        DESC
        arguments_schema(
          type: "object",
          additionalProperties: false,
          required: ["id"],
          properties: {
            id: {type: "integer"}
          }
        )

        def call(arguments:, context:)
          campaign = context.team.campaigns.find_by!(id: arguments["id"])

          unless campaign.sendable?
            return {
              enqueued: false,
              campaign_id: campaign.id,
              status_after: campaign.status,
              error: "Only draft or scheduled campaigns can be sent (current status: #{campaign.status})"
            }
          end

          subscriber_count = campaign.recipient_count || 0
          SendCampaignJob.perform_later(campaign.id)

          {
            enqueued: true,
            campaign_id: campaign.id,
            status_after: "sending",
            subscriber_count: subscriber_count
          }
        end
      end
    end
  end
end
