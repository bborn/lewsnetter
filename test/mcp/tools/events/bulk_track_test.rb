# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module Events
      class BulkTrackTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
          @s1 = @team.subscribers.create!(email: "a@ex.com", external_id: "ext-a")
          @s2 = @team.subscribers.create!(email: "b@ex.com", external_id: "ext-b")
        end

        test "tracks multiple events and reports created count" do
          result = BulkTrack.new.invoke(
            arguments: {
              "events" => [
                {"external_subscriber_id" => "ext-a", "name" => "login"},
                {"external_subscriber_id" => "ext-b", "name" => "purchase", "properties" => {"sku" => "X1"}}
              ]
            },
            context: @ctx
          )
          assert_equal 2, result[:created]
          assert_empty result[:errors]
          assert @s1.events.exists?(name: "login")
          assert @s2.events.exists?(name: "purchase")
        end

        test "records error for unknown subscriber without aborting batch" do
          result = BulkTrack.new.invoke(
            arguments: {
              "events" => [
                {"external_subscriber_id" => "ext-a", "name" => "click"},
                {"external_subscriber_id" => "no-such-sub", "name" => "click"},
                {"external_subscriber_id" => "ext-b", "name" => "view"}
              ]
            },
            context: @ctx
          )
          assert_equal 2, result[:created]
          assert_equal 1, result[:errors].length
          assert_equal 1, result[:errors].first[:index]
          assert_match "subscriber not found", result[:errors].first[:error]
          assert @s1.events.exists?(name: "click")
          assert @s2.events.exists?(name: "view")
        end

        test "records validation error for blank name without aborting batch" do
          result = BulkTrack.new.invoke(
            arguments: {
              "events" => [
                {"external_subscriber_id" => "ext-a", "name" => ""},
                {"external_subscriber_id" => "ext-b", "name" => "view"}
              ]
            },
            context: @ctx
          )
          assert_equal 1, result[:created]
          assert_equal 1, result[:errors].length
          assert_equal 0, result[:errors].first[:index]
        end

        test "events are scoped to calling team only" do
          other_team = create(:team)
          BulkTrack.new.invoke(
            arguments: {
              "events" => [
                {"external_subscriber_id" => "ext-a", "name" => "login"}
              ]
            },
            context: @ctx
          )
          assert_equal 0, other_team.events.count
          assert_equal 1, @team.events.count
        end

        test "accepts explicit occurred_at" do
          ts = "2024-06-01T08:00:00Z"
          result = BulkTrack.new.invoke(
            arguments: {
              "events" => [
                {"external_subscriber_id" => "ext-a", "name" => "signup", "occurred_at" => ts}
              ]
            },
            context: @ctx
          )
          assert_equal 1, result[:created]
          event = @s1.events.find_by!(name: "signup")
          assert_equal Time.parse(ts).utc, event.occurred_at.utc
        end
      end
    end
  end
end
