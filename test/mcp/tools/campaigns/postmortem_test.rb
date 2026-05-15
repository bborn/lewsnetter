# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module Campaigns
      class PostmortemTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
          @campaign = @team.campaigns.create!(
            subject: "Sent Campaign",
            status: "sent",
            body_markdown: "Hello",
            sent_at: 1.day.ago
          )
        end

        test "returns stats hash with all six counters" do
          result = Postmortem.new.invoke(arguments: {"id" => @campaign.id}, context: @ctx)
          assert result.key?(:stats)
          assert result[:stats].key?(:sent)
          assert result[:stats].key?(:opened)
          assert result[:stats].key?(:clicked)
          assert result[:stats].key?(:bounced)
          assert result[:stats].key?(:complained)
          assert result[:stats].key?(:unsubscribed)
        end

        test "reads sent count from campaign.stats" do
          @campaign.update_column(:stats, {"sent" => 42, "failed" => 1})
          result = Postmortem.new.invoke(arguments: {"id" => @campaign.id}, context: @ctx)
          assert_equal 42, result[:stats][:sent]
        end

        test "returns analyzed_at as ISO8601 string" do
          result = Postmortem.new.invoke(arguments: {"id" => @campaign.id}, context: @ctx)
          assert_match(/\d{4}-\d{2}-\d{2}T/, result[:analyzed_at])
        end

        test "returns top_links array" do
          result = Postmortem.new.invoke(arguments: {"id" => @campaign.id}, context: @ctx)
          assert result.key?(:top_links)
          assert result[:top_links].is_a?(Array)
        end

        test "raises RecordNotFound for campaign on another team" do
          other_team = create(:team)
          other = other_team.campaigns.create!(subject: "Other", status: "sent", body_markdown: "body")
          assert_raises(ActiveRecord::RecordNotFound) do
            Postmortem.new.invoke(arguments: {"id" => other.id}, context: @ctx)
          end
        end
      end
    end
  end
end
