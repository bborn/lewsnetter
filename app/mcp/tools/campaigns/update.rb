# frozen_string_literal: true

module Mcp
  module Tools
    module Campaigns
      class Update < Mcp::Tool::Base
        include Mcp::Tools::Serializers

        tool_name "campaigns_update"
        description <<~DESC
          Updates an existing campaign. The model enforces that sent campaigns cannot
          have their body changed. Validation errors raise ActiveRecord::RecordInvalid.
        DESC
        arguments_schema(
          type: "object",
          additionalProperties: false,
          required: ["id"],
          properties: {
            id: {type: "integer"},
            subject: {type: "string"},
            preheader: {type: "string"},
            body_markdown: {type: "string"},
            body_mjml: {type: "string"},
            email_template_id: {type: "integer"},
            segment_id: {type: "integer"},
            sender_address_id: {type: "integer"},
            scheduled_for: {type: "string", description: "ISO8601 datetime string"}
          }
        )

        PERMITTED = %w[subject preheader body_markdown body_mjml email_template_id
          segment_id sender_address_id scheduled_for].freeze

        def call(arguments:, context:)
          campaign = context.team.campaigns.find_by!(id: arguments["id"])
          attrs = arguments.slice(*PERMITTED)
          if (sf = attrs.delete("scheduled_for"))
            attrs["scheduled_for"] = Time.parse(sf)
          end
          campaign.update!(attrs)
          {campaign: serialize_campaign(campaign)}
        end
      end
    end
  end
end
