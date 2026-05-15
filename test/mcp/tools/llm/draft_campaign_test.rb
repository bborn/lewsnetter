require "test_helper"

module Mcp
  module Tools
    module Llm
      class DraftCampaignTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
          AI::Base.force_stub = true
        end

        teardown { AI::Base.force_stub = false }

        test "returns a draft when called with a brief" do
          result = DraftCampaign.new.invoke(
            arguments: {"brief" => "- launch announcement\n- value to user\n- CTA"},
            context: @ctx
          )
          assert result[:draft][:subject_candidates].is_a?(Array)
          assert_equal 5, result[:draft][:subject_candidates].size
          assert result[:draft][:markdown_body].present?
          assert result[:draft][:stub], "should be flagged as stub-mode draft"
        end

        test "accepts optional segment_id" do
          seg = @team.segments.create!(name: "Pros", natural_language_source: "pro plan users")
          result = DraftCampaign.new.invoke(
            arguments: {"brief" => "x", "segment_id" => seg.id},
            context: @ctx
          )
          assert result[:draft][:markdown_body].present?
        end

        test "returns 'not configured' shape when stub_mode? is forced AND configured? checked separately" do
          # When we want to test the not-configured path explicitly:
          original = ::Llm::Configuration.singleton_class.instance_method(:current)
          ::Llm::Configuration.singleton_class.define_method(:current) { ::Llm::Configuration.new(credentials: {}, env: {}) }
          AI::Base.force_stub = false  # let the real path run
          begin
            result = DraftCampaign.new.invoke(arguments: {"brief" => "x"}, context: @ctx)
            assert_equal false, result[:configured]
            assert_match(/not configured/i, result[:error])
          ensure
            ::Llm::Configuration.singleton_class.define_method(:current, original)
          end
        end

        test "raises ArgumentError when brief is missing" do
          assert_raises(::Mcp::Tool::ArgumentError) do
            DraftCampaign.new.invoke(arguments: {}, context: @ctx)
          end
        end
      end
    end
  end
end
