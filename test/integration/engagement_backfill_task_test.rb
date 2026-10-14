require "test_helper"
require "rake"

class EngagementBackfillTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("engagement:backfill_events")
    @task = Rake::Task["engagement:backfill_events"]

    @team = create(:team)
    sender = @team.sender_addresses.create!(email: "from@example.com", verified: true, ses_status: "verified")
    @campaign = @team.campaigns.create!(sender_address: sender, subject: "S", body_markdown: "Hi", status: "sent")
    @delivered_at = 3.days.ago
  end

  def make_delivery(key, **attrs)
    sub = @team.subscribers.create!(email: "#{key}@example.com", external_id: key, subscribed: true)
    Delivery.create!(campaign: @campaign, subscriber: sub, ses_message_id: "bf-#{key}",
      sent_at: @delivered_at, delivered_at: @delivered_at, status: "delivered", **attrs)
  end

  def run_task
    @task.reenable
    capture_io { @task.invoke }
  end

  test "classifies legacy clicks and opens by timing only, and is idempotent" do
    scanned = make_delivery("scanned", opened_at: @delivered_at + 2.seconds,
      clicked_at: @delivered_at + 5.seconds, click_count: 4, last_clicked_url: "https://example.com/a")
    reader = make_delivery("reader", opened_at: @delivered_at + 1.hour,
      clicked_at: @delivered_at + 2.hours, click_count: 2, last_clicked_url: "https://example.com/b")
    make_delivery("idle")

    run_task

    assert_equal "too_fast", scanned.click_events.sole.automated_reason
    assert_equal "too_fast", scanned.open_events.sole.automated_reason
    assert_not reader.click_events.sole.automated
    assert_not reader.open_events.sole.automated
    assert reader.click_events.sole.backfilled
    assert_equal "https://example.com/b", reader.click_events.sole.url

    stats = @campaign.delivery_stats
    assert_equal 1, stats[:clicked]
    assert_equal 1, stats[:clicked_automated]
    assert_equal 1, stats[:opened]

    assert_no_difference -> { ClickEvent.count + OpenEvent.count } do
      run_task
    end
  end
end
