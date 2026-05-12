require "test_helper"

module AI
  class CampaignDrafterTest < ActiveSupport::TestCase
    setup do
      @team = create(:team, name: "Acme Co")
      AI::Base.force_stub = true
    end

    teardown do
      AI::Base.force_stub = false
    end

    test "stub mode returns five subject candidates and a valid MJML body" do
      draft = AI::CampaignDrafter.new(
        team: @team,
        brief: "- launch\n- value\n- cta"
      ).call

      assert draft.stub?
      assert draft.success?
      assert_equal 5, draft.subject_candidates.size
      assert(draft.subject_candidates.all? { |c| c.subject.present? && c.rationale.present? })
      assert_match(/Acme Co/, draft.primary_subject)
      assert_match(/<mjml/, draft.mjml_body)
      assert_match(/<\/mjml>/, draft.mjml_body)
      assert_match(/<mj-body/, draft.mjml_body)
      assert_match(/Acme Co/, draft.mjml_body)
      assert_equal "Tuesday 10am Eastern", draft.suggested_send_time
      assert_equal [], draft.errors
    end

    test "stub mode is used when brief is blank" do
      draft = AI::CampaignDrafter.new(team: @team, brief: "").call
      assert draft.stub?
      assert draft.success?
    end

    test "Draft#primary_subject returns first candidate's subject" do
      draft = AI::CampaignDrafter.new(team: @team, brief: "anything").call
      assert_equal draft.subject_candidates.first.subject, draft.primary_subject
    end

    test "tone and segment are accepted without error" do
      segment = @team.segments.create!(name: "Pros", natural_language_source: "pro plan users")
      draft = AI::CampaignDrafter.new(
        team: @team, brief: "something", segment: segment, tone: "playful"
      ).call
      assert draft.success?
    end

    test "valid_mjml? rejects non-MJML content" do
      drafter = AI::CampaignDrafter.new(team: @team, brief: "x")
      refute drafter.send(:valid_mjml?, "<html><body>hi</body></html>")
      refute drafter.send(:valid_mjml?, "")
      assert drafter.send(:valid_mjml?, "<mjml><mj-body><mj-section></mj-section></mj-body></mjml>")
    end
  end
end
