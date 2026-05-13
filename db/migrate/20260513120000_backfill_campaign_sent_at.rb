class BackfillCampaignSentAt < ActiveRecord::Migration[7.2]
  # `sent_at` already exists on `campaigns` (added in the original
  # create_campaigns migration). Backfill the column for campaigns that were
  # marked `status == 'sent'` before the SendCampaignJob started setting it.
  # We use `updated_at` as a best-effort proxy — for those legacy rows it's the
  # closest signal we have for "when did this finish sending".
  def up
    execute(<<~SQL)
      UPDATE campaigns
      SET sent_at = updated_at
      WHERE status = 'sent' AND sent_at IS NULL
    SQL
  end

  def down
    # No-op: we don't want to clobber sent_at on rollback because new sends
    # populate it directly. Backfilled values are indistinguishable from real
    # ones at this point.
  end
end
