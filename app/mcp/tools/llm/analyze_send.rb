# frozen_string_literal: true

module Mcp
  module Tools
    module Llm
      class AnalyzeSend < Mcp::Tool::Base
        tool_name "llm_analyze_send"
        description "Generates a post-send analysis of a campaign in markdown: what worked, what didn't, and 3 specific actions. Wraps AI::PostSendAnalyst."
        arguments_schema(
          type: "object",
          additionalProperties: false,
          required: ["campaign_id"],
          properties: {
            campaign_id: {type: "integer"}
          }
        )

        def call(arguments:, context:)
          campaign = context.team.campaigns.find_by!(id: arguments["campaign_id"])

          unless ::Llm::Configuration.current.usable?
            return {configured: false, error: "LLM not configured. Set credentials.llm.api_key or ANTHROPIC_API_KEY."}
          end

          markdown = AI::PostSendAnalyst.new(campaign: campaign).call
          {configured: true, markdown: markdown, campaign_id: campaign.id}
        end
      end
    end
  end
end
