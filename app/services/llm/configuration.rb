# frozen_string_literal: true

# Centralizes LLM config. Read order:
#   1. ENV (ANTHROPIC_API_KEY, LLM_BASE_URL, LLM_DEFAULT_MODEL, LLM_PROVIDER)
#   2. credentials.llm namespace (provider, api_key, base_url, default_model)
#   3. credentials.anthropic.api_key (backwards compat with the old setup)
#
# `usable?` is the boolean predicate every degradation check uses. When false,
# AI::* services run in stub mode and the MCP llm_* tools return a structured
# "not configured" error instead of attempting a real call.
module Llm
  class Configuration
    DEFAULT_MODEL = "claude-sonnet-4-6"
    DEFAULT_PROVIDER = :anthropic

    def self.current
      new(
        credentials: (Rails.application.credentials.config rescue {}),
        env: ENV.to_h
      )
    end

    def initialize(credentials:, env:)
      @credentials = credentials || {}
      @env = env || {}
    end

    def usable?
      api_key.present?
    end

    def api_key
      @env["ANTHROPIC_API_KEY"].presence ||
        llm_namespace[:api_key].presence ||
        anthropic_namespace[:api_key].presence
    end

    def provider
      raw = @env["LLM_PROVIDER"].presence || llm_namespace[:provider]
      raw ? raw.to_sym : DEFAULT_PROVIDER
    end

    def base_url
      @env["LLM_BASE_URL"].presence || llm_namespace[:base_url].presence
    end

    def default_model
      @env["LLM_DEFAULT_MODEL"].presence || llm_namespace[:default_model].presence || DEFAULT_MODEL
    end

    private

    def llm_namespace
      @credentials[:llm] || {}
    end

    def anthropic_namespace
      @credentials[:anthropic] || {}
    end
  end
end
