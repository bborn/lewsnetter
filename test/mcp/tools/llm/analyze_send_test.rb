require "test_helper"

module Mcp
  module Tools
    module Llm
      class AnalyzeSendTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
          @campaign = @team.campaigns.create!(
            subject: "Big launch email",
            preheader: "Something exciting",
            body_mjml: "<mjml><mj-body><mj-section><mj-column><mj-text>Content</mj-text></mj-column></mj-section></mj-body></mjml>",
            status: "sent",
            sent_at: 1.day.ago,
            stats: {"sent" => 500, "opens" => 150, "clicks" => 30, "bounces" => 5, "complaints" => 1}
          )
          AI::Base.force_stub = true
        end

        teardown { AI::Base.force_stub = false }

        test "returns markdown analysis in stub mode" do
          result = AnalyzeSend.new.invoke(
            arguments: {"campaign_id" => @campaign.id},
            context: @ctx
          )
          assert_equal true, result[:configured]
          assert_equal @campaign.id, result[:campaign_id]
          assert result[:markdown].present?
          assert_match(/## What worked/, result[:markdown])
          assert_match(/## What didn't/, result[:markdown])
          assert_match(/## What to try next/, result[:markdown])
        end

        test "raises RecordNotFound when campaign belongs to another team" do
          other_team = create(:team)
          other_campaign = other_team.campaigns.create!(
            subject: "Other team",
            body_mjml: "<mjml><mj-body></mj-body></mjml>",
            status: "sent",
            sent_at: 1.day.ago,
            stats: {}
          )
          assert_raises(ActiveRecord::RecordNotFound) do
            AnalyzeSend.new.invoke(
              arguments: {"campaign_id" => other_campaign.id},
              context: @ctx
            )
          end
        end

        test "returns 'not configured' shape when LLM is not configured" do
          original = ::Llm::Configuration.singleton_class.instance_method(:current)
          ::Llm::Configuration.singleton_class.define_method(:current) { ::Llm::Configuration.new(credentials: {}, env: {}) }
          AI::Base.force_stub = false
          begin
            result = AnalyzeSend.new.invoke(
              arguments: {"campaign_id" => @campaign.id},
              context: @ctx
            )
            assert_equal false, result[:configured]
            assert_match(/not configured/i, result[:error])
          ensure
            ::Llm::Configuration.singleton_class.define_method(:current, original)
          end
        end

        test "raises ArgumentError when campaign_id is missing" do
          assert_raises(::Mcp::Tool::ArgumentError) do
            AnalyzeSend.new.invoke(arguments: {}, context: @ctx)
          end
        end
      end
    end
  end
end
