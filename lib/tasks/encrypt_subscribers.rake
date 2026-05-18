# Re-saves Subscriber rows so plaintext email values are rewritten
# through Rails' ActiveRecord Encryption pipeline. Idempotent —
# running twice does no harm (encrypting already-encrypted ciphertext
# is a no-op via Rails' transparent decrypt-then-encrypt).
#
# Runs on every deploy via bin/docker-entrypoint so a fresh deploy never
# leaves PII unencrypted at rest.
#
# History: email + name used to be encrypted, but the May-18-2026
# DecryptSubscriberNames migration moved name to plaintext (LIKE search
# was impossible against non-deterministic ciphertext). Only email is
# encrypted now, and we use a fast SQL-level pre-check to skip the
# whole iteration when every row is already encrypted — without that,
# the per-row decrypt-and-save round-trip exceeded kamal-proxy's 30s
# health-check window on a 10k-row table.
#
# Usage: bin/rails subscribers:encrypt_at_rest
namespace :subscribers do
  desc "Backfill ActiveRecord encryption on subscriber email"
  task encrypt_at_rest: :environment do
    conn = Subscriber.connection
    started = Time.current

    # Fast path: count plaintext rows via SQL. Encrypted values are JSON
    # envelopes that start with `{"p":` — anything else (or NULL/blank)
    # is plaintext or empty. This single query is O(table-scan) but
    # in-engine and ~50ms even on 100k rows.
    pending = conn.select_value(
      "SELECT COUNT(*) FROM subscribers " \
      "WHERE email IS NOT NULL AND email != '' AND email NOT LIKE '{\"p\":%'"
    )

    if pending.to_i.zero?
      puts "[encrypt_at_rest] all subscriber emails already encrypted; skipping"
      next
    end

    puts "[encrypt_at_rest] scanning #{Subscriber.count} subscribers (#{pending} need upgrade)…"
    upgraded = 0

    Subscriber.find_each(batch_size: 500) do |s|
      raw_email = conn.select_value(
        "SELECT email FROM subscribers WHERE id = #{s.id.to_i}"
      )
      next if raw_email.blank? || raw_email.start_with?('{"p":')

      # Rails 7.1+ ships `record.encrypt` for exactly this use case.
      s.encrypt
      upgraded += 1
    end

    elapsed = (Time.current - started).round(1)
    puts "[encrypt_at_rest] done in #{elapsed}s: #{upgraded} upgraded"
  end
end
