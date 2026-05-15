# frozen_string_literal: true

module Chats
  # Bridges Mcp::Tool::Base descendants into RubyLLM::Tool subclasses so the
  # in-app chat (powered by ruby_llm's acts_as_chat) uses the same registry
  # as the MCP server. Each adaptation is per-context: the wrapper class
  # closes over a specific Mcp::Tool::Context so the running chat's user +
  # team scope every tool call.
  module ToolAdapter
    module_function

    def adapt_all(context:)
      Mcp::Tool::Loader.load_all.map { |t| adapt(t, context: context) }
    end

    def adapt(tool_class, context:)
      our_tool = tool_class
      ctx = context

      Class.new(RubyLLM::Tool) do
        description our_tool.description.to_s

        schema = our_tool.arguments_schema || {}
        required = Array(schema[:required] || schema["required"]).map(&:to_s)
        properties = schema[:properties] || schema["properties"] || {}
        properties.each do |key, prop|
          key_s = key.to_s
          ruby_type = ToolAdapter.json_schema_to_ruby_llm_type(prop[:type] || prop["type"])
          desc = prop[:description] || prop["description"] || ""
          param key_s.to_sym, type: ruby_type, desc: desc, required: required.include?(key_s)
        end

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

    def json_schema_to_ruby_llm_type(json_type)
      case json_type.to_s
      when "string" then :string
      when "integer" then :integer
      when "number" then :number
      when "boolean" then :boolean
      when "array" then :array
      when "object" then :object
      else :string
      end
    end
  end
end
