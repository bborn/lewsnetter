# frozen_string_literal: true

module Mcp
  module Tool
    # Per-request context handed to every Mcp::Tool::Base subclass. Carries
    # the authenticated user + their current team (the token's resource
    # owner), and the token's OAuth scopes when the call came in over MCP.
    # Frozen so tools can't mutate it mid-call.
    class Context
      # Scopes whose consent text covers changing data
      # (config/locales/en/doorkeeper.en.yml).
      WRITE_SCOPES = %w[mcp:write admin].freeze

      attr_reader :user, :team, :scopes

      # `scopes` is nil for the in-app agent, which has no token.
      def initialize(user:, team:, scopes: nil)
        raise ArgumentError, "user is required" if user.nil?
        raise ArgumentError, "team is required" if team.nil?
        @user = user
        @team = team
        @scopes = scopes&.map(&:to_s)&.freeze
        freeze
      end

      # A token granted mcp:read and nothing that allows writing may only
      # call read-only tools. Tokens without mcp:* scopes (sync, platform
      # agent and admin tokens) keep the access they had before scopes
      # were checked.
      def may_call?(tool_class)
        tool_class.read_only? || !read_only_token?
      end

      private

      def read_only_token?
        return false if scopes.nil?
        scopes.include?("mcp:read") && !scopes.intersect?(WRITE_SCOPES)
      end
    end
  end
end
