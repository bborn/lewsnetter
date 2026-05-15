# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module Segments
      class SampleMatchingTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
          @sub1 = @team.subscribers.create!(email: "a@ex.com", subscribed: true)
          @sub2 = @team.subscribers.create!(email: "b@ex.com", subscribed: true)
          @sub3 = @team.subscribers.create!(email: "c@ex.com", subscribed: false)
        end

        test "returns sample of matching subscribers" do
          seg = @team.segments.create!(name: "Subscribed", predicate: "subscribers.subscribed = 1")
          result = SampleMatching.new.invoke(arguments: {"id" => seg.id}, context: @ctx)
          assert_equal seg.id, result[:segment_id]
          assert_equal 2, result[:total_matching]
          assert_nil result[:predicate_error]
          emails = result[:sample].map { |h| h[:email] }
          assert_includes emails, "a@ex.com"
          assert_includes emails, "b@ex.com"
          refute_includes emails, "c@ex.com"
        end

        test "limit restricts the sample size" do
          seg = @team.segments.create!(name: "All", predicate: "subscribers.subscribed IS NOT NULL")
          result = SampleMatching.new.invoke(arguments: {"id" => seg.id, "limit" => 2}, context: @ctx)
          assert result[:sample].length <= 2
          assert_equal 3, result[:total_matching]
        end

        test "raises RecordNotFound for segment on another team" do
          other_seg = create(:team).segments.create!(name: "Other")
          assert_raises(ActiveRecord::RecordNotFound) do
            SampleMatching.new.invoke(arguments: {"id" => other_seg.id}, context: @ctx)
          end
        end

        test "returns predicate_error for invalid predicate (forbidden token)" do
          seg = @team.segments.create!(name: "Bad Segment")
          seg.update_column(:definition, {"predicate" => "DROP TABLE subscribers"})
          result = SampleMatching.new.invoke(arguments: {"id" => seg.id}, context: @ctx)
          assert_equal seg.id, result[:segment_id]
          assert_equal [], result[:sample]
          assert_equal 0, result[:total_matching]
          assert_not_nil result[:predicate_error]
          assert_match(/forbidden/i, result[:predicate_error])
        end

        test "default limit is 10 when not specified" do
          seg = @team.segments.create!(name: "All No Predicate")
          result = SampleMatching.new.invoke(arguments: {"id" => seg.id}, context: @ctx)
          assert result[:sample].length <= 10
        end
      end
    end
  end
end
