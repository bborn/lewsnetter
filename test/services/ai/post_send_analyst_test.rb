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
        stats: {"sent" => 200, "opens" => 50, "clicks" => 10, "bounces" => 2, "complaints" => 1}
      )
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
      assert_match(/200 recipients/, md)
      # 50/200 = 25.0%
      assert_match(/25\.0%/, md)
      # 10/200 = 5.0%
      assert_match(/5\.0%/, md)
      assert_match(/Stub-mode analysis/, md)
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
