# frozen_string_literal: true

module Mcp
  module Tools
    module Events
      class Track < Mcp::Tool::Base
        include Mcp::Tools::Serializers

        tool_name "events_track"
        description "Tracks a single event for a subscriber, resolved by external_id. Raises RecordNotFound if the subscriber does not exist on the calling team."
        arguments_schema(
          type: "object",
          additionalProperties: false,
          required: ["external_subscriber_id", "name"],
          properties: {
            external_subscriber_id: {type: "string"},
            name: {type: "string"},
            occurred_at: {type: "string", description: "ISO8601 datetime. Defaults to now."},
            properties: {type: "object"}
          }
        )

        def call(arguments:, context:)
          sub = context.team.subscribers.find_by!(external_id: arguments["external_subscriber_id"])

          occurred_at = if arguments["occurred_at"].present?
            Time.parse(arguments["occurred_at"])
          else
            Time.current
          end

          event = sub.events.create!(
            team: context.team,
            name: arguments["name"],
            occurred_at: occurred_at,
            properties: arguments["properties"] || {}
          )

          {event: serialize_event(event), subscriber_id: sub.id}
        end
      end
    end
  end
end
