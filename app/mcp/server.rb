# frozen_string_literal: true

require "fast_mcp"

module Mcp
  # Builds a singleton FastMcp::Server with all Mcp::Tool::Base descendants
  # registered. `rack_app` returns a Rack-callable mounted at /mcp by
  # config/routes.rb. Per-request, the user + team set by DoorkeeperAuth
  # are read from the env and packaged into an Mcp::Tool::Context that's
  # handed to each tool invocation.
  #
  # FastMcp 1.6 API notes (discovered from gem source):
  #
  # - FastMcp::Server.new(name:, version:, logger:) — kwargs as expected.
  # - register_tool(klass) accepts a **class** (not an instance). The class must
  #   respond to .tool_name, .description, .input_schema_to_json, and expose a
  #   #call(**args) instance method. So we dynamically build a FastMcp::Tool
  #   subclass for each Mcp::Tool::Base descendant.
  # - For Rack, server.start_rack(downstream_app, options) returns a
  #   RackTransport (Rack middleware). We pass a 404 stub as the downstream app
  #   so the transport handles /mcp/* requests and falls through to the stub for
  #   everything else (which never happens when mounted in Rails routes).
  # - RackTransport defaults to localhost_only: true. We disable that here
  #   because our DoorkeeperAuth middleware handles auth; the transport is
  #   mounted behind it.
  # - Context threading: FastMcp's server calls tool_instance.call(**args) on
  #   an instance that was constructed before our wrapper can inject context.
  #   We use Thread.current[:mcp_context] (set per-request in rack_app) to
  #   pass the Mcp::Tool::Context into each delegating call. This is safe under
  #   Puma (one thread per request).
  module Server
    module_function

    def instance
      @instance ||= build
    end

    # Returns a Rack-callable suitable for `mount` in config/routes.rb.
    # Sets Thread.current[:mcp_context] before each request so tool
    # handlers can read it, and clears it in an ensure block.
    def rack_app
      @rack_app ||= begin
        # Build a minimal 404 stub for requests the transport doesn't handle.
        not_found = ->(_env) { [404, {"Content-Type" => "text/plain"}, ["Not Found"]] }

        transport = instance.start_rack(not_found,
          path_prefix: "/mcp",
          localhost_only: false,
          logger: Rails.logger)

        lambda do |env|
          Thread.current[:mcp_context] = Mcp::Tool::Context.new(
            user: env.fetch("mcp.user"),
            team: env.fetch("mcp.team")
          )
          transport.call(env)
        ensure
          Thread.current[:mcp_context] = nil
        end
      end
    end

    def build
      server = FastMcp::Server.new(name: "lewsnetter", version: "0.1.0", logger: Rails.logger)
      Mcp::Tool::Loader.load_all.each do |tool_class|
        server.register_tool(wrap(tool_class))
      end
      server
    end

    # Dynamically creates a FastMcp::Tool subclass that:
    #   - copies .tool_name, .description, and a simple JSON schema from our DSL
    #   - delegates #call(**args) back to our Mcp::Tool::Base subclass,
    #     supplying the per-request context from Thread.current
    def wrap(tool_class)
      our_tool = tool_class

      schema = our_tool._arguments_schema || {type: "object", properties: {}}

      Class.new(FastMcp::Tool) do
        # Class-level DSL
        tool_name our_tool._tool_name
        description our_tool._description

        # Provide a compatible input_schema_to_json so handle_tools_list
        # in the server serialises correctly. We bypass the Dry::Schema
        # machinery and return the raw hash our DSL carries.
        define_singleton_method(:input_schema_to_json) { schema }

        # Override input_schema with a no-op Dry schema that always passes,
        # because our Mcp::Tool::Base#invoke does its own JSON-Schema validation.
        define_singleton_method(:input_schema) do
          @_passthrough_schema ||= Dry::Schema.JSON
        end

        # The server calls tool_instance.call(**symbolized_args)
        define_method(:call) do |**args|
          ctx = Thread.current[:mcp_context]
          raise "missing per-request MCP context" if ctx.nil?

          our_tool.new.invoke(arguments: args, context: ctx)
        end
      end
    end
  end
end
