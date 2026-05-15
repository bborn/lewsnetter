# frozen_string_literal: true

module Mcp
  module Tools
    module EmailTemplates
      class RenderPreview < Mcp::Tool::Base
        include Mcp::Tools::Serializers

        tool_name "email_templates_render_preview"
        description <<~DESC
          Renders an email template to HTML for preview. Optionally supply a subscriber_id
          to use that subscriber's attributes for variable substitution, or a sample_data
          hash (e.g. {"name":"Sample User","plan":"growth"}) to inject arbitrary variables.
          If neither is given, {{var}} placeholders render unfilled but the MJML chrome
          compiles. Render errors are returned in the errors array rather than raised.
        DESC
        arguments_schema(
          type: "object",
          additionalProperties: false,
          required: ["id"],
          properties: {
            id: {type: "integer"},
            subscriber_id: {type: "integer"},
            sample_data: {type: "object"}
          }
        )

        def call(arguments:, context:)
          template = context.team.email_templates.find(arguments["id"])

          subscriber = build_subscriber(arguments, context, template)

          fake_campaign = Campaign.new(
            team: context.team,
            email_template: template,
            subject: "Subject preview",
            preheader: "Preheader preview",
            body_markdown: sample_body_markdown,
            body_mjml: nil,
            status: "draft"
          )

          errors = []
          html = begin
            CampaignRenderer.new(campaign: fake_campaign, subscriber: subscriber).call.html
          rescue => e
            errors << "#{e.class}: #{e.message}"
            nil
          end

          {
            html: html,
            byte_size: html&.bytesize,
            errors: errors
          }
        end

        private

        def build_subscriber(arguments, context, template)
          if arguments["subscriber_id"]
            # Use a real subscriber — find scoped to team for security.
            context.team.subscribers.find(arguments["subscriber_id"])
          elsif arguments["sample_data"]
            # Build an in-memory subscriber whose custom_attributes carry the
            # sample_data so CampaignRenderer's substitute() picks them up.
            sample = arguments["sample_data"].transform_keys(&:to_s)
            Subscriber.new(
              team: context.team,
              email: sample.delete("email") || "preview@example.com",
              name: sample.delete("name") || "Preview User",
              external_id: "mcp-preview",
              subscribed: true,
              custom_attributes: sample
            )
          else
            # No context — render with empty attributes so placeholders show.
            Subscriber.new(
              team: context.team,
              email: "preview@example.com",
              name: "Preview User",
              external_id: "mcp-preview",
              subscribed: true,
              custom_attributes: {}
            )
          end
        end

        def sample_body_markdown
          <<~MD
            ## Section heading

            This is sample body content so you can see how the template chrome wraps a
            campaign. The real campaign body goes here when this template is used.

            - Lists render in the template's body font
            - **Bold**, *italic*, and [links](https://example.com) get the chrome's typography

            [Sample call to action →](https://example.com)
          MD
        end
      end
    end
  end
end
