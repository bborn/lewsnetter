# Hits AWS SES with the team's credentials to verify they work, fetch the
# send quota, and list verified identities (email addresses + domains that
# the team has set up). Returns a Result struct the controller writes back
# into Team::SesConfiguration.
#
# This is the only place we treat AWS errors as user-facing — a bad key
# returns a Result with status=failed + an error message; we don't bubble
# the AWS exception up to the controller.
module Ses
  class Verifier
    Result = Struct.new(
      :status, :sandbox, :quota_max, :quota_sent, :identities, :error,
      keyword_init: true
    )

    def initialize(team:)
      @team = team
    end

    def call
      ses = Ses::ClientFor.call(@team)
      account = ses.get_account
      # IdentityInfo struct fields: identity_name, identity_type,
      # sending_enabled, verification_status, verification_info. `verified`
      # in our local shape is `sending_enabled` (the boolean SES actually
      # gates send permission with). `verification_status` is the SUCCESS/
      # PENDING/FAILED enum from the verification flow.
      identities = ses.list_email_identities.email_identities.map { |i|
        {
          identity: i.identity_name,
          type: i.identity_type,
          verified: i.sending_enabled,
          verification_status: i.verification_status
        }
      }
      Result.new(
        status: "verified",
        sandbox: account.production_access_enabled == false,
        quota_max: account.send_quota&.max_24_hour_send&.to_i,
        quota_sent: account.send_quota&.sent_last_24_hours&.to_i,
        identities: identities,
        error: nil
      )
    rescue Aws::SESV2::Errors::ServiceError => e
      Result.new(status: "failed", sandbox: nil, quota_max: nil, quota_sent: nil,
        identities: [], error: e.message)
    rescue Ses::ClientFor::NotConfigured => e
      Result.new(status: "unconfigured", sandbox: nil, quota_max: nil, quota_sent: nil,
        identities: [], error: e.message)
    end
  end
end
