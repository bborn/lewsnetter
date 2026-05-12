require "test_helper"

module AI
  class SegmentTranslatorTest < ActiveSupport::TestCase
    setup do
      @team = create(:team)
      @s1 = @team.subscribers.create!(email: "a@example.com", external_id: "seg-a", subscribed: true)
      @s2 = @team.subscribers.create!(email: "b@example.com", external_id: "seg-b", subscribed: true)
      @s3 = @team.subscribers.create!(email: "c@example.com", external_id: "seg-c", subscribed: false)
      AI::Base.force_stub = true
    end

    teardown do
      AI::Base.force_stub = false
    end

    test "stub mode returns canned predicate and matching subscribers" do
      result = AI::SegmentTranslator.new(
        team: @team,
        natural_language: "subscribers on pro plan"
      ).call

      assert result.stub?, "result should be flagged as stub"
      assert_equal "subscribed = true", result.sql_predicate
      assert_match(/stub mode/, result.human_description)
      assert_equal [], result.errors
      assert_equal 2, result.estimated_count
      assert_operator result.sample_subscribers.size, :<=, 5
      assert(result.sample_subscribers.all? { |s| s.subscribed == true })
    end

    test "stub mode is used when natural_language is blank" do
      result = AI::SegmentTranslator.new(team: @team, natural_language: "").call
      assert result.stub?
      assert result.success?
    end

    test "Result#success? requires predicate and no errors" do
      good = AI::SegmentTranslator::Result.new(
        sql_predicate: "subscribed = true", human_description: "ok",
        sample_subscribers: [], estimated_count: 0, errors: [], stub: false
      )
      bad = AI::SegmentTranslator::Result.new(
        sql_predicate: nil, human_description: "x",
        sample_subscribers: [], estimated_count: 0, errors: ["nope"], stub: false
      )
      assert good.success?
      refute bad.success?
    end

    test "validate_predicate rejects forbidden tokens" do
      translator = AI::SegmentTranslator.new(team: @team, natural_language: "x")
      errs = translator.send(:validate_predicate, "subscribed = true; DROP TABLE users")
      assert errs.any? { |e| e.include?("DROP") || e.include?(";") },
        "expected forbidden token error, got #{errs.inspect}"
    end

    test "validate_predicate rejects cross-table references" do
      translator = AI::SegmentTranslator.new(team: @team, natural_language: "x")
      errs = translator.send(:validate_predicate, "events.name = 'foo'")
      assert errs.any? { |e| e.include?("disallowed table") }
    end

    test "validate_predicate accepts a normal subscribers predicate" do
      translator = AI::SegmentTranslator.new(team: @team, natural_language: "x")
      errs = translator.send(:validate_predicate, "subscribed = true AND custom_attributes->>'plan' = 'pro'")
      assert_equal [], errs
    end
  end
end
