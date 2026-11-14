# frozen_string_literal: true

module Chats
  # Bridges Mcp::Tool::Base descendants into RubyLLM::Tool subclasses so the
  # in-app chat (powered by ruby_llm's acts_as_chat) uses the same registry
  # as the MCP server. Each adaptation is per-context: the wrapper class
  # closes over a specific Mcp::Tool::Context so the running chat's user +
  # team scope every tool call.
  module ToolAdapter
    # What Mcp::Server publishes for a tool that declares no arguments.
    EMPTY_ARGUMENTS_SCHEMA = {type: "object", properties: {}}.freeze

    module_function

    def adapt_all(context:)
      Mcp::Tool::Loader.load_all.map { |t| adapt(t, context: context) }
    end

    def adapt(tool_class, context:)
      our_tool = tool_class
      ctx = context

      Class.new(RubyLLM::Tool) do
        description our_tool.description.to_s

        # Hand ruby_llm the tool's JSON Schema as is, so the agent sees what
        # an MCP client gets from tools/list. Rebuilding it with `param` kept
        # only each property's top-level type: arrays of objects became
        # arrays of strings, and unions, enums, and bounds were dropped.
        params(our_tool.arguments_schema || EMPTY_ARGUMENTS_SCHEMA)

        # ruby_llm calls tool_instance.name to get the wire name. Override
        # the instance method so external clients see our snake_case names.
        define_method(:name) { our_tool.tool_name }

        define_method(:execute) do |args = {}|
          string_args = (args || {}).transform_keys(&:to_s)
          our_tool.new.invoke(arguments: string_args, context: ctx)
        rescue ActiveRecord::RecordNotFound => e
          {error: "Not found: #{e.message}"}
        rescue Mcp::Tool::ArgumentError => e
          {error: "Invalid arguments: #{e.message}"}
        rescue => e
          {error: "#{e.class}: #{e.message}"}
        end
      end
    end
  end
end
