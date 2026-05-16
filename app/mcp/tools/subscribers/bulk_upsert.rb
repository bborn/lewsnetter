# frozen_string_literal: true

module Mcp
  module Tools
    module Subscribers
      class BulkUpsert < Mcp::Tool::Base
        include Mcp::Tools::Serializers

        tool_name "subscribers_bulk_upsert"
        description "Creates or updates multiple subscribers in a single call. Each record is processed independently — per-record errors are reported in the errors array without aborting the batch. The entire operation is wrapped in a transaction so a catastrophic failure rolls back cleanly."
        arguments_schema(
          type: "object",
          additionalProperties: false,
          required: ["records"],
          properties: {
            records: {
              type: "array",
              items: {
                type: "object",
                additionalProperties: true,
                required: ["email"],
                properties: {
                  email: {type: "string"},
                  name: {type: "string"},
                  external_id: {type: "string"},
                  subscribed: {type: "boolean"},
                  custom_attributes: {type: "object"}
                }
              }
            }
          }
        )

        def call(arguments:, context:)
          records = arguments["records"]
          created = 0
          updated = 0
          errors = []

          ActiveRecord::Base.transaction do
            records.each_with_index do |record, index|
              begin
                attrs = record.slice("email", "name", "external_id", "subscribed", "custom_attributes")
                attrs["custom_attributes"] = ::Subscribers::AttributeNormalizer.call(attrs["custom_attributes"]) if attrs["custom_attributes"].present?
                existing = if attrs["external_id"].present?
                  context.team.subscribers.find_by(external_id: attrs["external_id"])
                end
                if existing
                  existing.update!(attrs.except("external_id"))
                  updated += 1
                else
                  context.team.subscribers.create!(attrs)
                  created += 1
                end
              rescue => e
                errors << {index: index, error: e.message}
              end
            end
          end

          {created: created, updated: updated, errors: errors}
        end
      end
    end
  end
end
