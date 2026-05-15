# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module Campaigns
      class DeleteTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
          @campaign = @team.campaigns.create!(subject: "Deletable", status: "draft", body_markdown: "Bye")
        end

        test "deletes campaign and returns deleted:true with id" do
          id = @campaign.id
          result = Delete.new.invoke(arguments: {"id" => id}, context: @ctx)
          assert_equal true, result[:deleted]
          assert_equal id, result[:id]
          refute @team.campaigns.exists?(id)
        end

        test "raises RecordNotFound for campaign on another team" do
          other_team = create(:team)
          other = other_team.campaigns.create!(subject: "Other", status: "draft", body_markdown: "body")
          assert_raises(ActiveRecord::RecordNotFound) do
            Delete.new.invoke(arguments: {"id" => other.id}, context: @ctx)
          end
        end

        test "raises RecordNotFound for nonexistent id" do
          # Use a positive integer that won't exist (obfuscates_id passes
          # positive integers through directly, so this hits the DB and raises).
          assert_raises(ActiveRecord::RecordNotFound) do
            Delete.new.invoke(arguments: {"id" => 999_999_999}, context: @ctx)
          end
        end
      end
    end
  end
end
