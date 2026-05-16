# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module Subscribers
      class ListTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
          @other_team = create(:team)
          @s1 = @team.subscribers.create!(email: "a@ex.com", external_id: "s1", subscribed: true)
          @s2 = @team.subscribers.create!(email: "b@ex.com", external_id: "s2", subscribed: false)
          @other = @other_team.subscribers.create!(email: "c@ex.com", external_id: "s3")
        end

        test "lists team's subscribers with correct total" do
          result = List.new.invoke(arguments: {"limit" => 50}, context: @ctx)
          ids = result[:subscribers].map { |h| h[:id] }
          assert_includes ids, @s1.id
          assert_includes ids, @s2.id
          refute_includes ids, @other.id
          assert_equal 2, result[:total]
          assert_equal 50, result[:limit]
          assert_equal 0, result[:offset]
        end

        test "subscribed:true filter excludes unsubscribed" do
          result = List.new.invoke(arguments: {"subscribed" => true}, context: @ctx)
          ids = result[:subscribers].map { |h| h[:id] }
          assert_includes ids, @s1.id
          refute_includes ids, @s2.id
          assert_equal 1, result[:total]
        end

        test "query matches exact email" do
          # Email is encrypted-at-rest (deterministic), so the query is an
          # exact-match lookup, not a substring scan. Substring search over
          # email isn't possible without decrypting every row.
          result = List.new.invoke(arguments: {"query" => "a@ex.com"}, context: @ctx)
          assert_equal [@s1.id], result[:subscribers].map { |h| h[:id] }
        end

        test "query matches external_id" do
          result = List.new.invoke(arguments: {"query" => "s2"}, context: @ctx)
          assert_equal [@s2.id], result[:subscribers].map { |h| h[:id] }
        end

        test "pagination via limit and offset" do
          result = List.new.invoke(arguments: {"limit" => 1, "offset" => 1}, context: @ctx)
          assert_equal 1, result[:subscribers].length
          assert_equal 2, result[:total]
          assert_equal 1, result[:limit]
          assert_equal 1, result[:offset]
        end

        test "other team's subscriber is not visible" do
          result = List.new.invoke(arguments: {}, context: @ctx)
          ids = result[:subscribers].map { |h| h[:id] }
          refute_includes ids, @other.id
        end
      end
    end
  end
end
