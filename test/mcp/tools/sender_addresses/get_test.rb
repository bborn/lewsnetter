# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module SenderAddresses
      class GetTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
          @sa = @team.sender_addresses.create!(email: "sender@example.com", name: "Sender")
        end

        test "returns sender address hash for a valid id" do
          result = Get.new.invoke(arguments: {"id" => @sa.id}, context: @ctx)
          assert_equal @sa.id, result[:sender_address][:id]
          assert_equal "sender@example.com", result[:sender_address][:email]
          assert_equal "Sender", result[:sender_address][:name]
        end

        test "raises RecordNotFound for sender address on another team" do
          other_team = create(:team)
          other = other_team.sender_addresses.create!(email: "other@example.com")
          assert_raises(ActiveRecord::RecordNotFound) do
            Get.new.invoke(arguments: {"id" => other.id}, context: @ctx)
          end
        end

        test "raises RecordNotFound for nonexistent id" do
          assert_raises(ActiveRecord::RecordNotFound) do
            Get.new.invoke(arguments: {"id" => 999_999_999}, context: @ctx)
          end
        end

        test "serialized hash includes expected keys" do
          result = Get.new.invoke(arguments: {"id" => @sa.id}, context: @ctx)
          sa_hash = result[:sender_address]
          %i[id email name verified ses_status created_at updated_at].each do |key|
            assert sa_hash.key?(key), "Expected key #{key} to be present"
          end
        end
      end
    end
  end
end
