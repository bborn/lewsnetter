# frozen_string_literal: true

module Mcp
  module Tools
    module Team
      class CustomAttributeSchema < Mcp::Tool::Base
        tool_name "team_custom_attribute_schema"
        description "Returns the observed schema of custom_attributes across the team's subscribers. Useful for understanding what fields are available for segmentation and personalization."
        arguments_schema(
          type: "object",
          additionalProperties: false,
          properties: {
            limit: {type: "integer", minimum: 1, maximum: 500, default: 50}
          }
        )

        def call(arguments:, context:)
          limit = arguments["limit"] || 50
          result = ::Team::CustomAttributeSchema.new(team: context.team, limit: limit).call
          {custom_attributes: result[:sample], sample_size: result[:sample_size]}
        end
      end
    end
  end
end
