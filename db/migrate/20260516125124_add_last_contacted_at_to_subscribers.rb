# Adds per-subscriber "last contacted" tracking so segments can filter by
# things like "contacted in the last 7 days" / "never contacted" — the
# Intercom-style timeseries audience filters.
#
# SendCampaignJob bumps these columns once per real (non-test) send. We
# only track the LAST contact + a running counter rather than every send,
# because segmentation almost always wants recency or volume rather than
# full history. If we ever need full history we can add a separate
# `deliveries` table without changing this schema.
#
# No backfill — historical campaigns don't have per-recipient send records.
# From the next deploy forward, the field is accurate; until then, old
# subscribers appear as "never contacted" in the filter, which is the
# correct conservative default.
class AddLastContactedAtToSubscribers < ActiveRecord::Migration[8.1]
  def change
    add_column :subscribers, :last_contacted_at, :datetime
    add_column :subscribers, :times_contacted, :integer, default: 0, null: false
    add_index  :subscribers, :last_contacted_at
  end
end
