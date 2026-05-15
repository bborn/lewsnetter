# frozen_string_literal: true

# Cloudflare AI Gateway integration. **Optional and self-contained.**
#
# This initializer is a no-op unless `Llm::Configuration.current.cf_aig_token`
# is present (set via `credentials.llm.cf_aig_token` or `ENV["CF_AIG_TOKEN"]`).
# Operators who don't use Cloudflare AI Gateway can ignore this file entirely;
# Lewsnetter falls back to direct provider calls via the standard ruby_llm
# initializer.
#
# == What it does
#
# When configured, switches the Anthropic provider's request headers from
# the standard `x-api-key: <provider-key>` to Cloudflare's gateway-auth
# pattern: `cf-aig-authorization: Bearer <CF token>`. Pairs with Cloudflare's
# BYOK / Stored Keys feature where the upstream Anthropic key lives in CF and
# is attached on the way out.
#
# == Required configuration (only if you want CF gateway routing)
#
#   credentials.llm.base_url:      https://gateway.ai.cloudflare.com/v1/<account>/<gateway>/anthropic
#   credentials.llm.cf_aig_token:  cfut_...   (from CF dashboard → AI Gateway → API → Authentication)
#
# Then in the CF dashboard, store your Anthropic key under "Stored Keys" tagged
# as the Anthropic provider for that gateway.
#
# == Adapting to a different gateway
#
# OpenRouter, Helicone, LiteLLM, etc. each have their own auth header pattern.
# To support one of those, copy this file, change the header name + value, and
# gate it on a different `Llm::Configuration` field (or just an ENV var).
Rails.application.config.after_initialize do
  config = Llm::Configuration.current
  next unless config.cf_aig_token.present?
  next unless defined?(RubyLLM::Providers::Anthropic)

  RubyLLM::Providers::Anthropic.class_eval do
    define_method(:headers) do
      {
        "cf-aig-authorization" => "Bearer #{Llm::Configuration.current.cf_aig_token}",
        "anthropic-version" => "2023-06-01"
      }
    end
  end

  Rails.logger.info("[llm] Cloudflare AI Gateway BYOK enabled — sending cf-aig-authorization, suppressing x-api-key")
end
