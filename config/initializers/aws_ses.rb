# Per-tenant SES is configured via Team::SesConfiguration. Each team brings
# their own AWS credentials and SNS topics. See app/services/ses/client_for.rb
# for the per-team client factory. This initializer only ensures the SDKs
# are loaded and that the global stub-override hook is defined.
#
# `Rails.application.config.ses_client` is consulted by SesSender as an
# override knob for tests — setting it to `:stub` forces stub mode for every
# send, regardless of per-team config. Unset (`nil`) means SesSender routes
# through `Ses::ClientFor.call(team)` for each campaign; teams that haven't
# configured SES still fall through to stub mode at the per-team layer.
require "aws-sdk-sesv2"
require "aws-sdk-sns"

Rails.application.config.ses_client = nil
