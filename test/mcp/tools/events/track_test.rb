# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module Events
      class TrackTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
          @sub = @team.subscribers.create!(email: "alice@ex.com", external_id: "ext-alice")
        end

        test "tracks an event with defaults" do
          result = Track.new.invoke(
            arguments: {"external_subscriber_id" => "ext-alice", "name" => "page_view"},
            context: @ctx
          )
          assert_equal "page_view", result[:event][:name]
          assert_equal @sub.id, result[:subscriber_id]
          assert_equal @sub.id, result[:event][:subscriber_id]
          assert_equal({}, result[:event][:properties])
          assert result[:event][:occurred_at].present?
          assert @sub.events.exists?(name: "page_view")
        end

        test "tracks an event with explicit occurred_at and properties" do
          ts = "2025-01-15T12:00:00Z"
          result = Track.new.invoke(
            arguments: {
              "external_subscriber_id" => "ext-alice",
              "name" => "purchase",
              "occurred_at" => ts,
              "properties" => {"amount" => 99}
            },
            context: @ctx
          )
          assert_equal "purchase", result[:event][:name]
          assert_equal ts, result[:event][:occurred_at]
          assert_equal({"amount" => 99}, result[:event][:properties])
        end

        test "scopes subscriber resolution to calling team" do
          # Create another team whose only subscriber has a different external_id
          other_user = create(:onboarded_user)
          other_team = other_user.current_team
          _other_sub = other_team.subscribers.create!(email: "bob@ex.com", external_id: "ext-bob")
          other_ctx = Mcp::Tool::Context.new(user: other_user, team: other_team)

          # ext-alice does not exist on other_team — must raise
          assert_raises(ActiveRecord::RecordNotFound) do
            Track.new.invoke(
              arguments: {"external_subscriber_id" => "ext-alice", "name" => "click"},
              context: other_ctx
            )
          end

          # Confirm that ext-alice on @team resolves fine
          result = Track.new.invoke(
            arguments: {"external_subscriber_id" => "ext-alice", "name" => "click"},
            context: @ctx
          )
          assert_equal @sub.id, result[:subscriber_id]
        end

        test "raises RecordNotFound when external_subscriber_id does not exist on team" do
          assert_raises(ActiveRecord::RecordNotFound) do
            Track.new.invoke(
              arguments: {"external_subscriber_id" => "nonexistent", "name" => "click"},
              context: @ctx
            )
          end
        end

        test "event is scoped to the team" do
          Track.new.invoke(
            arguments: {"external_subscriber_id" => "ext-alice", "name" => "signup"},
            context: @ctx
          )
          assert @team.events.exists?(name: "signup")
        end
      end
    end
  end
end
