# frozen_string_literal: true

# Registers a sending domain with AWS SES via `CreateEmailIdentity`,
# requesting Easy DKIM (SES generates the key, gives us 3 selector tokens
# to install as CNAMEs). Writes the tokens onto the Team::SesDomain row so
# the wizard's verify step can render them.
#
# Idempotent: if SES already has the identity (someone retried, or another
# team in the same AWS account verified it), we treat AlreadyExists as
# success and fall through to the checker to pick up current state.
#
# Returns a Result struct mirroring Ses::IdentityCreator so the controller
# can use the same shape for success/error branches.
module Ses
  class DomainIdentityCreator
    Result = Struct.new(:ok, :status, :message, :ses_domain, keyword_init: true) do
      def ok? = !!ok
    end

    def initialize(ses_domain:)
      @ses_domain = ses_domain
    end

    def call
      client = Ses::ClientFor.call(@ses_domain.team)
      response = client.create_email_identity(
        email_identity: @ses_domain.domain,
        dkim_signing_attributes: {next_signing_key_length: "RSA_2048_BIT"}
      )
      apply_dkim_attributes(response.dkim_attributes)
      @ses_domain.update!(
        status: "pending",
        last_verification_requested_at: Time.current
      )
      Result.new(
        ok: true,
        status: "pending",
        message: "Add the three CNAME records below to your DNS, then we'll detect verification automatically.",
        ses_domain: @ses_domain
      )
    rescue Aws::SESV2::Errors::AlreadyExistsException
      # The identity already exists in this AWS account. Fall back to a
      # GetEmailIdentity to pull the existing DKIM tokens — that way we
      # can still render CNAMEs to the user.
      hydrate_from_existing_identity(client)
      Result.new(
        ok: true,
        status: @ses_domain.status,
        message: "Amazon SES already knows this domain — current verification status loaded.",
        ses_domain: @ses_domain
      )
    rescue Ses::ClientFor::NotConfigured => e
      Rails.logger.info("[Ses::DomainIdentityCreator] team #{@ses_domain.team_id} unconfigured: #{e.message}")
      Result.new(
        ok: false,
        status: "unconfigured",
        message: "Your team's SES credentials aren't configured yet — finish step 1 of setup first.",
        ses_domain: @ses_domain
      )
    rescue Aws::SESV2::Errors::LimitExceededException => e
      Rails.logger.warn("[Ses::DomainIdentityCreator] limit exceeded: #{e.message}")
      Result.new(
        ok: false,
        status: "error",
        message: "Amazon SES rejected the request — verified-identity limit exceeded.",
        ses_domain: @ses_domain
      )
    rescue Aws::Errors::ServiceError, Aws::SESV2::Errors::ServiceError => e
      Rails.logger.warn("[Ses::DomainIdentityCreator] #{e.class}: #{e.message}")
      Result.new(
        ok: false,
        status: "error",
        message: "Amazon SES error: #{e.message}",
        ses_domain: @ses_domain
      )
    rescue => e
      Rails.logger.warn("[Ses::DomainIdentityCreator] unexpected #{e.class}: #{e.message}")
      Result.new(
        ok: false,
        status: "error",
        message: "Unexpected error: #{e.message}",
        ses_domain: @ses_domain
      )
    end

    private

    def apply_dkim_attributes(dkim)
      return unless dkim
      @ses_domain.dkim_token_list = Array(dkim.tokens)
      @ses_domain.dkim_status = dkim.status.to_s.presence
    end

    def hydrate_from_existing_identity(client)
      identity = client.get_email_identity(email_identity: @ses_domain.domain)
      apply_dkim_attributes(identity.dkim_attributes)
      verification_status = identity.verification_status.to_s
      @ses_domain.update!(
        verification_status: verification_status.presence,
        status: domain_status_from(verification_status, identity.dkim_attributes&.status.to_s),
        last_checked_at: Time.current,
        last_verification_requested_at: @ses_domain.last_verification_requested_at || Time.current,
        verified_at: (verification_status == "SUCCESS") ? Time.current : @ses_domain.verified_at
      )
    rescue Aws::SESV2::Errors::NotFoundException
      # Race: SES reported AlreadyExists then 404'd on read. Treat as pending.
      @ses_domain.update!(status: "pending", last_verification_requested_at: Time.current)
    end

    def domain_status_from(verification_status, dkim_status)
      return "verified" if verification_status == "SUCCESS"
      return "failed"   if verification_status == "FAILED" || dkim_status == "FAILED"
      "pending"
    end
  end
end
