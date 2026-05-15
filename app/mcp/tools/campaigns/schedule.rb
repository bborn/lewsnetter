# frozen_string_literal: true

module Mcp
  module Tools
    module Campaigns
      class Schedule < Mcp::Tool::Base
        include Mcp::Tools::Serializers

        tool_name "campaigns_schedule"
        description <<~DESC
          Schedules a campaign for future delivery by setting status to "scheduled" and
          recording the scheduled_for datetime. The scheduled_for argument must be an
          ISO8601 datetime string. Raises ArgumentError if the string cannot be parsed.
        DESC
        arguments_schema(
          type: "object",
          additionalProperties: false,
          required: ["id", "scheduled_for"],
          properties: {
            id: {type: "integer"},
            scheduled_for: {type: "string", description: "ISO8601 datetime string"}
          }
        )

        def call(arguments:, context:)
          campaign = context.team.campaigns.find_by!(id: arguments["id"])

          parsed_time = begin
            Time.parse(arguments["scheduled_for"])
          rescue ArgumentError, TypeError
            raise Mcp::Tool::ArgumentError, "scheduled_for must be ISO8601"
          end

          campaign.update!(status: "scheduled", scheduled_for: parsed_time)

          {
            scheduled: true,
            scheduled_for: parsed_time.iso8601,
            campaign: serialize_campaign(campaign)
          }
        end
      end
    end
  end
end
