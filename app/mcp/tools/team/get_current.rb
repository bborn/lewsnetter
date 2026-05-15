# frozen_string_literal: true

module Mcp
  module Tools
    module Team
      class GetCurrent < Mcp::Tool::Base
        tool_name "team_get_current"
        description "Returns the id, name, and slug of the team that owns the calling token."
        arguments_schema(type: "object", properties: {}, additionalProperties: false)

        def call(arguments:, context:)
          team = context.team
          {id: team.id, name: team.name, slug: team.slug}
        end
      end
    end
  end
end
