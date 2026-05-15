# frozen_string_literal: true

module Mcp
  module Tools
    module EmailTemplates
      class Get < Mcp::Tool::Base
        include Mcp::Tools::Serializers

        tool_name "email_templates_get"
        description "Returns a single email template by id. Raises RecordNotFound if the id does not belong to the calling team."
        arguments_schema(
          type: "object",
          additionalProperties: false,
          required: ["id"],
          properties: {
            id: {type: "integer"}
          }
        )

        def call(arguments:, context:)
          template = context.team.email_templates.find(arguments["id"])
          {email_template: serialize_email_template(template)}
        end
      end
    end
  end
end
