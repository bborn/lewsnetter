# Per-team SES sending-domain identity. Phase 1 of the domain-verification
# rework: one domain per team, driven by the email-sending setup wizard.
# The model itself allows multiple rows per team (no uniqueness on team_id)
# so Phase 2 multi-domain support is a UI change, not a schema change.
#
# `dkim_tokens` is the array of three CNAME selectors AWS returns when we
# call SESv2 CreateEmailIdentity for a domain. We turn each one into a
# CNAME the user adds to their DNS — the verification flow polls SES until
# DKIM goes "SUCCESS".
class CreateTeamSesDomains < ActiveRecord::Migration[8.1]
  def change
    create_table :team_ses_domains do |t|
      t.references :team, null: false, foreign_key: true, index: true
      t.string :domain, null: false
      t.string :status, default: "unverified", null: false
      t.string :verification_status   # raw SES enum: PENDING/SUCCESS/FAILED/TEMPORARY_FAILURE/NOT_STARTED
      t.string :dkim_status           # raw SES DKIM enum: PENDING/SUCCESS/FAILED/TEMPORARY_FAILURE/NOT_STARTED
      t.text :dkim_tokens            # JSON-encoded array of 3 selector tokens
      t.datetime :last_checked_at
      t.datetime :last_verification_requested_at
      t.datetime :verified_at
      t.timestamps
    end

    add_index :team_ses_domains, [:team_id, :domain], unique: true
  end
end
