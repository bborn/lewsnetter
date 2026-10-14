require "test_helper"

class ClickEventTest < ActiveSupport::TestCase
  BROWSER_UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0 Safari/537.36"

  setup do
    @team = create(:team)
    sender = @team.sender_addresses.create!(email: "from@example.com", verified: true, ses_status: "verified")
    campaign = @team.campaigns.create!(sender_address: sender, subject: "S", body_markdown: "Hi", status: "sent")
    subscriber = @team.subscribers.create!(email: "reader@example.com", external_id: "ce-1", subscribed: true)
    @delivered_at = Time.zone.parse("2026-10-01 09:00:00")
    @delivery = Delivery.create!(campaign: campaign, subscriber: subscriber, ses_message_id: "ce-msg-1",
      sent_at: @delivered_at - 5.seconds, delivered_at: @delivered_at, status: "delivered")
  end

  def click(at:, url: "https://example.com/a", ua: BROWSER_UA, method: "GET", honeypot: false)
    ClickEvent.record!(delivery: @delivery, url: url, user_agent: ua, ip: "198.51.100.9",
      http_method: method, honeypot: honeypot, at: at)
  end

  test "a browser click an hour after delivery is human" do
    event = click(at: @delivered_at + 1.hour)
    assert_not event.automated
    assert_nil event.automated_reason
  end

  test "a click inside the send-proximity window is too_fast" do
    event = click(at: @delivered_at + 30.seconds)
    assert_equal "too_fast", event.automated_reason
  end

  test "a click just past the send-proximity window is human" do
    event = click(at: @delivered_at + MachineTraffic::CLICK_SEND_PROXIMITY_WINDOW + 1.second)
    assert_not event.automated
  end

  test "timing falls back to sent_at when SES hasn't reported delivery" do
    @delivery.update_columns(delivered_at: nil)
    event = click(at: @delivery.sent_at + 10.seconds)
    assert_equal "too_fast", event.automated_reason
  end

  test "known scanner user agents are automated" do
    [
      "Mozilla/5.0 (compatible; Proofpoint URL Defense)",
      "Microsoft Office/16.0 (Windows NT 10.0; Microsoft Outlook 16.0.17928)",
      "python-requests/2.32.3",
      "curl/8.7.1"
    ].each_with_index do |ua, i|
      event = click(url: "https://example.com/ua-#{i}", ua: ua, at: @delivered_at + (2 + i).hours)
      assert_equal "scanner_user_agent", event.automated_reason, "expected #{ua.inspect} to be a scanner"
    end
  end

  test "HEAD requests and blank user agents are automated" do
    assert_equal "head_request", click(method: "HEAD", at: @delivered_at + 1.hour).automated_reason
    assert_equal "blank_user_agent", click(ua: nil, at: @delivered_at + 2.hours).automated_reason
  end

  test "three distinct links within the fan-out window flag the whole burst, earlier clicks included" do
    start = @delivered_at + 1.hour
    a = click(url: "https://example.com/a", at: start)
    b = click(url: "https://example.com/b", at: start + 2.seconds)
    c = click(url: "https://example.com/c", at: start + 4.seconds)

    assert_equal "link_fanout", c.automated_reason
    assert_equal %w[link_fanout link_fanout], [a.reload.automated_reason, b.reload.automated_reason]
  end

  test "three links a person clicks a minute apart are not fan-out" do
    start = @delivered_at + 1.hour
    click(url: "https://example.com/a", at: start)
    click(url: "https://example.com/b", at: start + 1.minute)
    third = click(url: "https://example.com/c", at: start + 2.minutes)

    assert_not third.automated
    assert_equal 0, @delivery.click_events.automated.count
  end

  test "a honeypot hit is automated and flags clicks inside the burst window" do
    start = @delivered_at + 1.hour
    before = click(at: start)
    hp = click(url: nil, honeypot: true, at: start + 5.seconds)
    after = click(url: "https://example.com/b", at: start + 10.seconds)

    assert_equal "honeypot", hp.automated_reason
    assert_equal "honeypot_burst", before.reload.automated_reason
    assert_equal "honeypot_burst", after.automated_reason
  end

  test "a person clicking after the scanner pass still counts as human" do
    # Scanner: honeypot + links seconds after delivery.
    click(url: nil, honeypot: true, at: @delivered_at + 3.seconds)
    click(url: "https://example.com/a", at: @delivered_at + 4.seconds)
    click(url: "https://example.com/b", at: @delivered_at + 5.seconds)
    # The reader, two hours later.
    human = click(url: "https://example.com/a", at: @delivered_at + 2.hours)

    assert_not human.automated
    assert_equal 1, @delivery.click_events.human.count
    assert_equal 3, @delivery.click_events.automated.count
  end

  test "stops writing rows past the per-delivery cap" do
    with_event_cap(2) do
      click(at: @delivered_at + 1.hour)
      click(at: @delivered_at + 2.hours)
      assert_nil click(at: @delivered_at + 3.hours)
    end
    assert_equal 2, @delivery.click_events.count
  end

  private

  def with_event_cap(value)
    original = MachineTraffic::MAX_EVENTS_PER_DELIVERY
    MachineTraffic.send(:remove_const, :MAX_EVENTS_PER_DELIVERY)
    MachineTraffic.const_set(:MAX_EVENTS_PER_DELIVERY, value)
    yield
  ensure
    MachineTraffic.send(:remove_const, :MAX_EVENTS_PER_DELIVERY)
    MachineTraffic.const_set(:MAX_EVENTS_PER_DELIVERY, original)
  end
end
