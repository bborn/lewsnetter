# Builds an AWS SES v2 (or SNS) client for a given team using that team's
# Team::SesConfiguration. Raises NotConfigured when the team has no SES
# config yet — callers (SesSender, Verifier, SNS webhook) decide whether to
# stub, error out, or surface the failure to the user.
#
# Note: the `encrypted_*` column readers return *decrypted* plaintext at
# read time — Rails 7+ `encrypts` is transparent in Ruby. The column name
# only reminds us that ciphertext is what's on disk.
module Ses
  class ClientFor
    class NotConfigured < StandardError; end

    def self.call(team)
      config = team.ses_configuration
      raise NotConfigured, "Team #{team.id} has no SES configured" unless config&.configured?

      Aws::SESV2::Client.new(
        access_key_id: config.encrypted_access_key_id,
        secret_access_key: config.encrypted_secret_access_key,
        region: config.region
      )
    end

    def self.sns_client_for(team)
      config = team.ses_configuration
      raise NotConfigured, "Team #{team.id} has no SES configured" unless config&.configured?

      Aws::SNS::Client.new(
        access_key_id: config.encrypted_access_key_id,
        secret_access_key: config.encrypted_secret_access_key,
        region: config.region
      )
    end
  end
end
