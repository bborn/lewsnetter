# frozen_string_literal: true

module Mcp
  module Tools
    module Sequences
      # Edits one sequence's settings: status (draft / active / paused) and the
      # segments that gate it. Steps are not edited here.
      class Update < Mcp::Tool::Base
        tool_name "sequences_update"
        description "Updates a sequence on the calling team by id. All fields optional. " \
          "status: draft, active or paused (active only enrolls and sends while the team's " \
          "sequences_enabled flag is on, see sequences_set_enabled). exit_segment_id, " \
          "goal_segment_id and trigger_segment_id take a segment id from segments_list, or null " \
          "to clear (trigger_segment_id is required for segment-triggered sequences). A " \
          "subscriber in the exit segment is never enrolled and leaves if already in. " \
          "reentry_days null means once ever."
        arguments_schema(
          type: "object",
          additionalProperties: false,
          required: ["id"],
          properties: {
            id: {type: "integer"},
            name: {type: "string"},
            status: {type: "string", enum: ::Sequence::STATUSES},
            exit_segment_id: {type: ["integer", "null"]},
            goal_segment_id: {type: ["integer", "null"]},
            trigger_segment_id: {type: ["integer", "null"]},
            goal_event_name: {type: ["string", "null"]},
            reentry_days: {type: ["integer", "null"], minimum: 1}
          }
        )

        FIELDS = %w[name status exit_segment_id goal_segment_id trigger_segment_id goal_event_name reentry_days].freeze

        def call(arguments:, context:)
          sequence = context.team.sequences.find_by!(id: arguments["id"])
          sequence.update!(arguments.slice(*FIELDS))
          {sequence: List.new.send(:serialize, sequence.reload),
           sequences_enabled: context.team.sequences_enabled?}
        rescue ActiveRecord::RecordInvalid => e
          raise Mcp::Tool::ArgumentError, e.record.errors.full_messages.to_sentence
        end
      end
    end
  end
end
