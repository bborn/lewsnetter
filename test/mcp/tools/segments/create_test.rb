# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module Segments
      class CreateTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
        end

        test "creates a segment with name only" do
          result = Create.new.invoke(arguments: {"name" => "All Subscribers"}, context: @ctx)
          assert_equal "All Subscribers", result[:segment][:name]
          assert_nil result[:segment][:predicate]
          assert @team.segments.exists?(name: "All Subscribers")
        end

        test "creates a segment with predicate and natural_language_source" do
          result = Create.new.invoke(
            arguments: {
              "name" => "Active",
              "predicate" => "subscribers.subscribed = 1",
              "natural_language_source" => "active subscribers"
            },
            context: @ctx
          )
          assert_equal "Active", result[:segment][:name]
          assert_equal "subscribers.subscribed = 1", result[:segment][:predicate]
          assert_equal "active subscribers", result[:segment][:natural_language_source]
        end

        test "segment is scoped to the calling team" do
          other_team = create(:team)
          other_ctx = Mcp::Tool::Context.new(user: create(:onboarded_user), team: other_team)
          Create.new.invoke(arguments: {"name" => "Other Team Segment"}, context: other_ctx)
          refute @team.segments.exists?(name: "Other Team Segment")
        end

        test "raises on missing required name" do
          assert_raises(Mcp::Tool::ArgumentError) do
            Create.new.invoke(arguments: {}, context: @ctx)
          end
        end

        test "propagates validation error when name is blank" do
          assert_raises(ActiveRecord::RecordInvalid) do
            Create.new.invoke(arguments: {"name" => ""}, context: @ctx)
          end
        end
      end
    end
  end
end
