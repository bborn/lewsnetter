# frozen_string_literal: true

# API-key-and-gateway config. Deferred to after_initialize so that Zeitwerk
# has finished loading app/services/llm/configuration.rb before we call it.
#
# `use_new_acts_as = true` is set in config/application.rb (must run BEFORE
# the ruby_llm Railtie's on_load(:active_record) callback fires).
#
# When the config is unusable (no API key, e.g. local dev without secrets),
# the block is a no-op and AI::* services run in stub mode.
#
# To route through an LLM gateway (e.g. Cloudflare AI Gateway), set
# credentials.llm.base_url or ENV["LLM_BASE_URL"] to the gateway's
# Anthropic-compatible URL.
Rails.application.config.after_initialize do
  config = Llm::Configuration.current

  RubyLLM.configure do |c|
    c.anthropic_api_key = config.api_key if config.api_key.present?
    c.default_model = config.default_model
    c.request_timeout = 60

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
