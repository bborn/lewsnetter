# frozen_string_literal: true

module Mcp
  module Tools
    module Sequences
      class List < Mcp::Tool::Base
        tool_name "sequences_list"
        description "Lists automated email sequences on the calling team with their trigger, " \
          "status, step count and enrollment counts by state. `sequences_enabled` says whether " \
          "the team's Sequences feature flag is on (when off, nothing enrolls or sends)."
        arguments_schema(
          type: "object",
          additionalProperties: false,
          properties: {
            status: {type: "string", enum: ::Sequence::STATUSES},
            limit: {type: "integer", minimum: 1, maximum: 200, default: 50},
            offset: {type: "integer", minimum: 0, default: 0}
          }
        )

        def call(arguments:, context:)
          scope = context.team.sequences
          scope = scope.where(status: arguments["status"]) if arguments["status"]
          total = scope.count
          limit = arguments["limit"] || 50
          offset = arguments["offset"] || 0
          rows = scope.includes(:steps).order(:id).limit(limit).offset(offset).map { |s| serialize(s) }
          {sequences_enabled: context.team.sequences_enabled?, sequences: rows,
           total: total, limit: limit, offset: offset}
        end

        private

        def serialize(s)
          {
            id: s.id,
            name: s.name,
            status: s.status,
            trigger_type: s.trigger_type,
            trigger_event_name: s.trigger_event_name,
            trigger_segment_id: s.trigger_segment_id,
            exit_segment_id: s.exit_segment_id,
            reentry_days: s.reentry_days,
            goal_segment_id: s.goal_segment_id,
            goal_event_name: s.goal_event_name,
            excluded_sequence_ids: s.excluded_sequence_ids,
            finish_after_minutes: s.finish_after_minutes,
            completed_tag: s.completed_tag,
            sender_address_id: s.sender_address_id,
            steps_count: s.steps.size,
            enrollments: s.enrollment_counts,
            created_at: s.created_at.iso8601,
            updated_at: s.updated_at.iso8601
          }
        end
      end
    end
  end
end
