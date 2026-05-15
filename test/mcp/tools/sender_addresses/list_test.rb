# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module SenderAddresses
      class ListTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
          @other_team = create(:team)
          @sa1 = @team.sender_addresses.create!(email: "alice@example.com", name: "Alice")
          @sa2 = @team.sender_addresses.create!(email: "bob@example.com", name: "Bob")
          @other = @other_team.sender_addresses.create!(email: "other@example.com")
        end

        test "returns all sender addresses for the team" do
          result = List.new.invoke(arguments: {}, context: @ctx)
          ids = result[:sender_addresses].map { |h| h[:id] }
          assert_includes ids, @sa1.id
          assert_includes ids, @sa2.id
          assert_equal 2, ids.length
        end

        test "does not return other team's sender addresses" do
          result = List.new.invoke(arguments: {}, context: @ctx)
          ids = result[:sender_addresses].map { |h| h[:id] }
          refute_includes ids, @other.id
        end

        test "returns expected serialized fields" do
          result = List.new.invoke(arguments: {}, context: @ctx)
          entry = result[:sender_addresses].find { |h| h[:id] == @sa1.id }
          assert_equal "alice@example.com", entry[:email]
          assert_equal "Alice", entry[:name]
          assert entry.key?(:verified)
          assert entry.key?(:ses_status)
          assert entry.key?(:created_at)
          assert entry.key?(:updated_at)
        end

        test "returns empty array when team has no sender addresses" do
          empty_user = create(:onboarded_user)
          empty_ctx = Mcp::Tool::Context.new(user: empty_user, team: empty_user.current_team)
          result = List.new.invoke(arguments: {}, context: empty_ctx)
          assert_equal [], result[:sender_addresses]
        end
      end
    end
  end
end
