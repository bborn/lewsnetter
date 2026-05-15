# frozen_string_literal: true

module Mcp
  module Tools
    module EmailTemplates
      class List < Mcp::Tool::Base
        include Mcp::Tools::Serializers

        tool_name "email_templates_list"
        description "Lists email templates on the calling team. Supports limit and offset for pagination."
        arguments_schema(
          type: "object",
          additionalProperties: false,
          properties: {
            limit: {type: "integer", minimum: 1, maximum: 200, default: 50},
            offset: {type: "integer", minimum: 0, default: 0}
          }
        )

        def call(arguments:, context:)
          scope = context.team.email_templates
          total = scope.count
          limit = arguments["limit"] || 50
          offset = arguments["offset"] || 0
          rows = scope.order(:id).limit(limit).offset(offset).map { |t| serialize_email_template(t) }
          {email_templates: rows, total: total, limit: limit, offset: offset}
        end
      end
    end
  end
end
