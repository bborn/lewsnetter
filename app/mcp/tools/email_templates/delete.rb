# frozen_string_literal: true

module Mcp
  module Tools
    module EmailTemplates
      class Delete < Mcp::Tool::Base
        include Mcp::Tools::Serializers

        tool_name "email_templates_delete"
        description "Deletes an email template by id from the calling team. Campaigns that reference this template will have their email_template_id set to null (dependent: :nullify)."
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
          id = template.id
          if template.destroy
            {deleted: true, id: id}
          else
            {error: template.errors.full_messages.join(", ")}
          end
        end
      end
    end
  end
end
