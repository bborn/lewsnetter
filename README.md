# Lewsnetter

> Open-source email marketing for the agent era. Draft, segment, send, analyze — by chat, by API, or by hand.

Lewsnetter is a self-hostable email campaign platform that ships with a built-in agent and a [Model Context Protocol](https://modelcontextprotocol.io) server. Tell the agent what you want — *"draft a release-notes email for the brand-tier audience"* — and it uses the same API any external tool can. No bespoke automations, no scripting, no copy-paste between tabs.

Built on Rails 8 + [BulletTrain](https://bullettrain.co). MIT licensed.

## What it does

- **Author with markdown + [Liquid](https://shopify.github.io/liquid/).** Write a campaign body in markdown, drop in `{{ first_name | default: "there" }}` placeholders, render through a reusable MJML template that owns the chrome (header, footer, unsubscribe link).
- **Send via your own AWS SES.** Per-team SES credentials. You control deliverability, bounces flow back via SNS webhooks. No middle-man sender.
- **Segment with plain SQL or natural language.** Predicates against subscriber + company custom_attributes (`json_extract(...)` over a JSON column). The built-in agent translates "brand-tier customers active in the last 30 days" into a safe predicate.
- **Talk to it like a teammate.** A built-in chat panel powered by `ruby_llm` + Anthropic Claude. Streaming responses, tool-use loop, full conversation memory. Works with any LLM provider that ruby_llm supports.
- **Or talk to it from anywhere.** MCP server at `/mcp/messages` with [OAuth 2.1 dynamic client registration](https://datatracker.ietf.org/doc/html/rfc7591). Connect Claude Desktop, Cursor, Codex — they auto-register, the user signs in, and the agent has the same tools the in-app chat does.

## Hosted vs self-hosted

| | Cloud (coming) | Self-hosted |
|---|---|---|
| **Setup** | Sign up, add SES creds | One Hetzner box + Kamal deploy (~20 min) |
| **Updates** | Continuous | Pull from `main` + `kamal deploy` |
| **AI** | Bring your own Anthropic key, or use the included quota | Bring your own Anthropic key |
| **MCP server** | Same `/mcp` endpoint | Same `/mcp` endpoint |
| **Pricing** | Per-team monthly | Free (you pay AWS + your VPS) |
| **Support** | Bruno + community | Community |

The hosted version is a thin convenience layer over the same OSS code. Everything that ships in this repo runs on the cloud version.

## Quick start (self-host)

You need:
- A Linux box (1 CPU / 2 GB RAM is fine for low traffic; e.g. Hetzner CPX21)
- A domain pointed at it
- An AWS account with SES enabled in your region
- An Anthropic API key (optional — the agent + LLM tools don't run without it; everything else does)

Then, on your laptop:

```sh
git clone https://github.com/bborn/lewsnetter.git
cd lewsnetter
bin/setup                                    # installs Ruby/Node/SQLite deps
EDITOR=vim bin/rails credentials:edit        # add llm.api_key + ses creds (see AGENTS.md)
echo "<your-server-ip>" > .kamal/SERVER_HOST
bundle exec kamal setup                      # first deploy: sets up Docker, Traefik, your app
```

About 20 minutes later, your app is live. Visit `https://your-domain.com`, sign in as the first user (auto-promoted to admin), and send your first campaign.

Production reference: `config/deploy.yml` is heavily commented (Litestream replication to R2, per-tenant SES, Cloudflare proxy), and `.github/workflows/deploy.yml` documents the secret matrix.

## Quick start (development)

```sh
bin/setup     # installs deps + creates dev DB
bin/dev       # boots Puma, Solid Queue, esbuild --watch, Tailwind --watch
```

Visit http://localhost:3000. First user is auto-admin.

## Connect an MCP client

Once deployed, point any MCP-aware tool at `https://your-domain.com/mcp/messages`. The server supports OAuth 2.1 dynamic client registration, so clients self-register and the user authorizes via the standard browser flow.

For Claude Desktop, in `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "lewsnetter": {
      "transport": {
        "type": "http",
        "url": "https://your-domain.com/mcp/messages"
      }
    }
  }
}
```

Restart Claude Desktop, invoke any tool, and it'll walk you through the auth flow.

The MCP server exposes 43 tools spanning subscribers, segments, email templates, campaigns, sender addresses, events, plus three LLM-backed tools (`llm_draft_campaign`, `llm_translate_segment`, `llm_analyze_send`) that wrap the in-app AI services. Full surface in [`docs/superpowers/specs/2026-05-15-mcp-and-in-app-agent-design.md`](docs/superpowers/specs/2026-05-15-mcp-and-in-app-agent-design.md).

## Stack

- **Rails 8.1** on Ruby 4
- **SQLite** primary + queue + Cable, [Litestream](https://litestream.io) → Cloudflare R2 backup
- **[BulletTrain](https://bullettrain.co)** for teams, Devise auth, CanCanCan, billing scaffolding
- **AWS SES v2** (`aws-sdk-sesv2`) for sending; per-team credentials
- **MJML** for responsive email templates; **Liquid** for body interpolation
- **`ruby_llm`** for the in-app chat agent (acts_as_chat, tool loop, streaming)
- **`fast-mcp`** for the MCP server (Streamable HTTP, mounted at `/mcp`)
- **Doorkeeper** for OAuth 2.1 (BulletTrain ships it; we add dynamic client registration on top)
- **Hotwire** (Turbo + Stimulus), **Tailwind**
- **[Kamal 2](https://kamal-deploy.org)** + GHCR for deploys

LLM provider: anything `ruby_llm` supports (Anthropic by default). Optional [Cloudflare AI Gateway](https://developers.cloudflare.com/ai-gateway/) for caching, observability, and BYOK key isolation — see [`config/initializers/cloudflare_ai_gateway.rb`](config/initializers/cloudflare_ai_gateway.rb).

## For AI agents

Agents driving this repo (Claude Code, Cursor, Codex, etc.) should read [`AGENTS.md`](AGENTS.md) first — it has the conventions, common commands, deploy procedure, and pointers to the specs/plans an agent needs to be productive.

If you point an agent at this repo and say "deploy this," it should be able to. If it can't, that's a bug in `AGENTS.md` — please open an issue.

## Status

Pre-1.0 but in production. Bruno is tenant zero — InfluenceKit's brand newsletter (~10k subscribers) ships through Lewsnetter every week. The app works end-to-end; expect rough edges.

The 2014 codebase that previously lived at this name is archived on [`legacy-2014`](https://github.com/bborn/lewsnetter/tree/legacy-2014).

## License

MIT — see [`MIT-LICENSE`](MIT-LICENSE). Inherits BulletTrain's MIT license.
