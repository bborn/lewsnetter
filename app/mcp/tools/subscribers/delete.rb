# frozen_string_literal: true

module Mcp
  module Tools
    module Subscribers
      class Delete < Mcp::Tool::Base
        include Mcp::Tools::Serializers

        tool_name "subscribers_delete"
        description "Deletes a subscriber by id from the calling team. Raises RecordNotFound if the id does not belong to the team."
        arguments_schema(
          type: "object",
          additionalProperties: false,
          required: ["id"],
          properties: {
            id: {type: "integer"}
          }
        )

        def call(arguments:, context:)
          sub = context.team.subscribers.find(arguments["id"])
          id = sub.id
          sub.destroy!
          {deleted: true, id: id}
        end
      end
    end
  end
end
