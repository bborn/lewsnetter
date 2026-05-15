# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module Subscribers
      class FindByExternalIdTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
          @other_team = create(:team)
          @sub = @team.subscribers.create!(email: "alice@ex.com", external_id: "ext-alice")
          @other_sub = @other_team.subscribers.create!(email: "bob@ex.com", external_id: "ext-bob")
        end

        test "finds subscriber by external_id" do
          result = FindByExternalId.new.invoke(arguments: {"external_id" => "ext-alice"}, context: @ctx)
          assert_equal @sub.id, result[:subscriber][:id]
          assert_equal "alice@ex.com", result[:subscriber][:email]
        end

        test "returns null subscriber when external_id not found (no error)" do
          result = FindByExternalId.new.invoke(arguments: {"external_id" => "no-such-id"}, context: @ctx)
          assert_nil result[:subscriber]
        end

        test "does not find subscriber belonging to another team" do
          result = FindByExternalId.new.invoke(arguments: {"external_id" => "ext-bob"}, context: @ctx)
          assert_nil result[:subscriber]
        end
      end
    end
  end
end
