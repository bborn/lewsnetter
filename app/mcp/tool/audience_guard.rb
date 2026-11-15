# frozen_string_literal: true

module Mcp
  module Tool
    # A campaign with no segment goes to every subscribed contact. Sending or
    # scheduling one over MCP takes an explicit all_subscribers: true.
    module AudienceGuard
      ALL_SUBSCRIBERS_PROPERTY = {
        type: "boolean",
        description: "Required when the campaign has no segment: confirms it goes to every subscribed contact."
      }.freeze

      private

      def require_audience!(campaign, arguments)
        return if campaign.segment.present? || arguments["all_subscribers"] == true

        raise Mcp::Tool::ArgumentError,
          "This campaign has no segment, so it would go to all #{campaign.recipient_count} subscribed contacts. " \
          "Set a segment, or pass all_subscribers: true."
      end
    end
  end
end
