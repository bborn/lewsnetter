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

    test "stub mode returns five subject candidates and a markdown body" do
      draft = AI::CampaignDrafter.new(
        team: @team,
        brief: "- launch\n- value\n- cta"
      ).call

      assert draft.stub?
      assert draft.success?
      assert_equal 5, draft.subject_candidates.size
      assert(draft.subject_candidates.all? { |c| c.subject.present? && c.rationale.present? })
      assert_match(/Acme Co/, draft.primary_subject)
      # Primary output is markdown — H2 headings, no MJML/HTML tags.
      assert_match(/^##\s/m, draft.markdown_body)
      assert_match(/Acme Co/, draft.markdown_body)
      refute_match(/<mjml/, draft.markdown_body)
      refute_match(/<mj-/, draft.markdown_body)
      # mjml_body fallback still populated for legacy callers.
      assert_match(/<mjml/, draft.mjml_body)
      assert_match(/<\/mjml>/, draft.mjml_body)
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

    test "the LLM path asks for the draft schema and builds the draft from the answer" do
      answer = {
        "subject_candidates" => [
          {"subject" => "Spring is here", "rationale" => "Seasonal"},
          {"subject" => " ", "rationale" => "blank subjects are dropped"}
        ],
        "preheader" => "New things",
        "markdown_body" => "## Hi\n\nBody",
        "suggested_send_time" => "Monday 9am Eastern"
      }
      drafter, calls = drafter_answering(answer)

      draft = drafter.call

      assert_equal AI::CampaignDrafter::DraftSchema, calls.sole[:schema]
      assert_not draft.stub?
      assert draft.success?
      assert_equal ["Spring is here"], draft.subject_candidates.map(&:subject)
      assert_equal "New things", draft.preheader
      assert_equal "## Hi\n\nBody", draft.markdown_body
      assert_match(/<h2>Hi<\/h2>/, draft.mjml_body)
      assert_equal "Monday 9am Eastern", draft.suggested_send_time
    end

    test "the LLM path falls back to the stub draft when the call fails" do
      drafter, _calls = drafter_answering(nil)

      draft = drafter.call

      assert draft.stub?
      assert_equal ["LLM did not return a draft"], draft.errors
    end

    test "the LLM path falls back to the stub draft without a markdown body" do
      drafter, _calls = drafter_answering("subject_candidates" => [], "markdown_body" => "")

      draft = drafter.call

      assert draft.stub?
      assert_equal ["LLM did not return a markdown_body"], draft.errors
    end

    test "the draft schema requires every field and allows no others" do
      schema = AI::CampaignDrafter::DraftSchema.new.to_json_schema

      assert_equal %w[subject_candidates preheader markdown_body suggested_send_time], schema["required"]
      assert_equal false, schema["additionalProperties"]
      assert_equal %w[subject rationale], schema.dig("properties", "subject_candidates", "items", "required")
    end

    test "markdown_to_mjml_fallback wraps markdown HTML in a complete MJML document" do
      drafter = AI::CampaignDrafter.new(team: @team, brief: "x")
      mjml = drafter.send(:markdown_to_mjml_fallback, "## Hello\n\nWorld")
      assert_match(/<mjml/, mjml)
      assert_match(/<\/mjml>/, mjml)
      assert_match(/<mj-body/, mjml)
      assert_match(/<h2/, mjml)
      assert_match(/Hello/, mjml)
    end

    private

    # A drafter in LLM mode whose ask_llm returns +answer+ and records its
    # arguments.
    def drafter_answering(answer)
      calls = []
      drafter = AI::CampaignDrafter.new(team: @team, brief: "- launch")
      drafter.define_singleton_method(:stub_mode?) { false }
      drafter.define_singleton_method(:ask_llm) { |**kwargs| (calls << kwargs) && answer }
      [drafter, calls]
    end
  end
end
