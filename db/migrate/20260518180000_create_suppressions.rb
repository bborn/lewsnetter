class CreateSuppressions < ActiveRecord::Migration[8.1]
  def change
    create_table :suppressions do |t|
      t.references :team, null: false, foreign_key: true, type: :integer

      # Encrypted at rest, same pattern as Subscriber#email. Stored as the
      # ciphertext blob; deterministic encryption means we can still do exact-
      # match lookups via `where(email: q)` for the SesSender skip-list and
      # the SNS auto-add upsert.
      t.string :email, null: false

      # Why this address is on the list: `hard_bounce` / `complaint` /
      # `manual` / `gdpr_request`. Plaintext string — low-stakes, useful for
      # operator debugging on the index page.
      t.string :reason, null: false

      # Optional context. For auto-added rows: the SES bounce/complaint
      # subtype (e.g. "General", "abuse"). For manual rows: the operator
      # user id who added it. Plaintext string.
      t.string :source

      # Free-form operator notes (visible on the index page). Optional.
      t.text :note

      # When the address was added to the list. Defaults to creation time
      # but is set explicitly by `Suppression.suppress` so re-fires of the
      # same SNS event don't bounce the timestamp around.
      t.datetime :suppressed_at, null: false

      t.timestamps
    end

    # Unique per team — one row per (team, email). The encrypted email column
    # is the deterministic ciphertext, so the index works against the same
    # bytes a `where(email: ...)` query produces. No need to lower() since
    # the model normalizes to downcase before encryption.
    add_index :suppressions, [:team_id, :email], unique: true,
      name: "index_suppressions_on_team_id_and_email"
    add_index :suppressions, :suppressed_at
  end
end
