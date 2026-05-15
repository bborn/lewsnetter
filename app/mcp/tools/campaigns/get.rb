# frozen_string_literal: true

module Mcp
  module Tools
    module Campaigns
      class Get < Mcp::Tool::Base
        include Mcp::Tools::Serializers

        tool_name "campaigns_get"
        description "Fetches a single campaign by id. Raises RecordNotFound if the campaign does not belong to the calling team."
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
          {campaign: serialize_campaign(campaign)}
        end
      end
    end
  end
end
