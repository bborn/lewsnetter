# frozen_string_literal: true

module Mcp
  module Tools
    module Subscribers
      class Count < Mcp::Tool::Base
        include Mcp::Tools::Serializers

        tool_name "subscribers_count"
        description "Returns the count of subscribers on the calling team, optionally filtered by subscribed status."
        arguments_schema(
          type: "object",
          additionalProperties: false,
          properties: {
            subscribed: {type: "boolean"}
          }
        )

        def call(arguments:, context:)
          scope = context.team.subscribers
          scope = scope.where(subscribed: arguments["subscribed"]) if arguments.key?("subscribed")
          {count: scope.count}
        end
      end
    end
  end
end
