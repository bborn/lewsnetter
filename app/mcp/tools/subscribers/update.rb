# frozen_string_literal: true

module Mcp
  module Tools
    module Subscribers
      class Update < Mcp::Tool::Base
        include Mcp::Tools::Serializers

        tool_name "subscribers_update"
        description "Partially updates a subscriber on the calling team. Only fields provided are changed."
        arguments_schema(
          type: "object",
          additionalProperties: false,
          required: ["id"],
          properties: {
            id: {type: "integer"},
            email: {type: "string", format: "email"},
            name: {type: "string"},
            subscribed: {type: "boolean"},
            custom_attributes: {type: "object"}
          }
        )

        def call(arguments:, context:)
          sub = context.team.subscribers.find_by!(id: arguments["id"])
          attrs = arguments.slice("email", "name", "subscribed", "custom_attributes")
          sub.update!(attrs)
          {subscriber: serialize_subscriber(sub)}
        end
      end
    end
  end
end
