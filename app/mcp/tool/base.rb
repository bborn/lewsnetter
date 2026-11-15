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
      NOT_ALLOWED = "Your role on this team doesn't allow this."

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

        # Declares that the tool only reads team data, so a token granted
        # just mcp:read may call it. Tools that don't say so need write
        # access (see Mcp::Tool::Context#may_call?).
        def read_only
          @_read_only = true
        end

        def read_only?
          @_read_only == true
        end

        # Keeps the tool out of the in-app agent; external MCP clients still
        # get it. The agent reads team data that outsiders can write, so sends
        # stay a button the user presses.
        def hidden_from_in_app_agent
          @_hidden_from_in_app_agent = true
        end

        def hidden_from_in_app_agent?
          @_hidden_from_in_app_agent == true
        end

        # The CanCan ability a caller needs on the calling team, e.g.
        # `requires_ability :destroy, Subscriber`. Checked by #invoke against
        # the user's current roles (config/models/roles.yml); a tool that
        # declares none is refused.
        def requires_ability(action = nil, subject = nil)
          return @_required_ability if action.nil?
          @_required_ability = [action, subject]
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
        authorize!(context)
        validate!(arguments)
        call(arguments: arguments, context: context)
      end

      private

      # Roles change while sockets and tokens stay open, so build the Ability
      # from a freshly loaded user rather than the one the context carries.
      def authorize!(context)
        action, model = self.class.requires_ability
        raise CanCan::AccessDenied.new("#{self.class.tool_name} declares no ability") if action.nil?

        subject = (model == ::Team) ? context.team : model.new(team_id: context.team.id)
        Ability.new(User.find(context.user.id)).authorize!(action, subject)
      end

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
