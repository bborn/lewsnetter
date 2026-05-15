# MCP LLM Configuration + LLM Tools (Phase 4 of 6)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Centralize LLM configuration (provider, key, base URL, default model) so the existing `AI::*` services, the new MCP `llm_*` tools, and the upcoming in-app agent all read from the same source of truth — and so an LLM gateway like Cloudflare AI Gateway can be plugged in via a single `base_url` change.

**Architecture:** New `Llm::Configuration` PORO reads from `Rails.application.credentials.llm` (with backwards-compat fallback to the existing `credentials.anthropic.api_key`) and ENV. The `ruby_llm` initializer is rewritten to read from it. `AI::Base#stub_mode?` delegates to `Llm::Configuration.current.usable?`. Three new MCP tools (`llm_draft_campaign`, `llm_translate_segment`, `llm_analyze_send`) wrap the existing services and degrade gracefully when LLM credentials aren't configured.

**Tech Stack:** `ruby_llm 1.15` (already installed), the new `Llm::Configuration` PORO, the existing `AI::CampaignDrafter`, `AI::SegmentTranslator`, `AI::PostSendAnalyst` services.

**Reference spec:** `docs/superpowers/specs/2026-05-15-mcp-and-in-app-agent-design.md` §"LLM configuration + gateway" + §"Failure / degradation matrix"

**Out of scope:** In-app agent UI/channel (Phase 5), cross-link existing AI panels (Phase 6).

---

## File structure

**Created:**
- `app/services/llm/configuration.rb`
- `test/services/llm/configuration_test.rb`
- `app/mcp/tools/llm/draft_campaign.rb` + test
- `app/mcp/tools/llm/translate_segment.rb` + test
- `app/mcp/tools/llm/analyze_send.rb` + test

**Modified:**
- `config/initializers/ruby_llm.rb` — read from `Llm::Configuration.current`
- `app/services/ai/base.rb` — `stub_mode?` delegates to `Llm::Configuration.current.usable?`

---

## Task 1: `Llm::Configuration`

A PORO that consolidates how the app reads LLM credentials and config. Reads from `Rails.application.credentials.llm` first, then falls back to the existing `credentials.anthropic.api_key` for backwards compat (no rewrite of credentials needed; subsequent ops can migrate).

**Files:**
- Create: `app/services/llm/configuration.rb`
- Create: `test/services/llm/configuration_test.rb`

- [ ] **Step 1: Failing test**

```ruby
# test/services/llm/configuration_test.rb
require "test_helper"

module Llm
  class ConfigurationTest < ActiveSupport::TestCase
    test "with no credentials and no ENV, usable? is false" do
      config = Configuration.new(credentials: {}, env: {})
      refute config.usable?
      assert_nil config.api_key
      assert_equal :anthropic, config.provider
      assert_equal "claude-sonnet-4-6", config.default_model
      assert_nil config.base_url
    end

    test "reads from credentials.llm namespace" do
      creds = {llm: {provider: "cloudflare", api_key: "sk-cf-test", base_url: "https://gateway.example.com/v1/anthropic", default_model: "claude-haiku-4-5"}}
      config = Configuration.new(credentials: creds, env: {})
      assert config.usable?
      assert_equal "sk-cf-test", config.api_key
      assert_equal :cloudflare, config.provider
      assert_equal "https://gateway.example.com/v1/anthropic", config.base_url
      assert_equal "claude-haiku-4-5", config.default_model
    end

    test "falls back to credentials.anthropic.api_key when llm namespace absent (backwards compat)" do
      creds = {anthropic: {api_key: "sk-ant-old"}}
      config = Configuration.new(credentials: creds, env: {})
      assert config.usable?
      assert_equal "sk-ant-old", config.api_key
      assert_equal :anthropic, config.provider
    end

    test "ENV ANTHROPIC_API_KEY overrides credentials" do
      creds = {llm: {api_key: "from-creds"}}
      env = {"ANTHROPIC_API_KEY" => "from-env"}
      config = Configuration.new(credentials: creds, env: env)
      assert_equal "from-env", config.api_key
    end

    test "ENV LLM_BASE_URL overrides credentials base_url" do
      creds = {llm: {api_key: "k", base_url: "https://creds.example.com"}}
      env = {"LLM_BASE_URL" => "https://env.example.com"}
      config = Configuration.new(credentials: creds, env: env)
      assert_equal "https://env.example.com", config.base_url
    end

    test ".current returns a Configuration built from app credentials + ENV" do
      assert_kind_of Configuration, Configuration.current
    end
  end
end
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement**

```ruby
# app/services/llm/configuration.rb
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
```

- [ ] **Step 4: Run, expect green.**

- [ ] **Step 5: Commit**

```bash
git add app/services/llm/configuration.rb test/services/llm/configuration_test.rb
git commit -m "feat(llm): Llm::Configuration — centralized config with gateway support"
```

---

## Task 2: Rewrite the `ruby_llm` initializer

Reads from `Llm::Configuration.current` and (when present) sets the base URL for gateway routing.

**Files:**
- Modify: `config/initializers/ruby_llm.rb`

- [ ] **Step 1: Update the initializer**

```ruby
# config/initializers/ruby_llm.rb
# frozen_string_literal: true

# Configures the ruby_llm gem from Llm::Configuration.current. When the
# config is unusable (no API key, e.g. local dev without secrets), the
# initializer is a no-op and AI::* services run in stub mode.
#
# To route through an LLM gateway (e.g. Cloudflare AI Gateway), set
# credentials.llm.base_url or ENV["LLM_BASE_URL"] to the gateway's
# Anthropic-compatible URL. ruby_llm respects the override.
config = Llm::Configuration.current

RubyLLM.configure do |c|
  c.anthropic_api_key = config.api_key if config.api_key.present?
  c.default_model = config.default_model
  c.request_timeout = 60

  # Gateway override. ruby_llm exposes a per-provider base URL setter on the
  # config struct in 1.15+; if your installed version uses a different name
  # (e.g. anthropic_base_url, anthropic_endpoint, openai_base_url), adjust here.
  if config.base_url.present?
    case config.provider
    when :anthropic, :cloudflare
      c.anthropic_api_url = config.base_url if c.respond_to?(:anthropic_api_url=)
    when :openai_compatible
      c.openai_api_url = config.base_url if c.respond_to?(:openai_api_url=)
    end
  end
end
```

> **CAVEAT:** `RubyLLM::Configuration` setter names vary by version. Check what's available with `bundle exec rails runner 'puts RubyLLM.config.methods.grep(/=$/).sort'` and adapt the gateway-override block. If neither setter exists, you may need to monkey-patch ruby_llm OR use a Faraday middleware. Don't over-engineer for v1 — if the gateway can't be wired through ruby_llm cleanly, log a warning and let the call go to default Anthropic. Phase 5's in-app agent can route through the gateway via a different code path if needed.

- [ ] **Step 2: Sanity-check boot**

```bash
bundle exec rails runner 'puts "boot ok; usable=#{Llm::Configuration.current.usable?}"'
```

Expected: prints `boot ok; usable=true` (if creds present) or `boot ok; usable=false`. No exceptions.

- [ ] **Step 3: Commit**

```bash
git add config/initializers/ruby_llm.rb
git commit -m "feat(llm): rewrite ruby_llm initializer to read from Llm::Configuration"
```

---

## Task 3: Refactor `AI::Base#stub_mode?` to delegate

**Files:**
- Modify: `app/services/ai/base.rb`

- [ ] **Step 1: Update**

In `app/services/ai/base.rb`, find the existing `stub_mode?` method:

```ruby
def stub_mode?
  return true if self.class.force_stub
  return true if Base.force_stub
  api_key = ENV["ANTHROPIC_API_KEY"].presence
  api_key ||= RubyLLM.config.anthropic_api_key.presence if defined?(RubyLLM)
  api_key.blank?
end
```

Replace with:

```ruby
def stub_mode?
  return true if self.class.force_stub
  return true if Base.force_stub
  !Llm::Configuration.current.usable?
end
```

- [ ] **Step 2: Run existing AI tests** — they must still pass:

```bash
bin/rails test test/services/ai/
```

Expected: all green (the tests use `AI::Base.force_stub = true` in setup, so stub mode triggers regardless of credentials).

- [ ] **Step 3: Commit**

```bash
git add app/services/ai/base.rb
git commit -m "refactor(ai): AI::Base#stub_mode? delegates to Llm::Configuration"
```

---

## Tasks 4-6: Three LLM-backed MCP tools

Each wraps an existing AI service and adds the "not configured" degradation path.

### Task 4: `llm_draft_campaign`

**Files:**
- Create: `app/mcp/tools/llm/draft_campaign.rb`
- Create: `test/mcp/tools/llm/draft_campaign_test.rb`

- [ ] **Step 1: Failing test**

```ruby
# test/mcp/tools/llm/draft_campaign_test.rb
require "test_helper"

module Mcp
  module Tools
    module Llm
      class DraftCampaignTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
          AI::Base.force_stub = true
        end

        teardown { AI::Base.force_stub = false }

        test "returns a draft when called with a brief" do
          result = DraftCampaign.new.invoke(
            arguments: {"brief" => "- launch announcement\n- value to user\n- CTA"},
            context: @ctx
          )
          assert result[:draft][:subject_candidates].is_a?(Array)
          assert_equal 5, result[:draft][:subject_candidates].size
          assert result[:draft][:markdown_body].present?
          assert result[:draft][:stub], "should be flagged as stub-mode draft"
        end

        test "accepts optional segment_id" do
          seg = @team.segments.create!(name: "Pros", natural_language_source: "pro plan users")
          result = DraftCampaign.new.invoke(
            arguments: {"brief" => "x", "segment_id" => seg.id},
            context: @ctx
          )
          assert result[:draft][:markdown_body].present?
        end

        test "returns 'not configured' shape when stub_mode? is forced AND configured? checked separately" do
          # When we want to test the not-configured path explicitly:
          original = Llm::Configuration.singleton_class.instance_method(:current)
          Llm::Configuration.singleton_class.define_method(:current) { Llm::Configuration.new(credentials: {}, env: {}) }
          AI::Base.force_stub = false  # let the real path run
          begin
            result = DraftCampaign.new.invoke(arguments: {"brief" => "x"}, context: @ctx)
            assert_equal false, result[:configured]
            assert_match(/not configured/i, result[:error])
          ensure
            Llm::Configuration.singleton_class.define_method(:current, original)
          end
        end

        test "raises ArgumentError when brief is missing" do
          assert_raises(Mcp::Tool::ArgumentError) do
            DraftCampaign.new.invoke(arguments: {}, context: @ctx)
          end
        end
      end
    end
  end
end
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement**

```ruby
# app/mcp/tools/llm/draft_campaign.rb
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
```

- [ ] **Step 4: Run tests, expect green.**

- [ ] **Step 5: Commit**

```bash
git add app/mcp/tools/llm/draft_campaign.rb test/mcp/tools/llm/draft_campaign_test.rb
git commit -m "feat(mcp): llm_draft_campaign — wraps AI::CampaignDrafter with degradation"
```

### Task 5: `llm_translate_segment`

**Files:**
- Create: `app/mcp/tools/llm/translate_segment.rb`
- Create: `test/mcp/tools/llm/translate_segment_test.rb`

Same pattern. Tool wraps `AI::SegmentTranslator`. Args: `{natural_language: string required}`. Returns: `{configured: bool, result: {sql_predicate, human_description, sample_subscribers, estimated_count, errors, stub}, error?}`.

- [ ] TDD per the same template. Commit:

```bash
git add app/mcp/tools/llm/translate_segment.rb test/mcp/tools/llm/translate_segment_test.rb
git commit -m "feat(mcp): llm_translate_segment — wraps AI::SegmentTranslator with degradation"
```

### Task 6: `llm_analyze_send`

**Files:**
- Create: `app/mcp/tools/llm/analyze_send.rb`
- Create: `test/mcp/tools/llm/analyze_send_test.rb`

Wraps `AI::PostSendAnalyst`. Args: `{campaign_id: int required}`. Returns: `{configured: bool, markdown: string, error?}`. Find the campaign via `context.team.campaigns.find(arguments["campaign_id"])`.

- [ ] TDD. Commit:

```bash
git add app/mcp/tools/llm/analyze_send.rb test/mcp/tools/llm/analyze_send_test.rb
git commit -m "feat(mcp): llm_analyze_send — wraps AI::PostSendAnalyst with degradation"
```

---

## Task 7: Smoke + suite

- [ ] **Step 1:** `bin/rails test test/mcp/ test/services/llm/ test/services/ai/` — all green.

- [ ] **Step 2:** Live smoke (with stub mode forced for predictability):

```bash
bin/dev > /tmp/dev.log 2>&1 &
sleep 8

TOKEN=$(bin/rails runner '
  user = User.find_by(email: "qa@local.test") || User.first
  team = user.current_team
  app = Platform::Application.find_or_create_by!(name: "MCP smoke") do |a|
    a.user = user; a.team = team
    a.uid = SecureRandom.hex(8); a.secret = SecureRandom.hex(16)
    a.redirect_uri = "urn:ietf:wg:oauth:2.0:oob"
  end
  print Doorkeeper::AccessToken.create!(resource_owner_id: user.id, application: app, scopes: "read write delete", token: SecureRandom.hex).token
' 2>/dev/null | tail -1)

# tools/list — should now show 43 tools
curl -s -X POST http://localhost:3000/mcp/messages \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' \
  | python3 -c "import json,sys; d=json.load(sys.stdin); ts=d['result']['tools']; print(len(ts),'tools'); [print(' ',t['name']) for t in ts if t['name'].startswith('llm_')]"

# llm_draft_campaign — will return real or stub draft depending on creds
curl -s -X POST http://localhost:3000/mcp/messages \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"llm_draft_campaign","arguments":{"brief":"- new feature\n- helpful for power users"}}}' \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['result']['content'][0]['text'][:400])"

pkill -9 -f "puma\|bin/dev\|foreman" 2>/dev/null
```

Expected: `43 tools`, with `llm_draft_campaign`, `llm_translate_segment`, `llm_analyze_send` listed; the call returns a draft body (real or stub).

---

## Self-review

**Spec coverage:**
- [x] `Llm::Configuration` PORO with provider/api_key/base_url/default_model — Task 1
- [x] Cloudflare AI Gateway support via `base_url` override — Task 2
- [x] `AI::Base#stub_mode?` delegates — Task 3
- [x] Three LLM-backed MCP tools wrap existing services — Tasks 4-6
- [x] Graceful degradation: tools return structured "not configured" error when no LLM — Tasks 4-6 each include this branch

**Type / name consistency:** `Llm::Configuration.current.usable?` is the single predicate. `Mcp::Tools::Llm::*` mirrors the existing `Mcp::Tools::*` namespace pattern.

**Placeholders:** none.

**Implementation deviations expected:**
- `RubyLLM` setter names for base URL may differ across 1.x versions — Task 2's caveat addresses this. If the setter doesn't exist, log + skip rather than fail boot.
- The "not configured" stub-mode test in Task 4 redefines `Llm::Configuration.current` via singleton — if this conflicts with concurrent tests, isolate via `Minitest::Mock` or a thread-local override instead.
