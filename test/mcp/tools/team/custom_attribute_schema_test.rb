# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module Team
      class CustomAttributeSchemaTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
        end

        test "returns empty schema and zero sample_size for team with no subscribers" do
          result = CustomAttributeSchema.new.invoke(arguments: {}, context: @ctx)
          assert_equal({}, result[:custom_attributes])
          assert_equal 0, result[:sample_size]
        end

        test "returns observed attribute types for populated team" do
          @team.subscribers.create!(email: "a@ex.com", custom_attributes: {"plan" => "pro", "score" => 10})
          result = CustomAttributeSchema.new.invoke(arguments: {}, context: @ctx)
          assert_equal "string", result[:custom_attributes]["plan"]
          assert_equal "integer", result[:custom_attributes]["score"]
          assert_equal 1, result[:sample_size]
        end

        test "limit argument is forwarded to service" do
          3.times.with_index { |i| @team.subscribers.create!(email: "s#{i}@ex.com", custom_attributes: {"n" => i}) }
          result = CustomAttributeSchema.new.invoke(arguments: {"limit" => 2}, context: @ctx)
          assert_equal 2, result[:sample_size]
        end

        test "only samples team's own subscribers" do
          other_team = create(:team)
          other_team.subscribers.create!(email: "x@other.com", custom_attributes: {"secret" => "value"})
          result = CustomAttributeSchema.new.invoke(arguments: {}, context: @ctx)
          refute result[:custom_attributes].key?("secret")
        end

        test "metadata is wired" do
          assert_equal "team_custom_attribute_schema", CustomAttributeSchema.tool_name
          assert_match(/custom_attributes|schema/i, CustomAttributeSchema.description)
        end
      end
    end
  end
end
