# frozen_string_literal: true

module Mcp
  module Tools
    module Subscribers
      class Get < Mcp::Tool::Base
        include Mcp::Tools::Serializers

        tool_name "subscribers_get"
        description "Returns a single subscriber by id. Raises RecordNotFound if the id does not belong to the calling team."
        arguments_schema(
          type: "object",
          additionalProperties: false,
          required: ["id"],
          properties: {
            id: {type: "integer"}
          }
        )

        def call(arguments:, context:)
          sub = context.team.subscribers.find_by!(id: arguments["id"])
          {subscriber: serialize_subscriber(sub)}
        end
      end
    end
  end
end
