# frozen_string_literal: true

module Mcp
  module Tools
    module Llm
      class DraftCampaign < Mcp::Tool::Base
        tool_name "llm_draft_campaign"
        description "Drafts a campaign from a brief: 5 subject candidates with rationale, preheader, markdown body, suggested send time. Wraps AI::CampaignDrafter."
        arguments_schema(
          type: "object",
          additionalProperties: false,
          required: ["brief"],
          properties: {
            brief: {type: "string"},
            segment_id: {type: "integer"},
            tone: {type: "string"}
          }
        )

        def call(arguments:, context:)
          unless ::Llm::Configuration.current.usable?
            return {configured: false, error: "LLM not configured. Set credentials.llm.api_key or ANTHROPIC_API_KEY."}
          end

          segment = arguments["segment_id"] ? context.team.segments.find(arguments["segment_id"]) : nil
          drafter = AI::CampaignDrafter.new(team: context.team, brief: arguments["brief"], segment: segment, tone: arguments["tone"])
          draft = drafter.call
          {
            configured: true,
            draft: {
              subject_candidates: draft.subject_candidates.map { |c| {subject: c.subject, rationale: c.rationale} },
              preheader: draft.preheader,
              markdown_body: draft.markdown_body,
              suggested_send_time: draft.suggested_send_time,
              errors: draft.errors,
              stub: draft.stub?
            }
          }
        end
      end
    end
  end
end
