# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module Subscribers
      class CreateTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
        end

        test "creates a new subscriber and returns upserted:false" do
          result = Create.new.invoke(
            arguments: {"email" => "new@ex.com", "name" => "New Person", "subscribed" => true},
            context: @ctx
          )
          assert_equal false, result[:upserted]
          assert_equal "new@ex.com", result[:subscriber][:email]
          assert_equal "New Person", result[:subscriber][:name]
          assert_equal true, result[:subscriber][:subscribed]
          assert @team.subscribers.exists?(email: "new@ex.com")
        end

        test "upserts when external_id matches existing subscriber (upserted:true)" do
          existing = @team.subscribers.create!(email: "old@ex.com", external_id: "eid-1", subscribed: false)
          result = Create.new.invoke(
            arguments: {"email" => "updated@ex.com", "external_id" => "eid-1", "subscribed" => true},
            context: @ctx
          )
          assert_equal true, result[:upserted]
          assert_equal existing.id, result[:subscriber][:id]
          assert_equal "updated@ex.com", result[:subscriber][:email]
          assert_equal true, result[:subscriber][:subscribed]
        end

        test "creates subscriber scoped to team (other team not affected)" do
          other_team = create(:team)
          other_team.subscribers.create!(email: "other@ex.com", external_id: "shared-eid")
          # Creating with same external_id in our team should create a new record (different team)
          result = Create.new.invoke(
            arguments: {"email" => "ours@ex.com", "external_id" => "shared-eid"},
            context: @ctx
          )
          assert_equal false, result[:upserted]
          assert_equal "ours@ex.com", result[:subscriber][:email]
          assert_equal 1, @team.subscribers.count
        end

        test "raises on missing required email" do
          assert_raises(Mcp::Tool::ArgumentError) do
            Create.new.invoke(arguments: {"name" => "No Email"}, context: @ctx)
          end
        end
      end
    end
  end
end
