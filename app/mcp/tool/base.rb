# frozen_string_literal: true

require "json-schema"

module Mcp
  module Tool
    class ArgumentError < StandardError; end

    # Abstract base class for MCP tools. Subclasses declare metadata via the
    # DSL (`tool_name`, `description`, `arguments_schema`) and implement
    # `#call(arguments:, context:)`. The loader at boot enumerates
    # `Base.descendants` and registers each with the FastMcp server.
    class Base
      class << self
        attr_reader :_tool_name, :_description, :_arguments_schema

        def tool_name(name = nil)
          return @_tool_name if name.nil?
          @_tool_name = name
        end

        def description(text = nil)
          return @_description if text.nil?
          @_description = text
        end

        def arguments_schema(schema = nil)
          return @_arguments_schema if schema.nil?
          @_arguments_schema = schema
        end

        # Tracks every subclass so the loader doesn't have to walk the
        # filesystem twice.
        def descendants
          @descendants ||= []
        end

        def inherited(subclass)
          super
          Base.descendants << subclass
        end
      end

      def call(arguments:, context:)
        raise NotImplementedError, "#{self.class} must implement #call"
      end

      # Validates arguments, then dispatches to #call. The server invokes
      # this — never #call directly — so schema validation is centralized.
      def invoke(arguments:, context:)
        validate!(arguments)
        call(arguments: arguments, context: context)
      end

      private

      def validate!(arguments)
        schema = self.class.arguments_schema
        return if schema.nil?
        # Pass schema as JSON string to force stringification of symbol keys,
        # ensuring compatibility between Ruby symbol-keyed schema declarations
        # and the string-keyed arguments that arrive over JSON-RPC.
        errors = JSON::Validator.fully_validate(schema.to_json, arguments)
        return if errors.empty?
        raise ArgumentError, errors.join("; ")
      end
    end
  end
end
