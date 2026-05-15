# frozen_string_literal: true

module Mcp
  module Tools
    module Campaigns
      class Create < Mcp::Tool::Base
        include Mcp::Tools::Serializers

        tool_name "campaigns_create"
        description <<~DESC
          Creates a new campaign (status defaults to "draft"). Requires a subject.
          Provide body_markdown, body_mjml, or an email_template_id with body content —
          at least one body source is required. Raises ActiveRecord::RecordInvalid on
          validation failure.
        DESC
        arguments_schema(
          type: "object",
          additionalProperties: false,
          required: ["subject"],
          properties: {
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
          attrs = arguments.slice(*PERMITTED)
          attrs["status"] = "draft"
          if (sf = attrs.delete("scheduled_for"))
            attrs["scheduled_for"] = Time.parse(sf)
          end
          campaign = context.team.campaigns.create!(attrs)
          {campaign: serialize_campaign(campaign)}
        end
      end
    end
  end
end
