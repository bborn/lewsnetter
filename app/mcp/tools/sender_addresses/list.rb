# frozen_string_literal: true

module Mcp
  module Tools
    module SenderAddresses
      class List < Mcp::Tool::Base
        include Mcp::Tools::Serializers

        tool_name "sender_addresses_list"
        description "Lists all sender addresses (from-email identities) on the calling team. No pagination — teams rarely have more than a handful."
        arguments_schema(
          type: "object",
          additionalProperties: false,
          properties: {}
        )

        def call(arguments:, context:)
          rows = context.team.sender_addresses.order(:id).map { |s| serialize_sender_address(s) }
          {sender_addresses: rows}
        end
      end
    end
  end
end
