# Backfills ClickEvent / OpenEvent rows for deliveries tracked before those
# tables existed, so Campaign#delivery_stats can report human numbers for
# historic campaigns too.
#
# Historic hits have no user agent, IP or per-click history — only the
# Delivery's first-click / first-open timestamp, click_count and
# last_clicked_url. So classification is TIMING ONLY: a first click within
# MachineTraffic::CLICK_SEND_PROXIMITY_WINDOW (or first open within
# OPEN_SEND_PROXIMITY_WINDOW) of delivered_at / sent_at is automated,
# anything later counts as human. One event is written per delivery (for
# the last clicked URL), so historic human click totals count one click per
# recipient rather than the raw click_count. Rows are marked
# `backfilled: true`.
#
# Idempotent: only deliveries with NO events of that kind are touched, so
# re-running is a no-op. Deliberately not run on boot.
#
# Usage:
#   bin/rails engagement:backfill_events
namespace :engagement do
  desc "Backfill click/open events from legacy Delivery columns (timing-only classification; idempotent)"
  task backfill_events: :environment do
    now = Time.current

    clicks = Delivery.where.not(clicked_at: nil).where.not(id: ClickEvent.select(:delivery_id))
    puts "Backfilling click events for #{clicks.count} deliveries..."
    click_counts = Hash.new(0)
    clicks.find_each(batch_size: 1000) do |delivery|
      automated = MachineTraffic.within_send_window?(delivery, delivery.clicked_at, MachineTraffic::CLICK_SEND_PROXIMITY_WINDOW)
      ClickEvent.insert({
        delivery_id: delivery.id,
        url: delivery.last_clicked_url,
        clicked_at: delivery.clicked_at,
        automated: automated,
        automated_reason: (automated ? "too_fast" : nil),
        backfilled: true,
        created_at: now,
        updated_at: now
      })
      click_counts[automated ? :automated : :human] += 1
    end
    puts "  clicks: #{click_counts[:human]} human, #{click_counts[:automated]} automated"

    opens = Delivery.where.not(opened_at: nil).where.not(id: OpenEvent.select(:delivery_id))
    puts "Backfilling open events for #{opens.count} deliveries..."
    open_counts = Hash.new(0)
    opens.find_each(batch_size: 1000) do |delivery|
      automated = MachineTraffic.within_send_window?(delivery, delivery.opened_at, MachineTraffic::OPEN_SEND_PROXIMITY_WINDOW)
      OpenEvent.insert({
        delivery_id: delivery.id,
        opened_at: delivery.opened_at,
        automated: automated,
        automated_reason: (automated ? "too_fast" : nil),
        backfilled: true,
        created_at: now,
        updated_at: now
      })
      open_counts[automated ? :automated : :human] += 1
    end
    puts "  opens: #{open_counts[:human]} human, #{open_counts[:automated]} automated"
    puts "Done."
  end
end
