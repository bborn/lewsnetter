# frozen_string_literal: true

module Mcp
  module Tools
    module Segments
      class Delete < Mcp::Tool::Base
        include Mcp::Tools::Serializers

        tool_name "segments_delete"
        description "Deletes a segment by id from the calling team. Returns an error if the segment has campaigns that reference it."
        arguments_schema(
          type: "object",
          additionalProperties: false,
          required: ["id"],
          properties: {
            id: {type: "integer"}
          }
        )

        def call(arguments:, context:)
          seg = context.team.segments.find(arguments["id"])
          id = seg.id
          if seg.destroy
            {deleted: true, id: id}
          else
            {error: seg.errors.full_messages.join(", ")}
          end
        end
      end
    end
  end
end
