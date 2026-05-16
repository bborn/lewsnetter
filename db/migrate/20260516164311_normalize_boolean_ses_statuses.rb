# One-time data fix: sender_addresses.ses_status was being set to the
# literal strings "true" / "false" because Ses::IdentityChecker read AWS's
# `verified_for_sending_status` (Boolean) instead of `verification_status`
# (String enum). The UI rendered those raw values as "TRUE" / "FALSE"
# instead of the proper status pill.
#
# We rewrite affected rows in place: a "true" row means AWS reported
# verified, so we re-stamp it as "verified" and flip the `verified` bit
# (which the buggy checker had wrong because "true" != "SUCCESS"). A
# "false" row maps to "pending" (the user clicked the link but the bool
# came back false at check time — fresh poll will set it correctly).
class NormalizeBooleanSesStatuses < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE sender_addresses
      SET ses_status = 'verified', verified = 1
      WHERE ses_status = 'true'
    SQL
    execute <<~SQL.squish
      UPDATE sender_addresses
      SET ses_status = 'pending', verified = 0
      WHERE ses_status = 'false'
    SQL
  end

  def down
    # No-op — we can't recover the original boolean shape, nor would we
    # want to (it was always wrong).
  end
end
