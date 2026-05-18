# frozen_string_literal: true

module Mcp
  module Tools
    module Campaigns
      class Postmortem < Mcp::Tool::Base
        include Mcp::Tools::Serializers

        tool_name "campaigns_postmortem"
        description <<~DESC
          Returns per-recipient delivery stats for a sent campaign. Counters are
          aggregated from the campaign's Delivery rows — one row per (campaign,
          subscriber) pair, written at send time and updated by SES SNS event
          webhooks (Bounce, Complaint, Delivery, Reject). The "failed" counter
          covers sends that errored locally (render failure) or were rejected by
          SES before reaching the network. Open + click counters are populated by
          client-side tracking in a follow-up phase and will be 0 until then.
          Use top_links for click-through data when available.
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
          deliveries = campaign.deliveries

          stats = {
            sent: deliveries.where.not(ses_message_id: nil).count,
            delivered: deliveries.where.not(delivered_at: nil).count,
            opened: deliveries.where.not(opened_at: nil).count,
            clicked: deliveries.where.not(clicked_at: nil).count,
            bounced: deliveries.bounced.count,
            complained: deliveries.complained.count,
            unsubscribed: deliveries.where.not(unsubscribed_at: nil).count,
            failed: deliveries.where(status: "failed").count
          }

          # top_links: aggregated from the per-recipient Delivery rows via
          # `last_clicked_url` + `click_count` (see Campaign#top_links for
          # the methodology + caveats). Falls back to the legacy
          # `campaign.stats["links"]` blob when no clicks have been
          # recorded yet, so older campaigns whose links got persisted into
          # the stats JSON column still surface here.
          tracked = campaign.top_links(limit: 10).map do |row|
            {url: row[:url], clicks: row[:total_clicks], unique_clicks: row[:unique_clicks]}
          end

          top_links =
            if tracked.any?
              tracked
            else
              legacy_links = Array((campaign.stats || {})["links"])
              legacy_links.first(10).map do |link|
                link.is_a?(Hash) ? link : {url: link.to_s, clicks: 0}
              end
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
