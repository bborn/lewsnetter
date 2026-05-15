# frozen_string_literal: true

module Mcp
  module Tools
    module SenderAddresses
      class Verify < Mcp::Tool::Base
        include Mcp::Tools::Serializers

        tool_name "sender_addresses_verify"
        description "Re-checks AWS SES verification status for a sender address. Optionally sends a verification email via SES first (send_verification_email: true). Raises RecordNotFound if the address does not belong to the calling team."
        arguments_schema(
          type: "object",
          additionalProperties: false,
          required: ["id"],
          properties: {
            id: {type: "integer"},
            send_verification_email: {type: "boolean", default: false}
          }
        )

        def call(arguments:, context:)
          sa = context.team.sender_addresses.find_by!(id: arguments["id"])
          send_email = arguments["send_verification_email"] || false

          verification_triggered = false
          creator_status = nil
          creator_message = nil

          if send_email
            result = Ses::IdentityCreator.new(sender_address: sa).call
            verification_triggered = result.ok?
            creator_status = result.status
            creator_message = result.message
          end

          # Re-pull current SES status regardless of whether we triggered an email
          Ses::IdentityChecker.new(sender_address: sa).call
          sa.reload

          {
            sender_address: serialize_sender_address(sa),
            verification_triggered: verification_triggered,
            status: creator_status || sa.ses_status,
            message: creator_message
          }
        end
      end
    end
  end
end
