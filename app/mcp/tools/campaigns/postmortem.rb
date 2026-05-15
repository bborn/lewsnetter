# frozen_string_literal: true

module Mcp
  module Tools
    module Campaigns
      class Postmortem < Mcp::Tool::Base
        include Mcp::Tools::Serializers

        tool_name "campaigns_postmortem"
        description <<~DESC
          Returns delivery stats for a sent campaign. The "sent" and "failed" counters
          come from campaign.stats (populated by SendCampaignJob). The opened, clicked,
          bounced, complained, and unsubscribed counters are read from campaign.stats
          where available; the current implementation does not persist per-campaign
          event-level stats back to the campaigns table (opens/clicks/bounces from SES
          SNS update subscriber records, not campaign stats), so those counters will be
          0 unless the job recorded them. Use top_links for click-through data when
          available.
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
          campaign = context.team.campaigns.find(arguments["id"])
          s = (campaign.stats || {})

          stats = {
            sent: s["sent"].to_i,
            opened: s["opens"].to_i,
            clicked: s["clicks"].to_i,
            bounced: s["bounces"].to_i,
            complained: s["complaints"].to_i,
            unsubscribed: s["unsubscribed"].to_i
          }

          # top_links: extract from stats["links"] if the job ever records it.
          top_links = Array(s["links"]).first(10).map do |link|
            link.is_a?(Hash) ? link : {url: link.to_s, clicks: 0}
          end

          {
            stats: stats,
            top_links: top_links,
            analyzed_at: Time.current.iso8601
          }
        end
      end
    end
  end
end
