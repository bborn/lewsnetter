# frozen_string_literal: true

module Mcp
  module Tools
    module Subscribers
      class Create < Mcp::Tool::Base
        include Mcp::Tools::Serializers

        tool_name "subscribers_create"
        description "Creates a subscriber on the calling team, or updates the existing one if external_id matches."
        arguments_schema(
          type: "object",
          additionalProperties: false,
          required: ["email"],
          properties: {
            email: {type: "string", format: "email"},
            name: {type: "string"},
            external_id: {type: "string"},
            subscribed: {type: "boolean"},
            custom_attributes: {type: "object"}
          }
        )

        def call(arguments:, context:)
          attrs = arguments.slice("email", "name", "external_id", "subscribed", "custom_attributes")
          existing = if attrs["external_id"].present?
            context.team.subscribers.find_by(external_id: attrs["external_id"])
          end
          if existing
            existing.update!(attrs.except("external_id"))
            {subscriber: serialize_subscriber(existing), upserted: true}
          else
            sub = context.team.subscribers.create!(attrs)
            {subscriber: serialize_subscriber(sub), upserted: false}
          end
        end
      end
    end
  end
end
