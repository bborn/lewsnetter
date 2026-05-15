# frozen_string_literal: true

module Mcp
  module Tools
    module Segments
      class Get < Mcp::Tool::Base
        include Mcp::Tools::Serializers

        tool_name "segments_get"
        description "Returns a single segment by id. Raises RecordNotFound if the id does not belong to the calling team."
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
          {segment: serialize_segment(seg)}
        end
      end
    end
  end
end
