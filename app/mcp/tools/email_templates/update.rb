# frozen_string_literal: true

module Mcp
  module Tools
    module EmailTemplates
      class Update < Mcp::Tool::Base
        include Mcp::Tools::Serializers

        tool_name "email_templates_update"
        description "Updates an existing email template by id. Only provided fields are updated."
        arguments_schema(
          type: "object",
          additionalProperties: false,
          required: ["id"],
          properties: {
            id: {type: "integer"},
            name: {type: "string"},
            mjml_body: {type: "string"}
          }
        )

        def call(arguments:, context:)
          template = context.team.email_templates.find_by!(id: arguments["id"])
          attrs = arguments.slice("name", "mjml_body")
          template.update!(attrs)
          {email_template: serialize_email_template(template)}
        end
      end
    end
  end
end
