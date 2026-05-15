# frozen_string_literal: true

module Mcp
  module Tool
    # Per-request context handed to every Mcp::Tool::Base subclass. Carries
    # the authenticated user + their current team (the token's resource
    # owner). Frozen so tools can't mutate it mid-call.
    class Context
      attr_reader :user, :team

      def initialize(user:, team:)
        raise ArgumentError, "user is required" if user.nil?
        raise ArgumentError, "team is required" if team.nil?
        @user = user
        @team = team
        freeze
      end
    end
  end
end
