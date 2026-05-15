# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module Campaigns
      class ScheduleTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
          @campaign = @team.campaigns.create!(subject: "Schedule Me", status: "draft", body_markdown: "Hello")
        end

        test "sets status to scheduled and persists scheduled_for" do
          future = 3.days.from_now.iso8601
          result = Schedule.new.invoke(
            arguments: {"id" => @campaign.id, "scheduled_for" => future},
            context: @ctx
          )
          assert result[:scheduled]
          assert_equal "scheduled", result[:campaign][:status]
          assert_equal "scheduled", @campaign.reload.status
          assert_not_nil @campaign.scheduled_for
        end

        test "returns scheduled_for as ISO8601 string" do
          future = "2030-01-15T10:00:00Z"
          result = Schedule.new.invoke(
            arguments: {"id" => @campaign.id, "scheduled_for" => future},
            context: @ctx
          )
          assert_match(/2030-01-15/, result[:scheduled_for])
        end

        test "raises ArgumentError for invalid datetime string" do
          assert_raises(Mcp::Tool::ArgumentError) do
            Schedule.new.invoke(
              arguments: {"id" => @campaign.id, "scheduled_for" => "not-a-date"},
              context: @ctx
            )
          end
        end

        test "raises RecordNotFound for campaign on another team" do
          other_team = create(:team)
          other = other_team.campaigns.create!(subject: "Other", status: "draft", body_markdown: "body")
          assert_raises(ActiveRecord::RecordNotFound) do
            Schedule.new.invoke(
              arguments: {"id" => other.id, "scheduled_for" => 1.day.from_now.iso8601},
              context: @ctx
            )
          end
        end
      end
    end
  end
end
