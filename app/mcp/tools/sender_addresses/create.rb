# frozen_string_literal: true

module Mcp
  module Tools
    module SenderAddresses
      class Create < Mcp::Tool::Base
        include Mcp::Tools::Serializers

        tool_name "sender_addresses_create"
        description "Creates a sender address on the calling team, then queries AWS SES to populate its verification status. The record is saved regardless of whether the SES check succeeds."
        arguments_schema(
          type: "object",
          additionalProperties: false,
          required: ["email"],
          properties: {
            email: {type: "string", format: "email"},
            name: {type: "string"}
          }
        )

        def call(arguments:, context:)
          sa = context.team.sender_addresses.create!(arguments.slice("email", "name"))
          ses_check = run_identity_check(sa)
          {sender_address: serialize_sender_address(sa.reload), ses_check: ses_check}
        end

        private

        def run_identity_check(sa)
          Ses::IdentityChecker.new(sender_address: sa).call
          {ok: sa.reload.verified, status: sa.ses_status, message: nil}
        rescue Ses::ClientFor::NotConfigured => e
          {ok: false, status: "unconfigured", message: e.message}
        rescue => e
          {ok: false, status: "error", message: "#{e.class}: #{e.message}"}
        end
      end
    end
  end
end
