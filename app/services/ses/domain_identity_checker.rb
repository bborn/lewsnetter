# frozen_string_literal: true

# Polled by the SES setup wizard's verify step to find out whether the
# user's DNS CNAMEs have propagated and SES has flipped the domain to
# SUCCESS. Writes status back onto the Team::SesDomain row.
#
# On successful verification, ensures the team has a verified
# `SenderAddress` on the domain (defaulting to `noreply@<domain>`) so the
# wizard's test step has a sender to send from without asking the user
# another question.
#
# Never raises — callers (the polling endpoint, future cron jobs) expect a
# Result struct with the updated domain.
module Ses
  class DomainIdentityChecker
    Result = Struct.new(:ok, :state, :ses_domain, :error, keyword_init: true) do
      def ok? = !!ok
    end

    DEFAULT_SENDER_LOCAL_PART = Team::SesDomain::DEFAULT_SENDER_LOCAL_PART

    def initialize(ses_domain:)
      @ses_domain = ses_domain
    end

    def call
      client = Ses::ClientFor.call(@ses_domain.team)
      identity = client.get_email_identity(email_identity: @ses_domain.domain)

      verification_status = identity.verification_status.to_s
      dkim_status = identity.dkim_attributes&.status.to_s
      new_status = domain_status_from(verification_status, dkim_status)

      attrs = {
        verification_status: verification_status.presence,
        dkim_status: dkim_status.presence,
        status: new_status,
        last_checked_at: Time.current
      }
      # Re-store the DKIM tokens if SES returned them — covers re-key flows.
      if identity.dkim_attributes && Array(identity.dkim_attributes.tokens).any?
        attrs[:dkim_tokens] = JSON.dump(Array(identity.dkim_attributes.tokens))
      end
      attrs[:verified_at] = Time.current if new_status == "verified" && @ses_domain.verified_at.blank?

      @ses_domain.update!(attrs)

      @ses_domain.provision_default_sender if @ses_domain.verified?

      Result.new(ok: true, state: new_status, ses_domain: @ses_domain)
    rescue Aws::SESV2::Errors::NotFoundException
      # SES forgot about the identity (likely manually deleted in the AWS
      # console). Surface that distinctly so the UI can prompt the user to
      # re-submit the domain.
      @ses_domain.update!(status: "unverified", verification_status: nil, dkim_status: nil, last_checked_at: Time.current)
      Result.new(ok: true, state: "unverified", ses_domain: @ses_domain)
    rescue Ses::ClientFor::NotConfigured => e
      Rails.logger.info("[Ses::DomainIdentityChecker] team #{@ses_domain.team_id} unconfigured: #{e.message}")
      Result.new(ok: false, state: "unconfigured", ses_domain: @ses_domain, error: e.message)
    rescue Aws::Errors::ServiceError, Aws::SESV2::Errors::ServiceError => e
      Rails.logger.warn("[Ses::DomainIdentityChecker] #{e.class}: #{e.message}")
      Result.new(ok: false, state: "error", ses_domain: @ses_domain, error: e.message)
    rescue => e
      Rails.logger.warn("[Ses::DomainIdentityChecker] unexpected #{e.class}: #{e.message}")
      Result.new(ok: false, state: "error", ses_domain: @ses_domain, error: e.message)
    end

    private

    def domain_status_from(verification_status, dkim_status)
      return "verified" if verification_status == "SUCCESS"
      return "failed" if verification_status == "FAILED" || dkim_status == "FAILED"
      "pending"
    end
  end
end
