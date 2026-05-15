# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module Segments
      class DeleteTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
          @seg = @team.segments.create!(name: "Deletable Segment")
        end

        test "deletes segment and returns deleted:true with id" do
          id = @seg.id
          result = Delete.new.invoke(arguments: {"id" => id}, context: @ctx)
          assert_equal true, result[:deleted]
          assert_equal id, result[:id]
          refute @team.segments.exists?(id)
        end

        test "raises RecordNotFound for segment on another team" do
          other_team = create(:team)
          other_seg = other_team.segments.create!(name: "Other")
          assert_raises(ActiveRecord::RecordNotFound) do
            Delete.new.invoke(arguments: {"id" => other_seg.id}, context: @ctx)
          end
        end

        test "returns error hash when segment has campaigns (restrict_with_error)" do
          @team.campaigns.create!(subject: "Test Campaign", status: "draft", segment: @seg, body_markdown: "Hello world")
          result = Delete.new.invoke(arguments: {"id" => @seg.id}, context: @ctx)
          assert result.key?(:error)
          assert_not_empty result[:error]
          assert @team.segments.exists?(@seg.id)
        end
      end
    end
  end
end
