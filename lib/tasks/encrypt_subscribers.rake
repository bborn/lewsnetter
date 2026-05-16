# Re-saves every Subscriber row so plaintext email + name values are
# rewritten through Rails' ActiveRecord Encryption pipeline. Idempotent
# — running twice does no harm (encrypting already-encrypted ciphertext
# is a no-op via Rails' transparent decrypt-then-encrypt).
#
# Runs on every deploy via bin/docker-entrypoint so a fresh deploy never
# leaves PII unencrypted at rest. The task is cheap (~30s for 10k rows)
# and bails after the first clean pass when there's nothing to upgrade.
#
# Usage: bin/rails subscribers:encrypt_at_rest
namespace :subscribers do
  desc "Backfill ActiveRecord encryption on subscriber email + name"
  task encrypt_at_rest: :environment do
    total = Subscriber.count
    upgraded = 0
    skipped = 0
    started = Time.current

    puts "[encrypt_at_rest] scanning #{total} subscribers…"

    Subscriber.find_each(batch_size: 500) do |s|
      # Read the raw DB value (not through the AR attribute, which would
      # auto-decrypt). If it doesn't parse as ActiveRecord Encryption JSON
      # then it's still plaintext and needs upgrading.
      raw_email = Subscriber.connection.exec_query(
        "SELECT email, name FROM subscribers WHERE id = #{s.id.to_i}"
      ).rows.first

      if encrypted?(raw_email[0]) && encrypted?(raw_email[1])
        skipped += 1
        next
      end

      # Rails 7.1+ ships `record.encrypt` for exactly this use case —
      # walks all encrypts'd attributes and rewrites them in-place. A
      # plain `s.save` would short-circuit on "value unchanged" and never
      # actually encrypt.
      s.encrypt
      upgraded += 1
    end

    elapsed = (Time.current - started).round(1)
    puts "[encrypt_at_rest] done in #{elapsed}s: #{upgraded} upgraded, #{skipped} already encrypted"
  end

  # ActiveRecord Encryption stores values as JSON like {"p":"...","h":{...}}.
  # A value that parses to that shape is already encrypted; anything else
  # is plaintext (or an empty string).
  def encrypted?(value)
    return true if value.blank?
    return false unless value.start_with?("{")
    JSON.parse(value).is_a?(Hash) && JSON.parse(value).key?("p")
  rescue JSON::ParserError
    false
  end
end
