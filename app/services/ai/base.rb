# frozen_string_literal: true

module AI
  # Common wiring for AI services: stub-mode detection, LLM client
  # construction, JSON-output parsing, and prompt helpers. Subclasses
  # implement `#call` and `#stub_result` (used when no API key is set or
  # when a real call fails).
  class Base
    DEFAULT_MODEL = "claude-sonnet-4-6"

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
      api_key = ENV["ANTHROPIC_API_KEY"].presence
      api_key ||= RubyLLM.config.anthropic_api_key.presence if defined?(RubyLLM)
      api_key.blank?
    end

    # Build a chat client. Subclasses can override `#model_id`.
    def chat
      @chat ||= RubyLLM.chat(model: model_id)
    end

    def model_id
      DEFAULT_MODEL
    end

    # Issue a single-shot prompt and return the response content as a String.
    # Returns nil on any error so callers can degrade to stub output.
    def ask_llm(system:, user:, schema: nil)
      client = chat.with_instructions(system)
      client = client.with_schema(schema) if schema
      result = client.ask(user)
      result.respond_to?(:content) ? result.content : result.to_s
    rescue => e
      Rails.logger.warn("[AI::#{self.class.name}] LLM call failed: #{e.class}: #{e.message}") if defined?(Rails)
      nil
    end

    # Try to parse a JSON object out of the model response. Models often wrap
    # JSON in fenced code blocks (```json ... ```) or include preamble text;
    # this peels off the outermost {...} block.
    def parse_json(raw)
      return nil if raw.blank?
      text = raw.to_s
      # Strip code fences if present.
      text = text.sub(/\A```(?:json)?\s*/i, "").sub(/```\s*\z/, "")
      # Find first {...} block.
      first = text.index("{")
      last = text.rindex("}")
      return nil unless first && last && last > first
      JSON.parse(text[first..last])
    rescue JSON::ParserError => e
      Rails.logger.warn("[AI::#{self.class.name}] JSON parse failed: #{e.message}") if defined?(Rails)
      nil
    end

    # Sample the observed custom_attributes keys + value types for a team's
    # subscribers. Limited to a handful so prompts stay short.
    def custom_attribute_schema(team, limit: 50)
      return {} unless team
      sample = team.subscribers.where.not(custom_attributes: {}).limit(limit).pluck(:custom_attributes)
      keys = Hash.new { |h, k| h[k] = Set.new }
      sample.each do |row|
        next unless row.is_a?(Hash)
        row.each { |k, v| keys[k] << infer_type(v) }
      end
      keys.transform_values { |types| types.to_a.join("|") }
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
