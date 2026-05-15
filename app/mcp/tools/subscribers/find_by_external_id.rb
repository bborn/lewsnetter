# frozen_string_literal: true

module Mcp
  module Tools
    module Subscribers
      class FindByExternalId < Mcp::Tool::Base
        include Mcp::Tools::Serializers

        tool_name "subscribers_find_by_external_id"
        description "Looks up a subscriber by external_id within the calling team. Returns null (not an error) when no match is found."
        arguments_schema(
          type: "object",
          additionalProperties: false,
          required: ["external_id"],
          properties: {
            external_id: {type: "string"}
          }
        )

        def call(arguments:, context:)
          sub = context.team.subscribers.find_by(external_id: arguments["external_id"])
          {subscriber: sub ? serialize_subscriber(sub) : nil}
        end
      end
    end
  end
end
