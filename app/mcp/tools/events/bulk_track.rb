# frozen_string_literal: true

module Mcp
  module Tools
    module Events
      class BulkTrack < Mcp::Tool::Base
        include Mcp::Tools::Serializers

        tool_name "events_bulk_track"
        description "Tracks multiple events in a single call. Each record is processed independently — per-record errors (unknown subscriber, validation failure) are collected in the errors array without aborting the batch. The entire batch is wrapped in a transaction so a catastrophic failure rolls back cleanly."
        arguments_schema(
          type: "object",
          additionalProperties: false,
          required: ["events"],
          properties: {
            events: {
              type: "array",
              maxItems: 500,
              items: {
                type: "object",
                additionalProperties: false,
                required: ["external_subscriber_id", "name"],
                properties: {
                  external_subscriber_id: {type: "string"},
                  name: {type: "string"},
                  occurred_at: {type: "string", description: "ISO8601 datetime. Defaults to now."},
                  properties: {type: "object"}
                }
              }
            }
          }
        )

        def call(arguments:, context:)
          records = arguments["events"]
          created = 0
          errors = []

          ActiveRecord::Base.transaction do
            records.each_with_index do |row, i|
              begin
                sub = context.team.subscribers.find_by(external_id: row["external_subscriber_id"])
                if sub.nil?
                  errors << {index: i, error: "subscriber not found: #{row["external_subscriber_id"]}"}
                  next
                end

                occurred_at = if row["occurred_at"].present?
                  Time.parse(row["occurred_at"])
                else
                  Time.current
                end

                sub.events.create!(
                  team: context.team,
                  name: row["name"],
                  occurred_at: occurred_at,
                  properties: row["properties"] || {}
                )
                created += 1
              rescue ActiveRecord::RecordInvalid => e
                errors << {index: i, error: e.message}
              rescue => e
                errors << {index: i, error: "#{e.class}: #{e.message}"}
              end
            end
          end

          {created: created, errors: errors}
        end
      end
    end
  end
end
