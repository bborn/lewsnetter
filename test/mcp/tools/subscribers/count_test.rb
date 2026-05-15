# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module Subscribers
      class CountTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
          @other_team = create(:team)
          @team.subscribers.create!(email: "a@ex.com", subscribed: true)
          @team.subscribers.create!(email: "b@ex.com", subscribed: true)
          @team.subscribers.create!(email: "c@ex.com", subscribed: false)
          @other_team.subscribers.create!(email: "d@ex.com", subscribed: true)
        end

        test "returns total count of team's subscribers" do
          result = Count.new.invoke(arguments: {}, context: @ctx)
          assert_equal 3, result[:count]
        end

        test "filters by subscribed:true" do
          result = Count.new.invoke(arguments: {"subscribed" => true}, context: @ctx)
          assert_equal 2, result[:count]
        end

        test "filters by subscribed:false" do
          result = Count.new.invoke(arguments: {"subscribed" => false}, context: @ctx)
          assert_equal 1, result[:count]
        end

        test "does not count other team's subscribers" do
          result = Count.new.invoke(arguments: {}, context: @ctx)
          # other team has 1 subscriber, but our team only has 3
          assert_equal 3, result[:count]
        end
      end
    end
  end
end
