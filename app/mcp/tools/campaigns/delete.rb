# frozen_string_literal: true

module Mcp
  module Tools
    module Campaigns
      class Delete < Mcp::Tool::Base
        include Mcp::Tools::Serializers

        tool_name "campaigns_delete"
        description "Deletes a campaign by id. Raises RecordNotFound if the campaign does not belong to the calling team."
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
          id = campaign.id
          campaign.destroy!
          {deleted: true, id: id}
        end
      end
    end
  end
end
