# AGENTS.md

Instructions for AI coding agents (Claude Code, Cursor, Codex, etc.) working on this repo. Humans should read [`README.md`](README.md) instead.

## What this app is

Lewsnetter is an open-source email marketing platform on Rails 8 + BulletTrain, with a built-in MCP server and an in-app agent. The agent (powered by `ruby_llm`'s `acts_as_chat`) and external MCP clients share the same tool registry — anything the agent can do, an external client can do via `/mcp/messages`.

The fastest way to grok the architecture: read the design spec at [`docs/superpowers/specs/2026-05-15-mcp-and-in-app-agent-design.md`](docs/superpowers/specs/2026-05-15-mcp-and-in-app-agent-design.md). It's the source-of-truth for "why is it built this way."

## Codebase map

| Path | What's there |
|---|---|
| `app/mcp/` | MCP server: `Mcp::Server`, `Mcp::Tool::Base`, `Mcp::DoorkeeperAuth`, all 43 tools under `tools/<group>/<verb>.rb`, 6 markdown skills under `skills/` |
| `app/services/llm/configuration.rb` | Single source of truth for LLM keys/base URL/provider. All AI code reads this. |
| `app/services/chats/tool_adapter.rb` | Bridges `Mcp::Tool::Base` → `RubyLLM::Tool` for the in-app agent (so external MCP and in-app agent share one tool surface). |
| `app/services/ai/` | Three task-specific AI services (campaign drafter, segment translator, post-send analyst). The `llm_*` MCP tools wrap these. |
| `app/services/campaign_renderer.rb` | Renders a campaign body for one subscriber: Liquid substitution → markdown → MJML → HTML → premailer-inlined. |
| `app/channels/chat_channel.rb` | ActionCable channel for the in-app agent. Streaming + tool indicators. |
| `app/models/{chat,message,tool_call,model}.rb` | `acts_as_chat` from `ruby_llm`. Don't add custom logic here unless necessary. |
| `app/controllers/well_known_controller.rb` | OAuth 2.1 RFC 8414 + 9728 metadata endpoints. |
| `app/controllers/oauth/registrations_controller.rb` | RFC 7591 dynamic client registration for MCP clients. |
| `config/initializers/ruby_llm.rb` | LLM key + gateway URL wiring. |
| `config/initializers/cloudflare_ai_gateway.rb` | Optional CF AI Gateway BYOK support. Self-contained — copy to support a different gateway. |
| `config/deploy.yml` | Kamal 2 production deploy config. |
| `initiatives/lewsnetter-v2/SESSION-HANDOFF-2026-05-14.md` | Latest "where we left off" notes. Read this if you need historical context for ongoing work. |
| `docs/superpowers/specs/` | Design specs (the why). |
| `docs/superpowers/plans/` | Implementation plans, phase by phase (the how). |

## Setup

```sh
bin/setup       # installs Ruby/Node/SQLite/Redis/Chrome (macOS uses Homebrew)
bin/dev         # starts Puma, Solid Queue worker, esbuild --watch, Tailwind --watch
```

`bin/dev` uses `overmind`. If you see `overmind: it looks like Overmind is already running`, either tail the existing one (`overmind connect`) or kill it: `pkill -9 -f overmind && rm -f .overmind.sock`.

Default dev user: `qa@local.test` / `password123`.

## Tests

```sh
bin/rails test                          # everything
bin/rails test test/mcp/                # MCP-specific
bin/rails test test/services/           # service objects (incl. CampaignRenderer)
bin/rails test test/system/             # Capybara/Chrome system tests
```

Pre-existing failures (don't introduce more, don't fix as part of unrelated work):
- `test/controllers/api/v1/subscribers_controller_test.rb` — missing `:subscriber` factory
- A handful of BulletTrain scaffolded `tangible_things` controller tests
- See `initiatives/lewsnetter-v2/SESSION-HANDOFF-2026-05-14.md` § "Operational fragilities" for the full list.

## Conventions

- **Commits:** Short imperative subject (`feat(mcp): ...`, `fix(agent): ...`, `docs: ...`). Body explains *why*, not what (the diff shows what). Co-author trailer is fine.
- **Branching:** Bruno's flow is master-direct. Feature branches OK for big work, but merge with `--ff-only` to keep history linear. Push to master triggers GH Actions deploy via Kamal.
- **No `git push --force-with-lease` to master** without explicit user instruction.
- **Don't skip pre-commit hooks** (`--no-verify`). If a hook fails, fix the underlying issue.
- **Design system:** Read [`DESIGN.md`](DESIGN.md) before any visual change. Don't deviate without approval.
- **Models registry:** `bin/rails ruby_llm:load_models` seeds the ~1,250-row LLM model registry. The prod entrypoint (`bin/docker-entrypoint`) auto-seeds on first boot when `Model.count == 0`. In dev, run it manually after a fresh `db:prepare`.

## MCP tool development

Adding a new tool? Convention:
1. Create `app/mcp/tools/<group>/<verb>.rb` subclassing `Mcp::Tool::Base`.
2. Declare `tool_name` (snake_case, `<group>_<verb>` — fast-mcp strips dots), `description`, `arguments_schema` (JSON Schema).
3. Implement `call(arguments:, context:)`. **Always scope to `context.team`** — never bare `Model.find(id)`. Use `find_by!(id: ...)` (BulletTrain's `ObfuscatesId` overrides `.find` with URL-style obfuscation; MCP clients send raw integers).
4. Return a JSON-serializable hash (symbol keys OK; the wrapper JSON-encodes).
5. Add a test at `test/mcp/tools/<group>/<verb>_test.rb` covering happy path, team-scoping, and one error case.

The tool is auto-loaded by `Mcp::Tool::Loader` at boot; no manifest to update.

## Deploy

Production runs Kamal 2 on a single Hetzner CPX21 in Ashburn (`178.156.185.100`). Container image is `bborn/lewsnetter` on GHCR.

```sh
git push origin master       # triggers .github/workflows/deploy.yml
# OR manually:
eval "$(mise activate bash)" && bundle exec kamal deploy
```

Deploys take 6–7 minutes. Tail with `gh run list --workflow Deploy --branch master --limit 1`.

After a major dependency or migration change, you may need to re-seed the LLM model registry on prod:

```sh
ssh -i ~/.ssh/lewsnetter_deploy root@178.156.185.100 \
  "cid=\$(docker ps -q -f name=lewsnetter-web | head -1); docker exec \$cid bin/rails ruby_llm:load_models"
```

If the user says "deploy this," the procedure is: run tests locally, commit, push to master, watch the workflow, smoke `/mcp/messages` (`POST` with a Doorkeeper token + `{"jsonrpc":"2.0","id":1,"method":"tools/list"}`) and the agent panel after it lands.

## Credentials

Edit:

```sh
EDITOR=vim bin/rails credentials:edit
```

Expected shape:

```yaml
llm:
  provider: anthropic                # or "cloudflare" if using AI Gateway
  api_key: sk-ant-...
  default_model: claude-sonnet-4-6
  base_url: https://gateway.ai.cloudflare.com/v1/<acct>/<gw>/anthropic   # optional
  cf_aig_token: cfut_...                                                 # optional, for CF gateway BYOK

anthropic:
  api_key: sk-ant-...   # legacy fallback (Llm::Configuration reads either)

system_mail:
  access_key_id: AKIA...
  secret_access_key: ...
  region: us-east-1
  from: system@yourdomain.com

cloudflare:
  r2_uploads:
    access_key_id: ...
    secret_access_key: ...
    bucket: ...
    endpoint: https://<acct>.r2.cloudflarestorage.com
```

Per-team SES creds are stored in `Team::SesConfiguration` (Rails 7 `encrypts`), not in `credentials.yml.enc`.

## Common operations

```sh
# Mint an MCP token for a user (e.g. for Claude Desktop manual config)
bin/rails runner '
  user = User.find_by!(email: "you@example.com")
  app  = Platform::Application.find_or_create_by!(name: "MCP — manual") do |a|
    a.user = user; a.team = user.current_team
    a.uid = SecureRandom.hex(8); a.secret = SecureRandom.hex(16)
    a.redirect_uri = "urn:ietf:wg:oauth:2.0:oob"
  end
  print Doorkeeper::AccessToken.create!(
    resource_owner_id: user.id, application: app,
    scopes: "read write delete", token: SecureRandom.hex
  ).token
'

# Inspect the live MCP tool registry
curl -s -X POST https://your-domain.com/mcp/messages \
  -H "Authorization: Bearer <token>" -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | jq '.result.tools | length'

# Watch agent telemetry on prod
ssh root@<server> 'docker logs lewsnetter-web 2>&1 | grep "\[mcp\]\|\[chat\]\|\[agent\]"'
```

## Hard rules

- **Never send a real campaign without explicit human authorization.** The agent has a `campaigns_send_now` tool. If the user is testing or exploring, suggest `campaigns_send_test` (sends one to themselves) instead.
- **Never push to `master` with failing CI tests** unless the user explicitly says to (and you've explained why CI is failing).
- **Never edit `db/schema.rb` directly** — generate a migration and run it.
- **Never bake secrets into committed files.** Credentials go in `config/credentials.yml.enc`. ENV vars on prod go in `~/.kamal/secrets`.
- **Never delete migrations after they've shipped to prod.** Add a new one to undo.

## Where to ask for help

- Architecture questions: read the spec in `docs/superpowers/specs/`.
- "Why was this built this way": check git blame and the corresponding plan doc in `docs/superpowers/plans/`.
- Operational state: `initiatives/lewsnetter-v2/SESSION-HANDOFF-2026-05-14.md`.
- Stuck: open an issue, ping Bruno.
