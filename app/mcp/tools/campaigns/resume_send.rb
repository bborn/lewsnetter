# frozen_string_literal: true

module Mcp
  module Tools
    module Campaigns
      class ResumeSend < Mcp::Tool::Base
        include Mcp::Tools::Serializers
        include Mcp::Tool::AudienceGuard

        tool_name "campaigns_resume_send"

        requires_ability :send_now, ::Campaign
        hidden_from_in_app_agent
        destructive
        description <<~DESC
          Resumes an interrupted send: a campaign whose status is "failed", or one stuck
          in "sending" with no progress for #{::Campaign::STUCK_SENDING_AFTER.inspect}. Only
          subscribers who don't already have a delivery for this campaign are mailed, so
          nobody gets it twice. Any other status returns an error. Returns the number of
          subscribers still to be sent. A campaign with no segment that wasn't sent with
          all_subscribers: true needs all_subscribers: true here too.
        DESC
        arguments_schema(
          type: "object",
          additionalProperties: false,
          required: ["id"],
          properties: {
            id: {type: "integer"},
            all_subscribers: Mcp::Tool::AudienceGuard::ALL_SUBSCRIBERS_PROPERTY
          }
        )

        def call(arguments:, context:)
          campaign = context.team.campaigns.find_by!(id: arguments["id"])

          unless campaign.resumable?
            return {
              enqueued: false,
              campaign_id: campaign.id,
              status_after: campaign.status,
              error: "Only a failed send, or one stuck in sending, can be resumed (current status: #{campaign.status})"
            }
          end

          unless campaign.audience_confirmed?
            require_audience!(campaign, arguments)
            campaign.update_column(:all_subscribers_confirmed, true)
          end

          remaining = campaign.remaining_recipient_count || 0
          SendCampaignJob.perform_later(campaign.id, resume: true)

          {
            enqueued: true,
            campaign_id: campaign.id,
            status_after: "sending",
            remaining_count: remaining
          }
        end
      end
    end
  end
end
