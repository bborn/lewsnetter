# frozen_string_literal: true

module Mcp
  module Tools
    module Campaigns
      class List < Mcp::Tool::Base
        include Mcp::Tools::Serializers

        tool_name "campaigns_list"
        description "Lists campaigns on the calling team. Supports pagination and optional status filter."
        arguments_schema(
          type: "object",
          additionalProperties: false,
          properties: {
            limit: {type: "integer", minimum: 1, maximum: 200, default: 50},
            offset: {type: "integer", minimum: 0, default: 0},
            status: {type: "string", enum: %w[draft scheduled sending sent failed]}
          }
        )

        def call(arguments:, context:)
          scope = context.team.campaigns
          scope = scope.where(status: arguments["status"]) if arguments["status"]
          total = scope.count
          limit = arguments["limit"] || 50
          offset = arguments["offset"] || 0
          rows = scope.order(:id).limit(limit).offset(offset).map { |c| serialize_campaign(c) }
          {campaigns: rows, total: total, limit: limit, offset: offset}
        end
      end
    end
  end
end
