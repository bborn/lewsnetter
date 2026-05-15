# MCP server + in-app agent

**Date:** 2026-05-15
**Author:** Bruno + Claude
**Status:** Design — pending review

## What we're building

A first-class **Model Context Protocol (MCP) server** for Lewsnetter, plus an **in-app agent** that uses the same tool surface to do work for users from a chat panel.

External agents (Claude.ai, Cursor, OpenClaw, Codex, anything that speaks MCP) get scoped, authenticated access to the full Lewsnetter workspace. The in-app agent is an opinionated client on top of the same tool registry that replaces the existing one-shot AI panels (campaign drafter, segment translator, post-send analyst) with a conversational interface that can chain tools across the whole product.

## Why now

1. PostHog's lesson — "expose raw API as MCP tools, ship skills for common workflows, learn what agents actually do before building bespoke harnesses." We have a clean BulletTrain-scaffolded API and three useful AI features already; the next investment is leverage, not more bespoke panels.
2. We already wrote and tore out a Lewsnetter→IK Ruby gem because path-vendoring outweighed the value. MCP is the inverse leverage: every agent gets it for free without a per-consumer integration.
3. The existing AI services (`AI::CampaignDrafter`, `AI::SegmentTranslator`, `AI::PostSendAnalyst`) already have the shape — system prompt + structured output + graceful stub mode. They become tools, not endpoints.

## Principles (PostHog playbook, applied)

- **Capabilities over features.** Each existing API action becomes a tool. We do not invent new abstractions; the MCP surface mirrors what `Api::V1::*Controller` already exposes.
- **Raw tools + skills.** Low-level tools are unopinionated (one verb each). Skills are markdown documents that teach an agent how to chain tools for common workflows ("draft and send a newsletter," "build a segment from a question," "analyze last week's send").
- **Live context in skills.** Skills include rendered context (current team's custom_attribute schema, recent campaign voice samples, available templates) — not static docs.
- **Validate demand.** Telemetry from day one: which tools get called, which skills get loaded, by what client, against what team. We need this to know what to invest in next.
- **Degrade gracefully.** No LLM key configured → MCP server still serves raw tools. Only LLM-backed tools (`llm.draft_campaign`, `llm.translate_segment`, `llm.analyze_send`) return a structured "LLM not configured" error.

## Architecture

### MCP server

- **Gem:** `fast-mcp` (Rack-mountable, supports streamable HTTP transport, integrates with Rails routing).
- **Mount point:** `POST /mcp` (and `GET /mcp` for SSE upgrade), as a Rack-mounted endpoint in `config/routes.rb`. No CSRF (API path, token-authed).
- **Auth:** A custom Rack middleware (`Mcp::DoorkeeperAuth`) sits in front of the MCP endpoint and validates `Authorization: Bearer <token>` against `Doorkeeper::AccessToken` (which maps to `Platform::AccessToken`). On success it sets `env["mcp.current_user"]` and `env["mcp.current_team"]` (the token's resource owner; we already use one-team-per-token in the IK integration). On failure it returns `401` with a JSON-RPC error body.
- **Tool registry:** New directory `app/mcp/tools/`. One Ruby file per tool. Each subclasses `Mcp::Tool::Base` and declares: `tool_name`, `description`, `arguments_schema` (JSON Schema), `call(arguments:, context:)`. A loader at boot enumerates the directory and registers each tool with the `fast-mcp` server. Tools call models / services directly — they do not roundtrip through the HTTP API.
- **Resource registry:** `app/mcp/skills/*.md`. Loader reads each file, parses frontmatter (`name`, `description`, `when_to_use`), and registers it as an MCP resource at `skill://<name>`. Skills can reference live context via ERB (e.g. `<%= context.team.subscribers.count %>`) — rendered per-request when the agent reads the resource.

### Tool surface

Mirrors `config/routes/api/v1.rb` plus three LLM-backed tools and one tenant-context tool.

| Group | Tools |
|---|---|
| `team` | `get_current`, `list_companies`, `custom_attribute_schema` |
| `subscribers` | `list`, `get`, `find_by_external_id`, `create`, `update`, `delete`, `bulk_upsert`, `count` |
| `segments` | `list`, `get`, `create`, `update`, `delete`, `count_matching`, `sample_matching` |
| `email_templates` | `list`, `get`, `create`, `update`, `delete`, `render_preview` |
| `campaigns` | `list`, `get`, `create`, `update`, `delete`, `send_test`, `send_now`, `schedule`, `postmortem` |
| `sender_addresses` | `list`, `get`, `create`, `verify` |
| `events` | `track`, `bulk_track`, `list_for_subscriber` |
| `llm` | `draft_campaign` (wraps `AI::CampaignDrafter`), `translate_segment` (wraps `AI::SegmentTranslator`), `analyze_send` (wraps `AI::PostSendAnalyst`) |

Authorization for each tool routes through CanCanCan via the token's resource owner — same path as the API controllers. The tool wrappers always scope to `context.team` (the token's tenant), so cross-tenant access is impossible.

### Skills

Initial set, all in `app/mcp/skills/`:

- `draft-and-send-newsletter.md` — picks a segment, drafts a campaign with `llm.draft_campaign`, sends a test, asks for confirmation, sends.
- `translate-question-to-segment.md` — natural language → predicate → preview → save segment.
- `analyze-recent-send.md` — finds the last sent campaign, runs `llm.analyze_send`, surfaces 3 actions.
- `import-subscribers-from-csv.md` — guides through a CSV upload, dedupe, and dry-run.
- `segment-cookbook.md` — reference resource: common predicate patterns for the team's actual `custom_attributes` schema (rendered live per-team).
- `voice-samples.md` — reference resource: the team's last 10 campaign subjects + body excerpts. Drafted prompts can include this by reference.

Skills are intentionally short (≤ 200 lines). The format is the same we'd hand a junior PM.

### In-app agent

- **Service:** `Agent::Runner` orchestrates the turn loop. Uses `ruby_llm` (already in the app, version 1.15) with tool-use enabled. The tool definitions are generated from the same `Mcp::Tool::Base` registry — no duplication.
- **Streaming:** New `AgentChannel` (ActionCable). Streams three message types: `reasoning` (thinking), `tool_call` (which tool + arguments + result), `assistant` (final or interim text). The UI renders each as a separate bubble with appropriate chrome.
- **Persistence:** `AgentConversation` (belongs_to team, user) and `AgentMessage` (belongs_to conversation, role enum: user/assistant/tool). Messages persist so users can scroll back and so we can run telemetry on what people ask.
- **UI:** Right-side collapsible panel in `themes/light/layouts/_account.html.erb`. Opens with `⌘K` or a chat icon in the top nav. Stimulus controller `agent_chat_controller.js` handles open/close + form submit + Cable subscription. Looks like the rest of the app — Geist Sans, hairline borders, orange accent.
- **Routes:** `resources :agent_conversations, only: [:index, :show, :create]` and nested `resources :messages, only: [:create]`. All under `/account/`.
- **Replacing existing panels:** Phase 4 of the implementation. Each existing AI panel (campaign drafter, segment translator, postmortem) grows an "Open in Agent" affordance that pre-fills a starter prompt. The bespoke panels keep working in parallel; we only retire them once telemetry says people prefer the agent.

### LLM configuration + gateway

Single source of truth: `Llm::Configuration` (PORO, reads from credentials + ENV). The existing `Rails.application.credentials.anthropic.api_key` is migrated to the new `llm:` namespace at install time; the initializer reads both during a deprecation window so a stale credentials file doesn't break boot.

```ruby
Llm::Configuration.current.usable?     # boolean
Llm::Configuration.current.provider    # :anthropic | :cloudflare | :openai_compatible
Llm::Configuration.current.base_url    # nil for native Anthropic, otherwise gateway URL
Llm::Configuration.current.api_key
Llm::Configuration.current.default_model
```

Credentials shape:

```yaml
llm:
  provider: anthropic                # or cloudflare, openai_compatible
  api_key: sk-ant-xxx
  base_url: https://gateway.ai.cloudflare.com/v1/<account>/<gateway>/anthropic   # optional
  default_model: claude-sonnet-4-6
```

`config/initializers/ruby_llm.rb` is rewritten to read from `Llm::Configuration.current`, set the base URL when present, and tolerate absence (no key → no configuration calls, app boots fine).

`AI::Base#stub_mode?` is rewritten to delegate to `Llm::Configuration.current.usable?` so all three predicates (the in-app agent, the existing AI services, the LLM-backed MCP tools) use the same definition.

We do not (yet) build a per-team LLM configuration UI. That's a follow-up; for v1 the platform operator configures one set of credentials. The shape of `Llm::Configuration` accepts a `team:` argument so a per-team override layer can drop in later without rewriting callers.

### Telemetry

- Every MCP tool call logs (Rails.logger.tagged) `[mcp]` with: `team_id`, `tool_name`, `client_name`, `client_version`, `latency_ms`, `success`. Line-oriented so future-us can grep / pipe to a real sink.
- Every agent turn logs `[agent]` with: `conversation_id`, `team_id`, `tool_calls_count`, `total_tokens`, `latency_ms`.
- Skill loads log `[mcp.skill]` with `skill_name`, `team_id`.

Persisted analytics (an `agent_invocations` table or similar) is a Phase 5 add — not v1.

## Failure / degradation matrix

| Condition | MCP raw tools | MCP LLM tools | In-app agent |
|---|---|---|---|
| No LLM credentials | ✅ work | ❌ structured "LLM not configured" error | UI shows "Configure your LLM key" CTA, no chat input |
| LLM credentials present, gateway URL set | ✅ work | ✅ routed via gateway | ✅ routed via gateway |
| LLM call fails mid-turn | n/a | tool returns error JSON to caller | agent surfaces error in stream + persists with `error` role |
| Token invalid | 401 from middleware | 401 | n/a (uses session) |
| Tool authorization fails (CanCan) | tool returns `{"error": "forbidden"}` JSON-RPC error | same | agent surfaces "I don't have permission to do that" |

## Out of scope (deliberately)

- **Per-team LLM config UI.** Shape is ready; UI ships later when a second tenant is onboarded.
- **OAuth flow for MCP.** v1 uses Doorkeeper Bearer tokens (same as today's IK integration). Full OAuth 2.1 dynamic client registration per the latest MCP spec is a later add — once we have an external developer asking for it.
- **Replacing the bespoke AI panels.** Phase 4 cross-links to the agent. Removal is gated on telemetry.
- **MCP prompts (the third primitive).** We ship tools + resources only. Prompts are a slot we'll fill once we know what users actually want pre-canned.
- **Agent memory across conversations.** Each conversation is independent. Cross-conversation memory is a separate design.
- **Public MCP server URL doc / discovery manifest.** Will need a `.well-known/mcp.json` and a public README for external developers; handled in a documentation pass after v1 lands.

## Phases for the implementation plan

The implementation plan (next step, via writing-plans) will sequence these:

1. **Chassis** — `fast-mcp` gem, Rack mount, Doorkeeper auth middleware, `Mcp::Tool::Base` + loader, one trivial tool (`team.get_current`) wired end-to-end with a passing test.
2. **Raw tools** — port the rest of the API surface. One tool file per action. Tests scope tools to the token's team.
3. **Skills** — `Mcp::Skill::Loader`, six initial skills, ERB live-context rendering, integration test that lists + reads each.
4. **LLM gateway + LLM tools** — `Llm::Configuration`, rewritten `ruby_llm.rb` initializer, three `llm.*` MCP tools wrapping the existing services. Migration: `AI::Base#stub_mode?` delegates to `Llm::Configuration#usable?`.
5. **In-app agent** — `AgentConversation` + `AgentMessage` models + migration, `Agent::Runner`, `AgentChannel`, controllers + routes, Stimulus controller, panel partial in `themes/light/layouts/_account.html.erb` (ejected partial — minimal change, follows DESIGN.md).
6. **Cross-link existing panels** — "Open in Agent" affordance on campaign drafter, segment translator, postmortem. Pre-filled starter prompts.

Each phase is independently shippable. Subagent parallelism: phases 2 and 3 can run concurrently (independent files). Phase 4 must precede 5 (agent reads `Llm::Configuration`). Phase 6 strictly last.

## Decisions worth flagging for the reviewer

1. **`fast-mcp` over the official `mcp` gem.** Rack-mountable, has Rails generator support, batteries-included for streamable HTTP. The official gem is more aligned with stdio/CLI use cases. Reversible — both implement the same protocol.
2. **One LLM config (not per-team) for v1.** Per-team is cleaner long-term but UI surface for v1 isn't worth it while we still have one tenant. The shape allows per-team to drop in later.
3. **In-app agent uses `ruby_llm` directly, not the MCP HTTP roundtrip.** Same tool registry, two callers (HTTP for external, in-process for the in-app agent). Avoids HTTP overhead for in-process use; tools must therefore be designed to be safely callable without a Rack stack (which they are — they take a context object, not `request`).
4. **Skills are ERB-rendered per-request, not statically loaded.** Pays off for `segment-cookbook.md` and `voice-samples.md` which are useless without the team's data. Cost: a tiny render at resource-read time. Worth it.
5. **`agent.tool_call` events streamed visibly.** The agent narrates what it's doing ("Looking up your last campaign... Drafting subject candidates... Sending a test to bruno@..."). This is both UX (trust) and debugging (we can see when it goes off the rails).
