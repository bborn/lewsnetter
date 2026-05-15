# frozen_string_literal: true

module Mcp
  module Tools
    module SenderAddresses
      class Get < Mcp::Tool::Base
        include Mcp::Tools::Serializers

        tool_name "sender_addresses_get"
        description "Fetches a single sender address by id. Raises RecordNotFound if it does not belong to the calling team."
        arguments_schema(
          type: "object",
          additionalProperties: false,
          required: ["id"],
          properties: {
            id: {type: "integer"}
          }
        )

        def call(arguments:, context:)
          sa = context.team.sender_addresses.find(arguments["id"])
          {sender_address: serialize_sender_address(sa)}
        end
      end
    end
  end
end
