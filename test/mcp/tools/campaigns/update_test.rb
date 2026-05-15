# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module Campaigns
      class UpdateTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
          @campaign = @team.campaigns.create!(subject: "Original", status: "draft", body_markdown: "Original body")
        end

        test "updates subject" do
          result = Update.new.invoke(
            arguments: {"id" => @campaign.id, "subject" => "Updated Subject"},
            context: @ctx
          )
          assert_equal "Updated Subject", result[:campaign][:subject]
          assert_equal "Updated Subject", @campaign.reload.subject
        end

        test "updates body_markdown" do
          result = Update.new.invoke(
            arguments: {"id" => @campaign.id, "body_markdown" => "New body"},
            context: @ctx
          )
          assert_equal "New body", result[:campaign][:body_markdown]
        end

        test "raises RecordNotFound for campaign on another team" do
          other_team = create(:team)
          other = other_team.campaigns.create!(subject: "Other", status: "draft", body_markdown: "body")
          assert_raises(ActiveRecord::RecordNotFound) do
            Update.new.invoke(arguments: {"id" => other.id, "subject" => "Hacked"}, context: @ctx)
          end
        end

        test "raises RecordInvalid when clearing subject" do
          assert_raises(ActiveRecord::RecordInvalid) do
            Update.new.invoke(arguments: {"id" => @campaign.id, "subject" => ""}, context: @ctx)
          end
        end
      end
    end
  end
end
