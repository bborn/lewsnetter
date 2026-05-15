# frozen_string_literal: true

module Mcp
  module Tools
    module Segments
      class Create < Mcp::Tool::Base
        include Mcp::Tools::Serializers

        tool_name "segments_create"
        description "Creates a new segment on the calling team. The predicate is a SQL WHERE fragment applied to the subscribers table."
        arguments_schema(
          type: "object",
          additionalProperties: false,
          required: ["name"],
          properties: {
            name: {type: "string"},
            predicate: {type: "string"},
            natural_language_source: {type: "string"}
          }
        )

        def call(arguments:, context:)
          attrs = arguments.slice("name", "predicate", "natural_language_source")
          seg = context.team.segments.create!(attrs)
          {segment: serialize_segment(seg)}
        end
      end
    end
  end
end
