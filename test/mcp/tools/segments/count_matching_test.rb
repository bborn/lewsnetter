# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module Segments
      class CountMatchingTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
          @team.subscribers.create!(email: "a@ex.com", subscribed: true)
          @team.subscribers.create!(email: "b@ex.com", subscribed: true)
          @team.subscribers.create!(email: "c@ex.com", subscribed: false)
        end

        test "returns count matching predicate and total subscriber count" do
          seg = @team.segments.create!(name: "Subscribed", predicate: "subscribers.subscribed = 1")
          result = CountMatching.new.invoke(arguments: {"id" => seg.id}, context: @ctx)
          assert_equal seg.id, result[:segment_id]
          assert_equal 2, result[:count]
          assert_equal 3, result[:total_team_subscribers]
          assert_nil result[:predicate_error]
        end

        test "returns full count when segment has no predicate" do
          seg = @team.segments.create!(name: "Everyone")
          result = CountMatching.new.invoke(arguments: {"id" => seg.id}, context: @ctx)
          assert_equal 3, result[:count]
          assert_nil result[:predicate_error]
        end

        test "raises RecordNotFound for segment on another team" do
          other_seg = create(:team).segments.create!(name: "Other")
          assert_raises(ActiveRecord::RecordNotFound) do
            CountMatching.new.invoke(arguments: {"id" => other_seg.id}, context: @ctx)
          end
        end

        test "returns predicate_error for invalid predicate (forbidden token)" do
          seg = @team.segments.create!(name: "Bad Segment")
          # Bypass setter validation by writing to definition directly
          seg.update_column(:definition, {"predicate" => "DROP TABLE subscribers"})
          result = CountMatching.new.invoke(arguments: {"id" => seg.id}, context: @ctx)
          assert_equal seg.id, result[:segment_id]
          assert_equal 0, result[:count]
          assert_not_nil result[:predicate_error]
          assert_match(/forbidden/i, result[:predicate_error])
        end
      end
    end
  end
end
