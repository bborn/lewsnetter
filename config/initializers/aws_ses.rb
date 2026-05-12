# Builds the AWS SES v2 client used by SesSender. Reads credentials from
# Rails.application.credentials.aws (preferred) or falls back to ENV.
#
# In development, if no credentials are configured, we don't crash — we set
# Rails.application.config.ses_client = :stub so SesSender knows to log
# instead of actually calling the API.
require "aws-sdk-sesv2"

Rails.application.config.to_prepare do
  creds = Rails.application.credentials.aws || {}
  region = creds[:region] || ENV["AWS_REGION"] || ENV["AWS_DEFAULT_REGION"]
  access_key_id = creds[:access_key_id] || ENV["AWS_ACCESS_KEY_ID"]
  secret_access_key = creds[:secret_access_key] || ENV["AWS_SECRET_ACCESS_KEY"]

  if region.present? && access_key_id.present? && secret_access_key.present?
    Rails.application.config.ses_client = Aws::SESV2::Client.new(
      region: region,
      access_key_id: access_key_id,
      secret_access_key: secret_access_key
    )
  else
    if Rails.env.development? || Rails.env.test?
      Rails.application.config.ses_client = :stub
      Rails.logger.info("[SES] No AWS credentials configured — running in stub mode (#{Rails.env}).")
    else
      Rails.application.config.ses_client = :stub
      Rails.logger.warn("[SES] AWS credentials missing in #{Rails.env}; SesSender will operate in stub mode until configured.")
    end
  end
end
