# Architecture

The "why we built it this way" doc. For evaluators, contributors, and future-Bruno trying to remember.

## Stack

| Layer | Choice | Why |
|---|---|---|
| Framework | Rails 8.1 + [BulletTrain](https://bullettrain.co) 1.45 | Boring, fast, the team-multitenancy + admin scaffolding from BT is worth more than a custom framework. |
| Database | SQLite | One file per database, fast, no separate process to operate. Modern SQLite handles way more concurrent writers than the 2010-era takes suggest. |
| Backup | [Litestream](https://litestream.io) → Cloudflare R2 | Streams every WAL frame to R2 within seconds. Point-in-time restore. R2 has no egress fees. |
| Background jobs | Solid Queue (Rails 8 built-in) | Lives in SQLite, no Redis dependency. |
| WebSockets | Solid Cable | Same logic — no Redis. |
| Deploy | [Kamal 2](https://kamal-deploy.org) + kamal-proxy | One-box Docker with rolling deploys + TLS termination at the proxy. |
| Cache | None (yet) | Honest — Rails 8's solid_cache would be a fine addition; we haven't needed it. |
| Frontend | Server-rendered ERB + Stimulus + Turbo | No SPA, no build step beyond Tailwind compilation. |
| Email sending | Bring-your-own Amazon SES via [aws-sdk-sesv2](https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/SESV2/Client.html) | See "BYO-SES decision" below. |
| LLM | [ruby_llm](https://github.com/crmne/ruby_llm) + Anthropic Claude | Streaming + tool use + provider-swappable. |
| Agent protocol | [MCP](https://modelcontextprotocol.io) | The wedge. See "Agent-native principle" below. |
| Auth | Devise + Doorkeeper (OAuth 2.1 for MCP) | Devise for humans, Doorkeeper for agents. |
| Billing | bullet_train-billing + Stripe | Open-sourced by Bullet Train in 2026, dropped right in. |

## Data layout

Multi-tenancy lives at the **Team** level (BulletTrain convention). Every meaningful record (Subscriber, Campaign, Segment, EmailTemplate, SesConfiguration, etc.) `belongs_to :team` with team-scoped ability checks via CanCanCan.

Notable models:

- **`Team`** — top-level tenant. `has_many` everything.
- **`Subscriber`** — the email recipient. `email` + `name` are encrypted at rest via Rails 8 ActiveRecord Encryption (deterministic on email so we can query, non-deterministic on name). Custom attributes live in a JSON column for flexible segmentation via `json_extract`.
- **`Segment`** — saved query against subscribers + their custom_attributes. Predicate is parsed to safe SQL via a whitelisted operator dictionary. The AI agent uses the same predicate format.
- **`Campaign`** — markdown body + Liquid placeholders + an EmailTemplate (MJML chrome) + a Segment (audience) + a SenderAddress (from). Renders to HTML at send time.
- **`EmailTemplate`** — reusable MJML chrome. Variables like `{{ body }}` slot the campaign content in.
- **`Team::SesConfiguration`** — per-team AWS credentials, region, SNS topics, physical postal address. Credentials are encrypted at rest.
- **`Team::SesDomain`** — verified sending domains (DKIM tokens, verification status). One team can have many; the wizard UI assumes one for now.
- **`SenderAddress`** — a verified From address. Either auto-provisioned from a verified domain or per-address verified via SES email identity.

Encryption keys live in Rails credentials. Losing the master key means losing access to encrypted columns. Don't lose the master key.

## The agent-native principle

Every controller has an MCP tool counterpart. The pattern:

```
Controller (UI)   →   Service object   ←   MCP tool
                            ↓
                          Model
```

Both the UI and the MCP server call the same service objects. Both go through the same Pundit/CanCanCan abilities. Both produce the same audit trail. There is no "API mode" vs "agent mode" — they're the same code path.

This is intentional. The thesis: **AI agents will be the primary users of most software within a few years**, and apps designed UI-first will struggle to expose the same capabilities. By building the tools first and the UI second, we get parity for free.

Practically, this means:
- Every new feature ships with both a UI page AND an MCP tool. No exceptions.
- The MCP tools live at `app/mcp/tools/<domain>/<verb>.rb` — one file per tool, file IS the JSON schema + implementation.
- Service objects are the contract surface. Controllers and MCP tools are thin.

## The BYO-SES decision

Lewsnetter never sends email itself. Every campaign goes through the user's own Amazon SES.

**Pros:**
- Users own their sending reputation. No noisy-neighbor problem.
- $0.10 per 1,000 emails (SES pricing) beats any platform that bundles sending.
- We never see outbound mail content. Less of a juicy target if we get popped.
- GDPR processor relationship is direct (you ↔ AWS), not transitive.

**Cons:**
- Setup friction. 10 minutes to create an IAM user, paste keys, verify a domain.
- Users can't blame the platform for deliverability. They can also fix it without filing a support ticket.
- We carry no aggregate sending IP reputation that benefits new accounts.

The setup wizard (4 steps: credentials → domain → DNS → test) absorbs most of the friction. The DKIM CNAMEs flow shipped in 2026 handles the deliverability-critical step that most BYO-SES tools elide.

## Billing model

- One paid tier: **Pro** at $10/month per team. No subscriber-count scaling, no email-volume tiers.
- Free signup. The entire app — campaigns, subscribers, segments, MCP, API — is free.
- The paywall fires only when a team tries to **save Amazon SES credentials**. Until they connect SES, they can build out a full newsletter operation for free. Once they want to actually send, they need to subscribe.
- Operator accounts (`BILLING_EXEMPT_EMAILS` env var) bypass the paywall entirely.

The narrow paywall is deliberate. It lets us be generous with the free tier (use the app indefinitely, build segments, draft campaigns) while charging at the moment of real value capture (sending). It also means the hosted infrastructure costs are bounded — non-paying users don't send mail.

## Marketing + app split (hosted only)

The hosted Lewsnetter runs the marketing site at `lewsnetter.dev` and the app at `app.lewsnetter.dev`. Same Rails process, same Docker container — kamal-proxy routes based on hostname.

Why split:
- Marketing pages need OG tags + canonical URLs at the apex.
- App pages need a stable host for OAuth callbacks, unsubscribe links, MCP metadata.
- Cleaner mental model: `app.` for signed-in users, apex for visitors.

Gotchas:
- Cross-host redirects need `allow_other_host: true` in Rails 7+.
- Cookies must be set for the parent domain (`.lewsnetter.dev`) to share across hosts if you ever need cross-host sessions (we don't).
- Self-hosters running single-host deployments leave `APP_BASE_URL` env var unset and helpers fall back to same-host.

## Decisions we deliberately did NOT make

- **No native drip campaigns.** Agents drive sequences via MCP + cron. See `docs/mcp.md` for the recipe.
- **No analytics dashboard.** Basic open/click/bounce metrics on each campaign are there; rich cross-campaign analytics aren't built. Future work if users ask.
- **No transactional email.** Lewsnetter is for marketing/newsletter sends only. Transactional belongs in your app, via SES directly or a dedicated tool like Postmark.
- **No multi-domain sending UI per team.** The model supports it; the wizard doesn't. One sending domain per team is the assumed case.
- **No A/B subject line testing.** Build if customers ask.
- **No template marketplace.** EmailTemplates are user-owned MJML; we don't host shared ones.
- **No Pinpoint Journeys-style flowchart builder.** That's what MCP + agents are for.
- **No third-party integrations beyond Stripe.** No Zapier, no Segment, no Mixpanel. The MCP server + REST API are the integration story.

## Where to start reading

For a feature:
- Controller: `app/controllers/account/<resource>_controller.rb`
- Model: `app/models/<resource>.rb`
- View: `app/views/account/<resource>/`
- MCP tool: `app/mcp/tools/<resource>/<verb>.rb`

For SES:
- `app/services/ses/` — the integration. Eight files, each focused. Read `client_for.rb` first.
- `app/controllers/account/email_sending_setup_controller.rb` — the wizard.

For the agent layer:
- `app/mcp/server.rb` — entry point.
- `app/mcp/tools/` — the tool implementations.
- `app/services/llm/` — the in-app chat agent.

For deploy:
- `config/deploy.yml` — heavily commented. Most operational questions are answered here.
- `Dockerfile` — standard Rails Docker setup.

For billing:
- `config/models/billing/products.yml` — the plans.
- `app/controllers/concerns/billing/requires_subscription_for_ses.rb` — the paywall gate.
- `app/models/team.rb` `#billing_exempt?` — operator allowlist.

## Conventions

- Tests in Minitest (`test/`), not RSpec. BulletTrain convention.
- Service objects for anything non-trivial. Thin controllers, thin models.
- ERB templates over view components (BulletTrain convention; might revisit).
- Strong opinions on UX/copy live in `DESIGN.md`. Read before touching styling.
- Project planning notes (where Bruno keeps them) live in gitignored `initiatives/` or scratch files.

## Open questions / known weaknesses

- No request-level rate limiting (rack-attack would help)
- No global Sentry / error tracking wired up
- Devise confirmable is off (signups are open + confirmed by default)
- Solid Cable WebSocket auth is BulletTrain-default; agents using MCP don't need it but human chat panel does
- SQLite WAL contention is theoretically possible at very high write volume; we haven't hit it
- No CSP headers configured beyond Rails defaults
