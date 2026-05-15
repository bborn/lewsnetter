# frozen_string_literal: true

module Mcp
  module Tools
    module EmailTemplates
      class Create < Mcp::Tool::Base
        include Mcp::Tools::Serializers

        tool_name "email_templates_create"
        description "Creates a new email template on the calling team."
        arguments_schema(
          type: "object",
          additionalProperties: false,
          required: ["name", "mjml_body"],
          properties: {
            name: {type: "string"},
            mjml_body: {type: "string"}
          }
        )

        def call(arguments:, context:)
          attrs = arguments.slice("name", "mjml_body")
          template = context.team.email_templates.create!(attrs)
          {email_template: serialize_email_template(template)}
        end
      end
    end
  end
end
