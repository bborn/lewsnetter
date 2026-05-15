# frozen_string_literal: true

# Configures the ruby_llm gem from Llm::Configuration.current. When the
# config is unusable (no API key, e.g. local dev without secrets), the
# initializer is a no-op and AI::* services run in stub mode.
#
# To route through an LLM gateway (e.g. Cloudflare AI Gateway), set
# credentials.llm.base_url or ENV["LLM_BASE_URL"] to the gateway's
# Anthropic-compatible URL. ruby_llm respects the override.
#
# The configuration is deferred to after_initialize so that Zeitwerk has
# finished loading app/services/llm/configuration.rb before we call it.
Rails.application.config.after_initialize do
  config = Llm::Configuration.current

  RubyLLM.configure do |c|
    c.anthropic_api_key = config.api_key if config.api_key.present?
    c.default_model = config.default_model
    c.request_timeout = 60

    # Generic gateway support: any gateway that exposes an Anthropic- or
    # OpenAI-compatible URL works by setting credentials.llm.base_url. ruby_llm
    # 1.15 exposes anthropic_api_base= / openai_api_base= for the per-provider
    # base URL. The respond_to? guard makes this a no-op on versions that
    # don't support it rather than raising.
    if config.base_url.present?
      case config.provider
      when :anthropic, :cloudflare
        c.anthropic_api_base = config.base_url if c.respond_to?(:anthropic_api_base=)
      when :openai_compatible
        c.openai_api_base = config.base_url if c.respond_to?(:openai_api_base=)
      end
    end
  end
end
