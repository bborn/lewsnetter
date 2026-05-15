# frozen_string_literal: true

module Mcp
  module Tools
    module Events
      class ListForSubscriber < Mcp::Tool::Base
        include Mcp::Tools::Serializers

        tool_name "events_list_for_subscriber"
        description "Lists events for a subscriber, scoped to the calling team. Returns events ordered by occurred_at descending. Raises RecordNotFound if the subscriber does not belong to the team."
        arguments_schema(
          type: "object",
          additionalProperties: false,
          required: ["subscriber_id"],
          properties: {
            subscriber_id: {type: "integer"},
            limit: {type: "integer", minimum: 1, maximum: 200, default: 50},
            offset: {type: "integer", minimum: 0, default: 0}
          }
        )

        def call(arguments:, context:)
          sub = context.team.subscribers.find_by!(id: arguments["subscriber_id"])
          scope = sub.events.order(occurred_at: :desc)
          total = scope.count
          limit = arguments["limit"] || 50
          offset = arguments["offset"] || 0
          {
            events: scope.limit(limit).offset(offset).map { |e| serialize_event(e) },
            total: total,
            limit: limit,
            offset: offset,
            subscriber_id: sub.id
          }
        end
      end
    end
  end
end
