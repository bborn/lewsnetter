require "test_helper"

module Mcp
  module Tools
    module Llm
      class TranslateSegmentTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
          # Create some subscribers so the stub result has samples
          @team.subscribers.create!(email: "a@test.com", subscribed: true)
          @team.subscribers.create!(email: "b@test.com", subscribed: true)
          AI::Base.force_stub = true
        end

        teardown { AI::Base.force_stub = false }

        test "returns a result when called with natural_language" do
          result = TranslateSegment.new.invoke(
            arguments: {"natural_language" => "subscribed users on the pro plan"},
            context: @ctx
          )
          assert_equal true, result[:configured]
          assert result[:result][:sql_predicate].present?
          assert result[:result][:human_description].present?
          assert result[:result][:sample_subscribers].is_a?(Array)
          assert_kind_of Integer, result[:result][:estimated_count]
          assert result[:result][:stub], "should be flagged as stub-mode result"
        end

        test "sample_subscribers are serialized as hashes with id key" do
          result = TranslateSegment.new.invoke(
            arguments: {"natural_language" => "anyone subscribed"},
            context: @ctx
          )
          samples = result[:result][:sample_subscribers]
          assert samples.all? { |s| s.key?(:id) || s.key?("id") }, "sample subscribers should be serialized hashes"
        end

        test "returns 'not configured' shape when LLM is not configured" do
          original = ::Llm::Configuration.singleton_class.instance_method(:current)
          ::Llm::Configuration.singleton_class.define_method(:current) { ::Llm::Configuration.new(credentials: {}, env: {}) }
          AI::Base.force_stub = false
          begin
            result = TranslateSegment.new.invoke(arguments: {"natural_language" => "x"}, context: @ctx)
            assert_equal false, result[:configured]
            assert_match(/not configured/i, result[:error])
          ensure
            ::Llm::Configuration.singleton_class.define_method(:current, original)
          end
        end

        test "raises ArgumentError when natural_language is missing" do
          assert_raises(Mcp::Tool::ArgumentError) do
            TranslateSegment.new.invoke(arguments: {}, context: @ctx)
          end
        end
      end
    end
  end
end
