# frozen_string_literal: true

module Mcp
  module Tools
    module Sequences
      # Turns the calling team's Sequences feature on or off. Off stops all
      # enrollment and sending without touching any sequence's own status.
      class SetEnabled < Mcp::Tool::Base
        tool_name "sequences_set_enabled"
        description "Turns the calling team's Sequences feature on or off (teams.sequences_enabled). " \
          "Off: nothing enrolls or sends, whatever each sequence's status. On: only sequences with " \
          "status active enroll and send; drafts and paused ones stay idle. Returns the flag and " \
          "how many sequences are active."
        arguments_schema(
          type: "object",
          additionalProperties: false,
          required: ["enabled"],
          properties: {enabled: {type: "boolean"}}
        )

        def call(arguments:, context:)
          team = context.team
          team.update!(sequences_enabled: arguments["enabled"])
          {sequences_enabled: team.sequences_enabled?,
           active_sequences: team.sequences.where(status: "active").count}
        end
      end
    end
  end
end
