# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module Subscribers
      class DeleteTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
          @sub = @team.subscribers.create!(email: "delete_me@ex.com")
        end

        test "deletes subscriber and returns deleted:true with id" do
          sub_id = @sub.id
          result = Delete.new.invoke(arguments: {"id" => sub_id}, context: @ctx)
          assert_equal true, result[:deleted]
          assert_equal sub_id, result[:id]
          refute @team.subscribers.exists?(sub_id)
        end

        test "does not delete another team's subscriber (raises RecordNotFound)" do
          other_team = create(:team)
          other_sub = other_team.subscribers.create!(email: "other@ex.com")
          assert_raises(ActiveRecord::RecordNotFound) do
            Delete.new.invoke(arguments: {"id" => other_sub.id}, context: @ctx)
          end
          assert other_team.subscribers.exists?(other_sub.id)
        end

        test "raises RecordNotFound for nonexistent id" do
          assert_raises(ActiveRecord::RecordNotFound) do
            Delete.new.invoke(arguments: {"id" => 999_999_999}, context: @ctx)
          end
        end
      end
    end
  end
end
