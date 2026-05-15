# frozen_string_literal: true

module Mcp
  module Tools
    module Segments
      class Update < Mcp::Tool::Base
        include Mcp::Tools::Serializers

        tool_name "segments_update"
        description "Updates an existing segment by id. All fields are optional; passing predicate:\"\" clears the predicate."
        arguments_schema(
          type: "object",
          additionalProperties: false,
          required: ["id"],
          properties: {
            id: {type: "integer"},
            name: {type: "string"},
            predicate: {type: "string"},
            natural_language_source: {type: "string"}
          }
        )

        def call(arguments:, context:)
          seg = context.team.segments.find(arguments["id"])
          attrs = arguments.slice("name", "predicate", "natural_language_source")
          seg.update!(attrs)
          {segment: serialize_segment(seg)}
        end
      end
    end
  end
end
