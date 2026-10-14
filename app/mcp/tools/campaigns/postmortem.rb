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
          SES before reaching the network. `opened`, `clicked` and `clicks_total`
          count HUMAN engagement only: link-scanner clicks (Safe Links,
          Proofpoint, Mimecast, near-instant clicks, honeypot hits) and Apple
          Mail Privacy Protection / scanner opens are excluded and reported in
          `opened_automated` / `clicked_automated`. The `*_raw` keys are the
          unfiltered counts. top_links gives human `clicks` / `unique_clicks`
          per URL plus `automated_clicks`.
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

          # Opens + clicks are HUMAN numbers; machine traffic (link
          # scanners, Apple MPP, honeypot hits) is reported alongside in
          # the *_automated / *_raw keys. See Campaign#delivery_stats.
          stats = campaign.delivery_stats

          # top_links: aggregated from ClickEvent rows — `clicks` and
          # `unique_clicks` are human, `automated_clicks` is scanner traffic
          # (see Campaign#top_links). Falls back to the legacy
          # `campaign.stats["links"]` blob when no clicks have been
          # recorded yet, so older campaigns whose links got persisted into
          # the stats JSON column still surface here.
          tracked = campaign.top_links(limit: 10).map do |row|
            {
              url: row[:url],
              clicks: row[:total_clicks],
              unique_clicks: row[:unique_clicks],
              automated_clicks: row[:automated_clicks]
            }
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
