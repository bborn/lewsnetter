# frozen_string_literal: true

module Mcp
  module Tools
    module Llm
      class TranslateSegment < Mcp::Tool::Base
        include Mcp::Tools::Serializers

        tool_name "llm_translate_segment"
        description "Translates a natural-language audience description into a SQL WHERE predicate, with sample matching subscribers and an estimated count. Wraps AI::SegmentTranslator."
        arguments_schema(
          type: "object",
          additionalProperties: false,
          required: ["natural_language"],
          properties: {
            natural_language: {type: "string"}
          }
        )

        def call(arguments:, context:)
          unless ::Llm::Configuration.current.usable?
            return {configured: false, error: "LLM not configured. Set credentials.llm.api_key or ANTHROPIC_API_KEY."}
          end

          result = AI::SegmentTranslator.new(team: context.team, natural_language: arguments["natural_language"]).call

          serialized_subscribers = result.sample_subscribers.map do |s|
            s.is_a?(Subscriber) ? serialize_subscriber(s) : s
          end

          {
            configured: true,
            result: {
              sql_predicate: result.sql_predicate,
              human_description: result.human_description,
              sample_subscribers: serialized_subscribers,
              estimated_count: result.estimated_count,
              errors: result.errors,
              stub: result.stub?
            }
          }
        end
      end
    end
  end
end
