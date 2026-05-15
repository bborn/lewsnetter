# frozen_string_literal: true

module Mcp
  module Tools
    module Segments
      class SampleMatching < Mcp::Tool::Base
        include Mcp::Tools::Serializers

        tool_name "segments_sample_matching"
        description "Returns a sample of subscribers matching the segment's predicate. Returns predicate_error if the predicate is invalid."
        arguments_schema(
          type: "object",
          additionalProperties: false,
          required: ["id"],
          properties: {
            id: {type: "integer"},
            limit: {type: "integer", minimum: 1, maximum: 50, default: 10}
          }
        )

        def call(arguments:, context:)
          seg = context.team.segments.find_by!(id: arguments["id"])
          limit = arguments["limit"] || 10
          begin
            matching_scope = seg.applies_to(context.team.subscribers)
            total_matching = matching_scope.count
            sample = matching_scope.order(:id).limit(limit).map { |s| serialize_subscriber(s) }
            {segment_id: seg.id, sample: sample, total_matching: total_matching, predicate_error: nil}
          rescue Segment::InvalidPredicate => e
            {segment_id: seg.id, sample: [], total_matching: 0, predicate_error: e.message}
          end
        end
      end
    end
  end
end
