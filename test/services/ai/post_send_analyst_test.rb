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
      # Opens/clicks are read from the human tracking events.
      clicker = Delivery.create!(campaign: @campaign, subscriber: subs[0], ses_message_id: "m0", status: "delivered",
        sent_at: 1.hour.ago, delivered_at: 55.minutes.ago, opened_at: 40.minutes.ago, clicked_at: 30.minutes.ago, click_count: 1)
      clicker.open_events.create!(opened_at: 40.minutes.ago, user_agent: "Thunderbird")
      clicker.click_events.create!(url: "https://example.com/", clicked_at: 30.minutes.ago, user_agent: "Firefox")
      opener = Delivery.create!(campaign: @campaign, subscriber: subs[1], ses_message_id: "m1", status: "delivered",
        sent_at: 1.hour.ago, delivered_at: 55.minutes.ago, opened_at: 40.minutes.ago)
      opener.open_events.create!(opened_at: 40.minutes.ago, user_agent: "Thunderbird")
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

    test "the LLM path asks for the analysis schema and adds the section headings" do
      analyst, calls = analyst_answering(
        "what_worked" => "Opens were **50%**.",
        "what_didnt" => "Clicks lagged.",
        "what_to_try_next" => "Test a shorter subject."
      )

      md = analyst.call

      assert_equal AI::PostSendAnalyst::AnalysisSchema, calls.sole[:schema]
      assert_equal <<~MARKDOWN, md
        ## What worked

        Opens were **50%**.

        ## What didn't

        Clicks lagged.

        ## What to try next

        Test a shorter subject.
      MARKDOWN
    end

    test "the LLM path falls back to the stub summary when a section is missing" do
      analyst, _calls = analyst_answering("what_worked" => "Fine.", "what_didnt" => "", "what_to_try_next" => "More.")

      md = analyst.call
      assert_match(/50\.0%/, md)
      refute_match(/Fine\./, md)
    end

    test "the LLM path falls back to the stub summary when the call fails" do
      analyst, _calls = analyst_answering(nil)

      assert_match(/50\.0%/, analyst.call)
    end

    test "the prompt includes the current Markdown campaign copy" do
      @campaign.update!(body_markdown: "## Markdown-only copy", body_mjml: nil)

      assert_includes analysis_prompt, "## Markdown-only copy"
    end

    test "the prompt prefers Markdown and keeps a legacy text fallback" do
      assert_includes analysis_prompt, "Body excerpt:\nHi there"

      @campaign.update!(body_markdown: "Preferred copy")
      prompt = analysis_prompt
      assert_includes prompt, "Body excerpt:\nPreferred copy"
      refute_includes prompt, "Hi there"
    end

    test "the baseline averages prior human rates per campaign and skips nontracking sends" do
      first = historical_campaign("First", sent: 4)
      second = historical_campaign("Second", sent: 2)
      historical_campaign("Empty", sent: 0)
      historical_campaign("Plain", sent: 5, plain_text_only: true)
      subscriber = @campaign.deliveries.first.subscriber

      first_delivery = first.deliveries.create!(subscriber: subscriber, status: "sent", ses_message_id: "history-first")
      first_delivery.click_events.create!(url: "https://example.test/", clicked_at: 1.day.ago, user_agent: "Firefox")
      second_delivery = second.deliveries.create!(subscriber: subscriber, status: "sent", ses_message_id: "history-second")
      second_delivery.open_events.create!(opened_at: 1.day.ago, user_agent: "Thunderbird", automated: true)

      prompt = analysis_prompt
      assert_includes prompt, '"open_rate_pct" => 12.5'
      assert_includes prompt, '"click_rate_pct" => 12.5'
    end

    test "an empty historical sample has no fabricated engagement rates" do
      historical_campaign("Empty", sent: 0)
      historical_campaign("Plain", sent: 5, plain_text_only: true)

      refute_match(/(?:open|click)_rate_pct/, analysis_prompt)
    end

    private

    def historical_campaign(subject, sent:, plain_text_only: false)
      @team.campaigns.create!(
        subject: subject, body_markdown: "Prior copy", plain_text_only: plain_text_only,
        status: "sent", sent_at: 2.days.ago, stats: {"sent" => sent}
      )
    end

    def analysis_prompt
      analyst, calls = analyst_answering(nil)
      analyst.call
      calls.sole.fetch(:user)
    end

    # An analyst in LLM mode whose ask_llm returns +answer+ and records its
    # arguments.
    def analyst_answering(answer)
      calls = []
      analyst = AI::PostSendAnalyst.new(campaign: @campaign)
      analyst.define_singleton_method(:stub_mode?) { false }
      analyst.define_singleton_method(:ask_llm) { |**kwargs| (calls << kwargs) && answer }
      [analyst, calls]
    end
  end
end
