# frozen_string_literal: true

require "erb"

module Mcp
  module Skill
    # Renders a Skill::Base's raw_body as ERB, with an Mcp::Tool::Context
    # available as `context` inside ERB tags. Errors don't raise — they're
    # surfaced inline so an LLM consuming the resource sees a useful message
    # rather than a silent empty body.
    class Renderer
      def initialize(skill:, context:)
        @skill = skill
        @context = context
      end

      def call
        binding_with_context = Binder.new(@context).get_binding
        ERB.new(@skill.raw_body, trim_mode: "-").result(binding_with_context)
      rescue => e
        <<~ERR
          [skill render error]
          The skill `#{@skill.name}` could not be fully rendered:
          #{e.class}: #{e.message}
        ERR
      end

      # Provides the binding that ERB tags evaluate against. Only exposes
      # `context` — keeps the surface area tight and predictable.
      class Binder
        def initialize(context)
          @context = context
        end

        def context
          @context
        end

        def get_binding
          binding
        end
      end
    end
  end
end
