# frozen_string_literal: true

# Adds an email identity to AWS SES so the team's user can receive a
# verification email at that address. The user clicks the link, AWS marks
# the identity verified, and Lewsnetter picks that up next time
# Ses::IdentityChecker runs (manually via "Re-check with SES" or
# automatically after some events).
#
# Return shape: a Result struct with :ok (bool), :status (one of "sent",
# "already_exists", "domain_verified", "unconfigured", "error") and
# :message (a human string the controller can flash). The controller
# decides whether to refresh the SenderAddress via IdentityChecker after
# this call returns.
module Ses
  class IdentityCreator
    Result = Struct.new(:ok, :status, :message, keyword_init: true) do
      def ok?
        !!ok
      end
    end

    def initialize(sender_address:)
      @sender_address = sender_address
    end

    def call
      client = Ses::ClientFor.call(@sender_address.team)
      client.create_email_identity(email_identity: @sender_address.email)
      Result.new(
        ok: true,
        status: "sent",
        message: "We asked Amazon SES to send a verification email to #{@sender_address.email}. Click the link in your inbox, then come back here and click Re-check with SES."
      )
    rescue Aws::SESV2::Errors::AlreadyExistsException
      # SES already knows about this address (maybe a previous attempt, or
      # the domain is verified). Treat as success — caller should re-check
      # to pick up the current verified status.
      Result.new(
        ok: true,
        status: "already_exists",
        message: "Amazon SES already knows this address. Re-checking verification status."
      )
    rescue Ses::ClientFor::NotConfigured => e
      Rails.logger.info("[Ses::IdentityCreator] team #{@sender_address.team_id} unconfigured: #{e.message}")
      Result.new(
        ok: false,
        status: "unconfigured",
        message: "Your team's SES credentials aren't configured yet. Set them up under Email Sending first."
      )
    rescue Aws::SESV2::Errors::LimitExceededException => e
      Rails.logger.warn("[Ses::IdentityCreator] limit exceeded: #{e.message}")
      Result.new(
        ok: false,
        status: "error",
        message: "Amazon SES rejected the request — verified-identity limit exceeded."
      )
    rescue Aws::Errors::ServiceError, Aws::SESV2::Errors::ServiceError => e
      Rails.logger.warn("[Ses::IdentityCreator] #{e.class}: #{e.message}")
      Result.new(
        ok: false,
        status: "error",
        message: "Amazon SES error: #{e.message}"
      )
    rescue => e
      Rails.logger.warn("[Ses::IdentityCreator] unexpected #{e.class}: #{e.message}")
      Result.new(
        ok: false,
        status: "error",
        message: "Unexpected error: #{e.message}"
      )
    end
  end
end
