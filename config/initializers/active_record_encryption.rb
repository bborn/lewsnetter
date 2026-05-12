# Active Record Encryption keys.
#
# Rails 7+ `encrypts` (used by Team::SesConfiguration for AWS credentials)
# requires a primary key, deterministic key, and key-derivation salt. In
# production these MUST come from Rails encrypted credentials or env vars —
# leaking these keys would expose every tenant's AWS access key/secret.
#
# Dev/test fallback: we ship a known development key set so a fresh checkout
# works without any setup. NEVER reuse these keys in production. When we set
# up the Hetzner/Kamal deploy we'll generate fresh keys via
# `bin/rails db:encryption:init` and write them to credentials.
DEV_AR_ENCRYPTION_KEYS = {
  primary_key: "AKwB7gwGt9Cey0OMKrOwKqG6h0znY6E4",
  deterministic_key: "mUh08z2ICEro058D1ulGSMOplw7Wm2Xs",
  key_derivation_salt: "vAOB5XiD4juLclEzpDbh9hwRzjNz2bvX"
}.freeze

Rails.application.config.active_record.encryption.tap do |enc|
  creds = Rails.application.credentials.active_record_encryption || {}

  enc.primary_key = creds[:primary_key].presence ||
    ENV["AR_ENCRYPTION_PRIMARY_KEY"].presence ||
    DEV_AR_ENCRYPTION_KEYS[:primary_key]
  enc.deterministic_key = creds[:deterministic_key].presence ||
    ENV["AR_ENCRYPTION_DETERMINISTIC_KEY"].presence ||
    DEV_AR_ENCRYPTION_KEYS[:deterministic_key]
  enc.key_derivation_salt = creds[:key_derivation_salt].presence ||
    ENV["AR_ENCRYPTION_KEY_DERIVATION_SALT"].presence ||
    DEV_AR_ENCRYPTION_KEYS[:key_derivation_salt]
end
