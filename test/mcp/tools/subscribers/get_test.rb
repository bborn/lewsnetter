# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module Subscribers
      class GetTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
          @other_team = create(:team)
          @sub = @team.subscribers.create!(email: "alice@ex.com", external_id: "ext-1", subscribed: true)
          @other_sub = @other_team.subscribers.create!(email: "bob@ex.com")
        end

        test "returns subscriber data for a valid id" do
          result = Get.new.invoke(arguments: {"id" => @sub.id}, context: @ctx)
          assert_equal @sub.id, result[:subscriber][:id]
          assert_equal "alice@ex.com", result[:subscriber][:email]
          assert_equal "ext-1", result[:subscriber][:external_id]
          assert_equal true, result[:subscriber][:subscribed]
        end

        test "other team's subscriber is not accessible (raises RecordNotFound)" do
          assert_raises(ActiveRecord::RecordNotFound) do
            Get.new.invoke(arguments: {"id" => @other_sub.id}, context: @ctx)
          end
        end

        test "missing id raises RecordNotFound" do
          assert_raises(ActiveRecord::RecordNotFound) do
            Get.new.invoke(arguments: {"id" => 999_999_999}, context: @ctx)
          end
        end
      end
    end
  end
end
