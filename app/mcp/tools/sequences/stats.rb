# frozen_string_literal: true

module Mcp
  module Tools
    module Sequences
      class Stats < Mcp::Tool::Base
        tool_name "sequences_stats"
        description "Per-step funnel for one sequence: for each step, how many subscribers are " \
          "waiting on it, how many were skipped by its skip segment, and sent / delivered / " \
          "opened / clicked / bounced / unsubscribed from its deliveries. Also returns " \
          "enrollment counts by state and exit reason."
        arguments_schema(
          type: "object",
          additionalProperties: false,
          required: ["id"],
          properties: {
            id: {type: "integer", description: "Sequence id (from sequences_list)."}
          }
        )

        def call(arguments:, context:)
          sequence = context.team.sequences.find_by!(id: arguments["id"])
          {
            id: sequence.id,
            name: sequence.name,
            status: sequence.status,
            enrollments: sequence.enrollment_counts,
            exit_reasons: sequence.enrollments.where.not(exit_reason: nil).group(:exit_reason).count,
            steps: sequence.step_stats.map { |row|
              step = row[:step]
              row.except(:step).merge(
                id: step.id,
                subject: step.subject,
                delay_minutes: step.delay_minutes,
                skip_segment_id: step.skip_segment_id,
                sent_tag: step.sent_tag,
                action: step.action? ? {on: step.action_trigger, tag: step.action_tag, exit: step.action_exit} : nil
              )
            }
          }
        end
      end
    end
  end
end
