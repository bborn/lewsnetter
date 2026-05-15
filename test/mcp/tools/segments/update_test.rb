# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module Segments
      class UpdateTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
          @seg = @team.segments.create!(
            name: "Original Name",
            predicate: "subscribers.subscribed = 1",
            natural_language_source: "active"
          )
        end

        test "updates the name" do
          result = Update.new.invoke(arguments: {"id" => @seg.id, "name" => "New Name"}, context: @ctx)
          assert_equal "New Name", result[:segment][:name]
          assert_equal "subscribers.subscribed = 1", result[:segment][:predicate]
        end

        test "clears predicate when passed empty string" do
          result = Update.new.invoke(arguments: {"id" => @seg.id, "predicate" => ""}, context: @ctx)
          assert_nil result[:segment][:predicate]
          @seg.reload
          assert_nil @seg.predicate
        end

        test "updates predicate to new value" do
          result = Update.new.invoke(
            arguments: {"id" => @seg.id, "predicate" => "subscribers.bounced_at IS NULL"},
            context: @ctx
          )
          assert_equal "subscribers.bounced_at IS NULL", result[:segment][:predicate]
        end

        test "raises RecordNotFound for segment on another team" do
          other_team = create(:team)
          other_seg = other_team.segments.create!(name: "Other")
          assert_raises(ActiveRecord::RecordNotFound) do
            Update.new.invoke(arguments: {"id" => other_seg.id, "name" => "Hack"}, context: @ctx)
          end
        end

        test "partial update leaves untouched fields unchanged" do
          result = Update.new.invoke(arguments: {"id" => @seg.id, "name" => "Renamed"}, context: @ctx)
          assert_equal "Renamed", result[:segment][:name]
          assert_equal "active", result[:segment][:natural_language_source]
        end
      end
    end
  end
end
