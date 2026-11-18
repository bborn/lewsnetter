# Before this release, test sends ("Send test to me", "Send as", MCP
# campaigns_send_test) passed an unsaved stand-in Subscriber to SesSender,
# whose Delivery.create! autosaved it. Each one left a subscribed row with
# the author's email (external_id "test-<user id>", "mcp-test-<user id>" or
# "preview-as-<subscriber id>") and a Delivery on the campaign. Those rows
# counted in audiences, and with resend safety their deliveries would stop
# the author getting the real send.
#
# Delete them with everything that points at them: deliveries (and those
# deliveries' click/open events), events, sequence enrollments and Mailkick
# subscriptions. Nothing else references subscribers (company is a column
# on the subscriber row). Safe to re-run: a second pass finds nothing.
class DeleteTestSendStandInSubscribers < ActiveRecord::Migration[8.1]
  STAND_IN_EXTERNAL_ID = /\A(?:test|mcp-test|preview-as)-\d+\z/

  def up
    candidates = select_rows(<<~SQL)
      SELECT id, external_id FROM subscribers
      WHERE external_id LIKE 'test-%'
        OR external_id LIKE 'mcp-test-%'
        OR external_id LIKE 'preview-as-%'
    SQL
    ids = candidates.select { |_id, external_id| external_id.to_s.match?(STAND_IN_EXTERNAL_ID) }.map { |id, _| Integer(id) }
    return if ids.empty?

    list = ids.join(",")
    deliveries = "SELECT id FROM deliveries WHERE subscriber_id IN (#{list})"
    say "Deleting #{ids.size} test-send stand-in subscribers " \
      "(#{select_value("SELECT COUNT(*) FROM deliveries WHERE subscriber_id IN (#{list})")} deliveries)"

    execute "DELETE FROM click_events WHERE delivery_id IN (#{deliveries})"
    execute "DELETE FROM open_events WHERE delivery_id IN (#{deliveries})"
    execute "DELETE FROM deliveries WHERE subscriber_id IN (#{list})"
    execute "DELETE FROM events WHERE subscriber_id IN (#{list})"
    execute "DELETE FROM sequence_enrollments WHERE subscriber_id IN (#{list})"
    execute "DELETE FROM mailkick_subscriptions WHERE subscriber_type = 'Subscriber' AND subscriber_id IN (#{list})"
    execute "DELETE FROM subscribers WHERE id IN (#{list})"
  end

  def down
    # Nothing to restore: the rows were test-send artifacts.
  end
end
