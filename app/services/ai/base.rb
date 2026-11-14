# frozen_string_literal: true

module AI
  # Common wiring for AI services: stub-mode detection, LLM client
  # construction, structured output, and prompt helpers. Subclasses
  # implement `#call` and `#stub_result` (used when no API key is set or
  # when a real call fails).
  class Base
    class << self
      # Allow tests / callers to flip stub mode on regardless of ENV.
      attr_accessor :force_stub
    end

    # Subclasses use this to mark a serializable result struct as stub-mode
    # for the view layer ("this is canned, not from an LLM").
    StubMarker = Module.new

    def initialize(**)
      # No-op — subclasses set their own ivars.
    end

    def call
      raise NotImplementedError, "#{self.class} must implement #call"
    end

    private

    # True when no API key is configured, when tests have forced stub mode,
    # or when ruby_llm isn't loaded.
    def stub_mode?
      return true if self.class.force_stub
      return true if Base.force_stub
      !Llm::Configuration.current.usable?
    end

    # Build a chat client. Subclasses can override `#model_id`.
    def chat
      @chat ||= RubyLLM.chat(model: model_id)
    end

    def model_id
      Llm::Configuration.current.default_model
    end

    # Issue a single-shot prompt. Returns the response text, or, given a
    # schema (a Schematist::Schema class or a JSON Schema Hash), the Hash the
    # model answered in that shape: the provider constrains the output to
    # the schema, so there is no JSON to dig out of prose. Returns nil on any
    # error so callers can degrade to stub output.
    def ask_llm(system:, user:, schema: nil)
      client = chat.with_instructions(system)
      client = client.with_schema(schema) if schema
      result = client.ask(user)
      schema ? result.parsed : result.content
    rescue => e
      Rails.logger.warn("[AI::#{self.class.name}] LLM call failed: #{e.class}: #{e.message}") if defined?(Rails)
      nil
    end

    # Sample the observed custom_attributes keys + value types for a team's
    # subscribers. Limited to a handful so prompts stay short.
    # Delegates to Team::CustomAttributeSchema so the MCP tool can reuse the
    # same logic without calling a private method.
    def custom_attribute_schema(team, limit: 50)
      Team::CustomAttributeSchema.new(team: team, limit: limit).call[:sample]
    end

    def observed_event_names(team, limit: 25)
      return [] unless team
      team.events.distinct.limit(limit).pluck(:name)
    end

    def infer_type(value)
      case value
      when TrueClass, FalseClass then "boolean"
      when Integer then "integer"
      when Float then "number"
      when Array then "array"
      when Hash then "object"
      when nil then "null"
      else "string"
      end
    end
  end
end
