# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tool
    class LoaderTest < ActiveSupport::TestCase
      test "discovers all tool files and returns Base descendants" do
        tools = Loader.load_all
        assert tools.is_a?(Array)
        assert tools.all? { |klass| klass < Mcp::Tool::Base }
        names = tools.map(&:tool_name)
        assert_includes names, "team_get_current"
      end

      test "tool names are unique" do
        names = Loader.load_all.map(&:tool_name)
        duplicates = names.tally.select { |_, count| count > 1 }.keys
        assert_empty duplicates, "Duplicate tool_name(s): #{duplicates.inspect}"
      end
    end
  end
end
