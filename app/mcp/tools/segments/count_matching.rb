# frozen_string_literal: true

module Mcp
  module Tools
    module Segments
      class CountMatching < Mcp::Tool::Base
        include Mcp::Tools::Serializers

        tool_name "segments_count_matching"
        description "Returns the number of subscribers matching the segment's predicate, plus the total team subscriber count. Returns predicate_error if the predicate is invalid."
        arguments_schema(
          type: "object",
          additionalProperties: false,
          required: ["id"],
          properties: {
            id: {type: "integer"}
          }
        )

        def call(arguments:, context:)
          seg = context.team.segments.find_by!(id: arguments["id"])
          total = context.team.subscribers.count
          begin
            count = seg.applies_to(context.team.subscribers).count
            {segment_id: seg.id, count: count, total_team_subscribers: total, predicate_error: nil}
          rescue Segment::InvalidPredicate => e
            {segment_id: seg.id, count: 0, total_team_subscribers: total, predicate_error: e.message}
          end
        end
      end
    end
  end
end
