require "test_helper"

module AI
  class PostSendAnalystTest < ActiveSupport::TestCase
    setup do
      @team = create(:team)
      @campaign = @team.campaigns.create!(
        subject: "Hello world",
        preheader: "preview",
        body_mjml: "<mjml><mj-body><mj-section><mj-column><mj-text>Hi there</mj-text></mj-column></mj-section></mj-body></mjml>",
        status: "sent",
        sent_at: 1.day.ago,
        stats: {"sent" => 4}
      )
      # Engagement lives on the per-recipient deliveries, not the stats column:
      # 4 sent/delivered, 2 opened, 1 clicked → 50% open, 25% click.
      subs = 4.times.map do |i|
        @team.subscribers.create!(email: "d#{i}@example.com", external_id: "d-#{i}", subscribed: true)
      end
      Delivery.create!(campaign: @campaign, subscriber: subs[0], ses_message_id: "m0", status: "delivered",
        sent_at: 1.hour.ago, delivered_at: 55.minutes.ago, opened_at: 40.minutes.ago, clicked_at: 30.minutes.ago, click_count: 1)
      Delivery.create!(campaign: @campaign, subscriber: subs[1], ses_message_id: "m1", status: "delivered",
        sent_at: 1.hour.ago, delivered_at: 55.minutes.ago, opened_at: 40.minutes.ago)
      Delivery.create!(campaign: @campaign, subscriber: subs[2], ses_message_id: "m2", status: "delivered",
        sent_at: 1.hour.ago, delivered_at: 55.minutes.ago)
      Delivery.create!(campaign: @campaign, subscriber: subs[3], ses_message_id: "m3", status: "delivered",
        sent_at: 1.hour.ago, delivered_at: 55.minutes.ago)
      AI::Base.force_stub = true
    end

    teardown do
      AI::Base.force_stub = false
    end

    test "stub mode returns three-section markdown that reads campaign stats" do
      md = AI::PostSendAnalyst.new(campaign: @campaign).call

      assert_kind_of String, md
      assert_match(/## What worked/, md)
      assert_match(/## What didn't/, md)
      assert_match(/## What to try next/, md)
      assert_match(/Hello world/, md)
      assert_match(/4 recipients/, md)
      # 2 opened / 4 sent = 50.0%
      assert_match(/50\.0%/, md)
      # 1 clicked / 4 sent = 25.0%
      assert_match(/25\.0%/, md)
      assert_match(/postmortem/i, md)
    end

    test "stub mode handles a campaign with empty stats without raising" do
      empty = @team.campaigns.create!(
        subject: "Empty",
        body_mjml: "<mjml><mj-body></mj-body></mjml>",
        status: "sent",
        sent_at: Time.current,
        stats: {}
      )
      md = AI::PostSendAnalyst.new(campaign: empty).call
      assert_match(/0 recipients/, md)
      assert_match(/0\.0%/, md)
    end

    # Regression for the production 500 on /campaigns/:id/postmortem when the
    # controller's resource loader failed to populate @campaign. The service's
    # `call` already guards with `return stub_markdown unless @campaign`, but
    # `stub_markdown` itself reached through `@campaign.stats` and re-crashed.
    test "stub mode renders without raising when @campaign is nil" do
      md = nil
      assert_nothing_raised do
        md = AI::PostSendAnalyst.new(campaign: nil).call
      end
      assert_match(/## What worked/, md)
      assert_match(/0 recipients/, md)
      assert_match(/\(no subject\)/, md)
    end
  end
end
