# Drops encryption on Subscriber#name. The model directive is removed in
# the same commit; this migration rewrites every existing row's ciphertext
# value back to plaintext so reads after the directive is gone return the
# right thing.
#
# Rationale: names are low-stakes PII (often public on LinkedIn, resumes,
# bylines) and non-deterministic encryption made LIKE / substring search
# impossible — breaking subscriber search, cmd-K, and any segment that
# wants to filter on name. Email stays deterministic-encrypted; that's
# the actually-sensitive field for spam/phishing exposure.
#
# Migration runs BEFORE the new code starts serving (Kamal's standard
# deploy ordering: db:migrate completes, then app containers boot), so
# there's no window where a user would see ciphertext garbage on screen.
class DecryptSubscriberNames < ActiveRecord::Migration[8.1]
  def up
    encryptor = ActiveRecord::Encryption.encryptor
    conn = Subscriber.connection
    decrypted = 0
    skipped_plaintext = 0

    conn.select_all("SELECT id, name FROM subscribers WHERE name IS NOT NULL AND name != ''").each do |row|
      raw = row["name"]
      plain =
        begin
          encryptor.decrypt(raw)
        rescue ActiveRecord::Encryption::Errors::Decryption,
          ActiveRecord::Encryption::Errors::Encoding
          # Already plaintext (support_unencrypted_data: true rows from
          # before the encryption rollout).
          nil
        end

      if plain.nil?
        skipped_plaintext += 1
        next
      end

      conn.exec_update(
        "UPDATE subscribers SET name = #{conn.quote(plain)} WHERE id = #{row["id"].to_i}"
      )
      decrypted += 1
    end

    say "Decrypted #{decrypted} subscriber name(s); skipped #{skipped_plaintext} already-plaintext."
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "Re-encrypting requires the original cipher; revert via point-in-time restore if needed."
  end
end
