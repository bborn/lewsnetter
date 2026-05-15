# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module Campaigns
      class ListTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
          @other_team = create(:team)

          @draft = @team.campaigns.create!(subject: "Draft One", status: "draft", body_markdown: "Hello")
          @sent = @team.campaigns.create!(subject: "Sent One", status: "sent", body_markdown: "Hello")
          @other = @other_team.campaigns.create!(subject: "Other", status: "draft", body_markdown: "Hello")
        end

        test "lists team campaigns with correct total" do
          result = List.new.invoke(arguments: {}, context: @ctx)
          ids = result[:campaigns].map { |h| h[:id] }
          assert_includes ids, @draft.id
          assert_includes ids, @sent.id
          refute_includes ids, @other.id
          assert_equal 2, result[:total]
          assert_equal 50, result[:limit]
          assert_equal 0, result[:offset]
        end

        test "filters by status" do
          result = List.new.invoke(arguments: {"status" => "draft"}, context: @ctx)
          ids = result[:campaigns].map { |h| h[:id] }
          assert_includes ids, @draft.id
          refute_includes ids, @sent.id
          assert_equal 1, result[:total]
        end

        test "pagination via limit and offset" do
          result = List.new.invoke(arguments: {"limit" => 1, "offset" => 1}, context: @ctx)
          assert_equal 1, result[:campaigns].length
          assert_equal 2, result[:total]
          assert_equal 1, result[:limit]
          assert_equal 1, result[:offset]
        end

        test "other team campaigns are not visible" do
          result = List.new.invoke(arguments: {}, context: @ctx)
          ids = result[:campaigns].map { |h| h[:id] }
          refute_includes ids, @other.id
        end
      end
    end
  end
end
