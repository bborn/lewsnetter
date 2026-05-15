# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module Campaigns
      class GetTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
          @campaign = @team.campaigns.create!(subject: "Hello World", status: "draft", body_markdown: "Body text")
        end

        test "returns campaign hash for a valid id" do
          result = Get.new.invoke(arguments: {"id" => @campaign.id}, context: @ctx)
          assert_equal @campaign.id, result[:campaign][:id]
          assert_equal "Hello World", result[:campaign][:subject]
          assert_equal "draft", result[:campaign][:status]
        end

        test "raises RecordNotFound for campaign on another team" do
          other_team = create(:team)
          other = other_team.campaigns.create!(subject: "Other", status: "draft", body_markdown: "Body")
          assert_raises(ActiveRecord::RecordNotFound) do
            Get.new.invoke(arguments: {"id" => other.id}, context: @ctx)
          end
        end

        test "raises RecordNotFound for nonexistent id" do
          # Use a positive integer that won't exist (obfuscates_id passes
          # positive integers through directly, so this hits the DB and raises).
          assert_raises(ActiveRecord::RecordNotFound) do
            Get.new.invoke(arguments: {"id" => 999_999_999}, context: @ctx)
          end
        end
      end
    end
  end
end
