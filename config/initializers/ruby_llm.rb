# frozen_string_literal: true

# Configures the ruby_llm gem. When ANTHROPIC_API_KEY is absent the AI services
# in app/services/ai/* fall back to stub mode, so this configuration is purely
# additive — nothing breaks if the key is missing.
RubyLLM.configure do |config|
  api_key =
    ENV["ANTHROPIC_API_KEY"].presence ||
    (Rails.application.credentials.dig(:anthropic, :api_key) rescue nil) ||
    (Rails.application.credentials.respond_to?(:anthropic_api_key) ? Rails.application.credentials.anthropic_api_key : nil)

  config.anthropic_api_key = api_key if api_key.present?
  config.default_model = ENV.fetch("RUBY_LLM_DEFAULT_MODEL", "claude-sonnet-4-6")
  config.request_timeout = 60
end
