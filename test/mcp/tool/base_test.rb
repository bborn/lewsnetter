# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tool
    class BaseTest < ActiveSupport::TestCase
      class FakeTool < Base
        tool_name "fake.do_something"
        description "Test tool"
        arguments_schema(
          type: "object",
          properties: {x: {type: "integer"}},
          required: ["x"]
        )

        def call(arguments:, context:)
          {received: arguments["x"], team_id: context.team.id}
        end
      end

      setup do
        @user = create(:onboarded_user)
        @team = @user.current_team
        @ctx = Context.new(user: @user, team: @team)
      end

      test "subclass exposes tool_name, description, arguments_schema" do
        assert_equal "fake.do_something", FakeTool.tool_name
        assert_equal "Test tool", FakeTool.description
        assert_equal "object", FakeTool.arguments_schema[:type]
      end

      test "#invoke validates arguments against schema and calls" do
        result = FakeTool.new.invoke(arguments: {"x" => 7}, context: @ctx)
        assert_equal({received: 7, team_id: @team.id}, result)
      end

      test "#invoke raises Mcp::Tool::ArgumentError when required field missing" do
        assert_raises(Mcp::Tool::ArgumentError) do
          FakeTool.new.invoke(arguments: {}, context: @ctx)
        end
      end

      test "base #call raises NotImplementedError" do
        assert_raises(NotImplementedError) do
          Base.new.call(arguments: {}, context: @ctx)
        end
      end

      test "Base.descendants accumulates registered subclasses" do
        assert_includes Base.descendants, FakeTool
      end
    end
  end
end
