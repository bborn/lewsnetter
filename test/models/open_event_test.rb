require "test_helper"

class OpenEventTest < ActiveSupport::TestCase
  setup do
    @team = create(:team)
    sender = @team.sender_addresses.create!(email: "from@example.com", verified: true, ses_status: "verified")
    campaign = @team.campaigns.create!(sender_address: sender, subject: "S", body_markdown: "Hi", status: "sent")
    subscriber = @team.subscribers.create!(email: "reader@example.com", external_id: "oe-1", subscribed: true)
    @delivered_at = Time.zone.parse("2026-10-01 09:00:00")
    @delivery = Delivery.create!(campaign: campaign, subscriber: subscriber, ses_message_id: "oe-msg-1",
      sent_at: @delivered_at, delivered_at: @delivered_at, status: "delivered")
  end

  def open_with(ua, at:, method: "GET")
    OpenEvent.record!(delivery: @delivery, user_agent: ua, ip: "2001:db8:1234:5678::1", http_method: method, at: at)
  end

  test "a mail client fetch well after delivery is human" do
    event = open_with("Mozilla/5.0 (Windows NT 10.0) Thunderbird/128.0", at: @delivered_at + 20.minutes)
    assert_not event.automated
    assert_equal "2001:db8:1234::", event.ip_prefix, "IPv6 must be stored as an anonymized /48"
  end

  test "Apple Mail Privacy Protection's bare UA is automated whenever it arrives" do
    assert_equal "apple_mpp", open_with("Mozilla/5.0", at: @delivered_at + 3.hours).automated_reason
  end

  test "Outlook desktop and Gmail's image proxy count as human opens" do
    outlook = open_with("Microsoft Office/16.0 (Microsoft Outlook 16.0.17928)", at: @delivered_at + 1.hour)
    gmail = open_with("Mozilla/5.0 (Windows NT 5.1; rv:11.0) Gecko Firefox/11.0 (via ggpht.com GoogleImageProxy)", at: @delivered_at + 2.hours)
    assert_not outlook.automated
    assert_not gmail.automated
  end

  test "near-instant opens, scanners, HEAD and blank UAs are automated" do
    assert_equal "too_fast", open_with("Mozilla/5.0 (Macintosh) Thunderbird/128.0", at: @delivered_at + 10.seconds).automated_reason
    assert_equal "scanner_user_agent", open_with("Mimecast-Scanner/1.0", at: @delivered_at + 1.hour).automated_reason
    assert_equal "head_request", open_with("Thunderbird", at: @delivered_at + 1.hour, method: "HEAD").automated_reason
    assert_equal "blank_user_agent", open_with("", at: @delivered_at + 1.hour).automated_reason
  end
end
