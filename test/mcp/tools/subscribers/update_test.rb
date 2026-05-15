# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module Subscribers
      class UpdateTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
          @sub = @team.subscribers.create!(email: "orig@ex.com", name: "Original", subscribed: true)
        end

        test "partially updates subscriber fields" do
          result = Update.new.invoke(
            arguments: {"id" => @sub.id, "name" => "Updated", "subscribed" => false},
            context: @ctx
          )
          assert_equal @sub.id, result[:subscriber][:id]
          assert_equal "Updated", result[:subscriber][:name]
          assert_equal false, result[:subscriber][:subscribed]
          # email unchanged
          assert_equal "orig@ex.com", result[:subscriber][:email]
        end

        test "does not allow updating another team's subscriber (raises RecordNotFound)" do
          other_team = create(:team)
          other_sub = other_team.subscribers.create!(email: "other@ex.com")
          assert_raises(ActiveRecord::RecordNotFound) do
            Update.new.invoke(arguments: {"id" => other_sub.id, "name" => "Hacked"}, context: @ctx)
          end
        end

        test "raises RecordNotFound for nonexistent id" do
          assert_raises(ActiveRecord::RecordNotFound) do
            Update.new.invoke(arguments: {"id" => 999_999_999, "name" => "Ghost"}, context: @ctx)
          end
        end
      end
    end
  end
end
