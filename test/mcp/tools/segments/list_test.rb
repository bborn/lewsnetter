# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module Segments
      class ListTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
          @other_team = create(:team)
          @seg1 = @team.segments.create!(name: "Active Users")
          @seg2 = @team.segments.create!(name: "Trial Users")
          @other_seg = @other_team.segments.create!(name: "Other Team Segment")
        end

        test "lists team's segments with correct total" do
          result = List.new.invoke(arguments: {}, context: @ctx)
          ids = result[:segments].map { |h| h[:id] }
          assert_includes ids, @seg1.id
          assert_includes ids, @seg2.id
          refute_includes ids, @other_seg.id
          assert_equal 2, result[:total]
          assert_equal 50, result[:limit]
          assert_equal 0, result[:offset]
        end

        test "other team's segments are not visible" do
          result = List.new.invoke(arguments: {}, context: @ctx)
          ids = result[:segments].map { |h| h[:id] }
          refute_includes ids, @other_seg.id
        end

        test "pagination via limit and offset" do
          result = List.new.invoke(arguments: {"limit" => 1, "offset" => 1}, context: @ctx)
          assert_equal 1, result[:segments].length
          assert_equal 2, result[:total]
          assert_equal 1, result[:limit]
          assert_equal 1, result[:offset]
        end

        test "returns segment fields including predicate" do
          seg = @team.segments.create!(name: "Subscribed", predicate: "subscribers.subscribed = 1")
          result = List.new.invoke(arguments: {}, context: @ctx)
          found = result[:segments].find { |h| h[:id] == seg.id }
          assert_not_nil found
          assert_equal "Subscribed", found[:name]
          assert_equal "subscribers.subscribed = 1", found[:predicate]
        end
      end
    end
  end
end
