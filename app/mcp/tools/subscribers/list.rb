# frozen_string_literal: true

module Mcp
  module Tools
    module Subscribers
      class List < Mcp::Tool::Base
        include Mcp::Tools::Serializers

        tool_name "subscribers_list"
        description "Lists subscribers on the calling team. Supports limit, offset, subscribed filter, and a query that matches email or external_id."
        arguments_schema(
          type: "object",
          additionalProperties: false,
          properties: {
            limit: {type: "integer", minimum: 1, maximum: 200, default: 50},
            offset: {type: "integer", minimum: 0, default: 0},
            subscribed: {type: "boolean"},
            query: {type: "string"}
          }
        )

        def call(arguments:, context:)
          scope = context.team.subscribers
          scope = scope.where(subscribed: arguments["subscribed"]) if arguments.key?("subscribed")
          if (q = arguments["query"]).present?
            like = "%#{q}%"
            scope = scope.where("email LIKE ? OR external_id LIKE ?", like, like)
          end
          total = scope.count
          limit = arguments["limit"] || 50
          offset = arguments["offset"] || 0
          rows = scope.order(:id).limit(limit).offset(offset).map { |s| serialize_subscriber(s) }
          {subscribers: rows, total: total, limit: limit, offset: offset}
        end
      end
    end
  end
end
