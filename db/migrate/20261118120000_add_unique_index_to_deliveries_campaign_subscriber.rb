# One Delivery per subscriber per broadcast campaign, enforced by the
# database. SendCampaignJob skips subscribers who already have a row and
# SesSender treats a unique-index hit as "already handled, don't send", so
# this is what stops a resumed or overlapping send from re-mailing anyone.
#
# Sequence deliveries (sequence_step_id set) are excluded: a step's hidden
# campaign legitimately mails the same subscriber again on re-entry, and a
# failed step send is retried with a new row.
#
# Any existing duplicate broadcast rows are merged first: the row with an
# SES message id wins (lowest id among those, else lowest id overall), the
# others' click/open events move to it, and the extra rows are deleted.
class AddUniqueIndexToDeliveriesCampaignSubscriber < ActiveRecord::Migration[8.1]
  INDEX_NAME = "index_deliveries_one_per_broadcast_subscriber"

  def up
    merge_duplicate_broadcast_deliveries

    add_index :deliveries, [:campaign_id, :subscriber_id],
      unique: true,
      where: "sequence_step_id IS NULL",
      name: INDEX_NAME
  end

  def down
    remove_index :deliveries, name: INDEX_NAME
  end

  private

  def merge_duplicate_broadcast_deliveries
    groups = select_rows(<<~SQL)
      SELECT campaign_id, subscriber_id
      FROM deliveries
      WHERE sequence_step_id IS NULL
      GROUP BY campaign_id, subscriber_id
      HAVING COUNT(*) > 1
    SQL
    return if groups.empty?

    say "Merging #{groups.size} duplicate (campaign_id, subscriber_id) delivery groups"

    groups.each do |campaign_id, subscriber_id|
      ids = select_values(<<~SQL)
        SELECT id FROM deliveries
        WHERE campaign_id = #{Integer(campaign_id)}
          AND subscriber_id = #{Integer(subscriber_id)}
          AND sequence_step_id IS NULL
        ORDER BY (ses_message_id IS NULL), id
      SQL
      keep_id, *drop_ids = ids.map { |id| Integer(id) }
      drop_list = drop_ids.join(",")

      execute "UPDATE click_events SET delivery_id = #{keep_id} WHERE delivery_id IN (#{drop_list})"
      execute "UPDATE open_events SET delivery_id = #{keep_id} WHERE delivery_id IN (#{drop_list})"
      execute "DELETE FROM deliveries WHERE id IN (#{drop_list})"
    end
  end
end
