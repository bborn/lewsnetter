# frozen_string_literal: true

# Queries AWS SES for the verification status of a single email identity and
# writes the result back onto the SenderAddress record (`verified`,
# `ses_status`). Replaces the old user-editable verified/ses_status form
# fields — those are now derived from SES, not from user input.
#
# Stub mode: when the team has no SES configured (Ses::ClientFor::NotConfigured),
# we mark the address as `not_in_ses` so the UI can show a "needs setup"
# state without erroring.
module Ses
  class IdentityChecker
    def initialize(sender_address:)
      @sender_address = sender_address
    end

    def call
      client = Ses::ClientFor.call(@sender_address.team)
      result = client.get_email_identity(email_identity: @sender_address.email)

      status = result.verified_for_sending_status
      @sender_address.update!(
        verified: status.to_s == "SUCCESS",
        ses_status: status.to_s.downcase.presence || "unknown"
      )
    rescue Aws::SESV2::Errors::NotFoundException
      # No explicit email-address identity in SES. Fall back to checking whether
      # the parent domain is a verified identity — SES treats domain verification
      # as covering every address on that domain (DKIM/SPF set up at the apex),
      # so foo@verified-domain.com sends fine without a per-address identity.
      if (domain = @sender_address.email.to_s.split("@", 2).last) && domain_verified?(client, domain)
        @sender_address.update!(verified: true, ses_status: "domain_verified")
      else
        # Neither the address nor its parent domain is verified — UI should
        # prompt the user to add one.
        @sender_address.update!(verified: false, ses_status: "not_in_ses")
      end
    rescue Ses::ClientFor::NotConfigured => e
      Rails.logger.info("[Ses::IdentityChecker] team #{@sender_address.team_id} unconfigured: #{e.message}")
      @sender_address.update!(verified: false, ses_status: "unconfigured")
    rescue Aws::Errors::ServiceError, Aws::SESV2::Errors::ServiceError => e
      Rails.logger.warn("[Ses::IdentityChecker] #{e.class}: #{e.message}")
      @sender_address.update!(verified: false, ses_status: "error")
    rescue => e
      Rails.logger.warn("[Ses::IdentityChecker] unexpected #{e.class}: #{e.message}")
      @sender_address.update!(verified: false, ses_status: "error")
    ensure
      @sender_address
    end

    private

    def domain_verified?(client, domain)
      result = client.get_email_identity(email_identity: domain)
      result.verified_for_sending_status.to_s == "SUCCESS"
    rescue Aws::SESV2::Errors::NotFoundException
      false
    rescue Aws::Errors::ServiceError, Aws::SESV2::Errors::ServiceError => e
      Rails.logger.warn("[Ses::IdentityChecker] domain lookup #{domain} failed: #{e.class}: #{e.message}")
      false
    end
  end
end
