# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module Segments
      class GetTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
          @seg = @team.segments.create!(name: "Test Segment", predicate: "subscribers.subscribed = 1")
        end

        test "returns segment for valid id" do
          result = Get.new.invoke(arguments: {"id" => @seg.id}, context: @ctx)
          assert_equal @seg.id, result[:segment][:id]
          assert_equal "Test Segment", result[:segment][:name]
          assert_equal "subscribers.subscribed = 1", result[:segment][:predicate]
        end

        test "raises RecordNotFound for segment belonging to another team" do
          other_team = create(:team)
          other_seg = other_team.segments.create!(name: "Other Segment")
          assert_raises(ActiveRecord::RecordNotFound) do
            Get.new.invoke(arguments: {"id" => other_seg.id}, context: @ctx)
          end
        end

        test "raises RecordNotFound for nonexistent id" do
          assert_raises(ActiveRecord::RecordNotFound) do
            Get.new.invoke(arguments: {"id" => 999_999_999}, context: @ctx)
          end
        end
      end
    end
  end
end
