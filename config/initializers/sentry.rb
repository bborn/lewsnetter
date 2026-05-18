# frozen_string_literal: true

# Sentry error tracking. Only activates when SENTRY_DSN is set, so dev,
# test, and any self-hosted deployment that hasn't wired Sentry just runs
# without it (no init, no overhead, no events). The hosted deployment
# sets SENTRY_DSN via .kamal/secrets + GitHub Actions secrets.
#
# PII posture: send_default_pii is intentionally OFF. Lewsnetter handles
# subscriber emails + names — none of that should ever land in a
# third-party error tracker. We surface enough context to debug (signed-in
# operator email, team id, request path, controller + action) without
# shipping subscriber records.

return unless ENV["SENTRY_DSN"].present?

Sentry.init do |config|
  config.dsn = ENV["SENTRY_DSN"]
  config.breadcrumbs_logger = %i[active_support_logger http_logger]

  # Tag every event with the Rails environment so prod / staging are easy
  # to filter on the Sentry side.
  config.environment = Rails.env

  # Tag with the deployed commit SHA so Sentry can group releases + show
  # which deploy introduced a regression. Kamal injects KAMAL_VERSION
  # (the image tag = commit SHA on our setup); fall back to a generic
  # GIT_COMMIT_SHA if a deployer wires that instead.
  config.release = ENV["KAMAL_VERSION"].presence ||
                   ENV["GIT_COMMIT_SHA"].presence

  # Performance traces — 10% sample in production, off in dev/test.
  config.traces_sample_rate = Rails.env.production? ? 0.1 : 0.0

  # Privacy + safety belt:
  #
  # 1. Never auto-send user IP / request headers / cookies. Add explicit
  #    context via Sentry.set_user / set_extra in code if needed.
  config.send_default_pii = false

  # 2. Extend Sentry's built-in field scrubber with the
  #    Lewsnetter-specific PII surface. Sentry scrubs values whose KEY
  #    matches anything in this list, regardless of where in the payload
  #    they appear (params, extras, breadcrumbs, etc.).
  config.sanitize_fields = %w[
    email name phone address
    encrypted_access_key_id encrypted_secret_access_key
    access_key_id secret_access_key
    stripe_customer_id card cvc
    password password_confirmation current_password
    authorization api_key token access_token refresh_token bearer
    rails_master_key secret_key_base
    dkim_tokens
  ]

  # 3. before_send hook — last-chance filter. Drop health-check routing
  #    noise so the inbox stays signal. Must return either the (possibly
  #    modified) Sentry::Event OR nil to drop. Returning anything else
  #    (e.g. a Hash) silently drops the event AND breaks the SDK.
  config.before_send = lambda do |event, _hint|
    msg = event.respond_to?(:message) ? event.message.to_s : ""
    exception_values =
      begin
        Array(event.exception&.values).map { |v| v.value.to_s }.join(" ")
      rescue
        ""
      end
    return nil if (msg + exception_values).match?(%r{ActionController::RoutingError.*/up\b})
    event
  end

  # Don't capture infrastructure noise — routing 404s, CSRF flaps on
  # webhook endpoints, expected RecordNotFound from CanCanCan.
  config.excluded_exceptions += %w[
    ActionController::RoutingError
    ActionController::InvalidAuthenticityToken
    ActiveRecord::RecordNotFound
    Mcp::DoorkeeperAuth::Unauthorized
  ]
end
