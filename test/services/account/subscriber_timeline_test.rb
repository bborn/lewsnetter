# frozen_string_literal: true

require "test_helper"

module Account
  class SubscriberTimelineTest < ActiveSupport::TestCase
    setup do
      @team = create(:team)
      @subscriber = @team.subscribers.create!(
        email: "tl@example.com", external_id: "tl-1", subscribed: true
      )
      # Backdate signup so it doesn't race the test's relative-time
      # delivery + event timestamps (real subscribers exist long before
      # they receive their first campaign).
      @subscriber.update_columns(created_at: 1.year.ago)
    end

    test "empty subscriber returns a single signup entry" do
      entries = Account::SubscriberTimeline.new(subscriber: @subscriber).call

      assert_equal 1, entries.size
      assert_equal "signup", entries.first[:kind]
      assert_equal @subscriber.created_at.to_i, entries.first[:at].to_i
    end

    test "a delivery with opened_at and clicked_at expands to sent + opened + clicked" do
      campaign = make_campaign(subject: "Welcome aboard")
      now = Time.current
      Delivery.create!(
        campaign: campaign,
        subscriber: @subscriber,
        ses_message_id: "msg-1",
        sent_at: now - 10.minutes,
        delivered_at: now - 9.minutes,
        opened_at: now - 5.minutes,
        clicked_at: now - 4.minutes,
        last_clicked_url: "https://example.com/landing",
        status: "delivered"
      )

      kinds = Account::SubscriberTimeline.new(subscriber: @subscriber).call.map { |e| e[:kind] }

      # Newest first: clicked → opened → delivered → sent → signup
      assert_equal %w[clicked opened delivered campaign_sent signup], kinds
    end

    test "multiple campaigns are sorted newest first" do
      older = make_campaign(subject: "Older")
      newer = make_campaign(subject: "Newer")

      Delivery.create!(
        campaign: older, subscriber: @subscriber,
        ses_message_id: "msg-old", sent_at: 2.days.ago, status: "sent"
      )
      Delivery.create!(
        campaign: newer, subscriber: @subscriber,
        ses_message_id: "msg-new", sent_at: 1.hour.ago, status: "sent"
      )

      entries = Account::SubscriberTimeline.new(subscriber: @subscriber).call
      sent_entries = entries.select { |e| e[:kind] == "campaign_sent" }

      assert_equal "Sent: Newer", sent_entries.first[:title]
      assert_equal "Sent: Older", sent_entries.last[:title]
    end

    test "custom events appear in the timeline mixed with delivery events" do
      campaign = make_campaign(subject: "Mixed")
      Delivery.create!(
        campaign: campaign, subscriber: @subscriber,
        ses_message_id: "msg-mix", sent_at: 3.hours.ago, status: "sent"
      )
      @subscriber.events.create!(
        team: @team, name: "viewed_pricing",
        occurred_at: 1.hour.ago, properties: {plan: "pro"}
      )

      entries = Account::SubscriberTimeline.new(subscriber: @subscriber).call
      kinds = entries.map { |e| e[:kind] }

      assert_includes kinds, "custom_event"
      assert_includes kinds, "campaign_sent"
      # Custom event is more recent than the send, so it appears first.
      assert_equal "custom_event", entries.first[:kind]
      assert_equal "viewed_pricing", entries.first[:title]
    end

    test "respects the limit kwarg" do
      campaign = make_campaign(subject: "Limit")
      Delivery.create!(
        campaign: campaign, subscriber: @subscriber,
        ses_message_id: "msg-limit", sent_at: 1.hour.ago,
        opened_at: 50.minutes.ago, clicked_at: 40.minutes.ago, status: "delivered"
      )

      entries = Account::SubscriberTimeline.new(subscriber: @subscriber, limit: 2).call
      assert_equal 2, entries.size
    end

    test "bounce produces a bounced entry with subtype" do
      campaign = make_campaign(subject: "Hard bounce")
      Delivery.create!(
        campaign: campaign, subscriber: @subscriber,
        ses_message_id: "msg-bounce", sent_at: 2.hours.ago,
        bounced_at: 1.hour.ago, bounce_subtype: "Permanent",
        error_message: "User unknown", status: "bounced"
      )

      entries = Account::SubscriberTimeline.new(subscriber: @subscriber).call
      bounced = entries.detect { |e| e[:kind] == "bounced" }

      assert_not_nil bounced
      assert_match(/Permanent/, bounced[:title])
      assert_equal "User unknown", bounced[:subtitle]
    end

    private

    def make_campaign(subject:)
      @team.campaigns.create!(
        subject: subject,
        status: "draft",
        body_markdown: "Hello"
      )
    end
  end
end
