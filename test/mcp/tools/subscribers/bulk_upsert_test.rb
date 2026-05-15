# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module Subscribers
      class BulkUpsertTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
        end

        test "creates new subscribers and reports created count" do
          result = BulkUpsert.new.invoke(
            arguments: {
              "records" => [
                {"email" => "a@ex.com", "external_id" => "eid-a"},
                {"email" => "b@ex.com", "external_id" => "eid-b"}
              ]
            },
            context: @ctx
          )
          assert_equal 2, result[:created]
          assert_equal 0, result[:updated]
          assert_empty result[:errors]
          assert @team.subscribers.exists?(email: "a@ex.com")
          assert @team.subscribers.exists?(email: "b@ex.com")
        end

        test "upserts existing subscribers by external_id and reports updated count" do
          existing = @team.subscribers.create!(email: "orig@ex.com", external_id: "eid-x")
          result = BulkUpsert.new.invoke(
            arguments: {
              "records" => [
                {"email" => "updated@ex.com", "external_id" => "eid-x"},
                {"email" => "brand-new@ex.com"}
              ]
            },
            context: @ctx
          )
          assert_equal 1, result[:created]
          assert_equal 1, result[:updated]
          assert_empty result[:errors]
          assert_equal "updated@ex.com", existing.reload.email
        end

        test "records per-record errors without aborting the batch" do
          result = BulkUpsert.new.invoke(
            arguments: {
              "records" => [
                {"email" => "good@ex.com"},
                {"email" => ""},  # invalid — email blank
                {"email" => "also-good@ex.com"}
              ]
            },
            context: @ctx
          )
          assert_equal 2, result[:created]
          assert_equal 0, result[:updated]
          assert_equal 1, result[:errors].length
          assert_equal 1, result[:errors].first[:index]
          assert result[:errors].first[:error].present?
        end

        test "only creates records scoped to calling team" do
          other_team = create(:team)
          BulkUpsert.new.invoke(
            arguments: {"records" => [{"email" => "x@ex.com", "external_id" => "shared"}]},
            context: @ctx
          )
          assert_equal 0, other_team.subscribers.count
          assert_equal 1, @team.subscribers.count
        end
      end
    end
  end
end
