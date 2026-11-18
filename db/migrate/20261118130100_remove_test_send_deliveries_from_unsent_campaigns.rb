# Before this release, test sends ("Send test to me", "Send as", MCP
# campaigns_send_test) passed an unsaved stand-in Subscriber to SesSender,
# whose Delivery.create! autosaved it: each one left a subscribed row with
# the author's email (external_id "test-<user id>", "mcp-test-<user id>" or
# "preview-as-<subscriber id>") and a Delivery on the campaign.
#
# SendCampaignJob now skips anyone with a Delivery for the campaign, and
# anyone sharing that address, so those leftover rows would stop the author
# getting the real send. Remove the test-send Delivery rows from campaigns
# that haven't gone out yet (draft or scheduled). Only rows belonging to
# stand-in subscribers are touched. The one case where such a row could be
# from a real send is a failed campaign redrafted through the API; then the
# author's own address gets that campaign again, and nobody else does.
#
# The stand-in subscriber rows themselves are left alone.
class RemoveTestSendDeliveriesFromUnsentCampaigns < ActiveRecord::Migration[8.1]
  STAND_IN_EXTERNAL_ID = /\A(?:test|mcp-test|preview-as)-\d+\z/

  def up
    candidates = select_rows(<<~SQL)
      SELECT deliveries.id, subscribers.external_id
      FROM deliveries
      INNER JOIN subscribers ON subscribers.id = deliveries.subscriber_id
      INNER JOIN campaigns ON campaigns.id = deliveries.campaign_id
      WHERE campaigns.status IN ('draft', 'scheduled')
        AND deliveries.sequence_step_id IS NULL
        AND (subscribers.external_id LIKE 'test-%'
          OR subscribers.external_id LIKE 'mcp-test-%'
          OR subscribers.external_id LIKE 'preview-as-%')
    SQL

    ids = candidates.select { |_id, external_id| external_id.to_s.match?(STAND_IN_EXTERNAL_ID) }.map { |id, _| Integer(id) }
    return if ids.empty?

    say "Removing #{ids.size} test-send deliveries from unsent campaigns"
    ids.each_slice(500) do |slice|
      list = slice.join(",")
      execute "DELETE FROM click_events WHERE delivery_id IN (#{list})"
      execute "DELETE FROM open_events WHERE delivery_id IN (#{list})"
      execute "DELETE FROM deliveries WHERE id IN (#{list})"
    end
  end

  def down
    # Nothing to restore: the rows were test-send bookkeeping.
  end
end
