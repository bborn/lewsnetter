# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module Events
      class ListForSubscriberTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
          @sub = @team.subscribers.create!(email: "alice@ex.com", external_id: "ext-alice")
          @e1 = @sub.events.create!(team: @team, name: "login", occurred_at: 2.hours.ago)
          @e2 = @sub.events.create!(team: @team, name: "purchase", occurred_at: 1.hour.ago)
          @e3 = @sub.events.create!(team: @team, name: "logout", occurred_at: 30.minutes.ago)
        end

        test "lists events for subscriber ordered by occurred_at descending" do
          result = ListForSubscriber.new.invoke(
            arguments: {"subscriber_id" => @sub.id},
            context: @ctx
          )
          assert_equal @sub.id, result[:subscriber_id]
          assert_equal 3, result[:total]
          ids = result[:events].map { |e| e[:id] }
          assert_equal [@e3.id, @e2.id, @e1.id], ids
        end

        test "pagination via limit and offset" do
          result = ListForSubscriber.new.invoke(
            arguments: {"subscriber_id" => @sub.id, "limit" => 2, "offset" => 1},
            context: @ctx
          )
          assert_equal 3, result[:total]
          assert_equal 2, result[:limit]
          assert_equal 1, result[:offset]
          assert_equal 2, result[:events].length
          # offset=1 skips the most recent, so we get e2 then e1
          assert_equal [@e2.id, @e1.id], result[:events].map { |e| e[:id] }
        end

        test "event payload includes expected fields" do
          result = ListForSubscriber.new.invoke(
            arguments: {"subscriber_id" => @sub.id, "limit" => 1},
            context: @ctx
          )
          evt = result[:events].first
          assert evt.key?(:id)
          assert evt.key?(:name)
          assert evt.key?(:subscriber_id)
          assert evt.key?(:properties)
          assert evt.key?(:occurred_at)
          assert evt.key?(:created_at)
        end

        test "raises RecordNotFound for subscriber belonging to another team" do
          other_team = create(:team)
          other_sub = other_team.subscribers.create!(email: "bob@ex.com", external_id: "ext-bob")

          assert_raises(ActiveRecord::RecordNotFound) do
            ListForSubscriber.new.invoke(
              arguments: {"subscriber_id" => other_sub.id},
              context: @ctx
            )
          end
        end

        test "does not include events from other subscribers" do
          other_sub = @team.subscribers.create!(email: "eve@ex.com", external_id: "ext-eve")
          other_sub.events.create!(team: @team, name: "intrusion", occurred_at: Time.current)

          result = ListForSubscriber.new.invoke(
            arguments: {"subscriber_id" => @sub.id},
            context: @ctx
          )
          names = result[:events].map { |e| e[:name] }
          refute_includes names, "intrusion"
          assert_equal 3, result[:total]
        end
      end
    end
  end
end
