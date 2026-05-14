# Lewsnetter v2 — Session Handoff (2026-05-14)

Two-day deep session. State of the app at the end + the things future-you (or another agent) needs to know to pick up cleanly.

---

## What Lewsnetter is

AI-native email marketing SaaS on BulletTrain. Replaces Intercom for InfluenceKit's marketing emails. Live at https://lewsnetter.whinynil.co. Today's flagship use case: send a "Brands Newsletter" to ~745 brand-tenant users at IK.

---

## Production state

| | Value |
|---|---|
| URL | https://lewsnetter.whinynil.co |
| Host | Hetzner CPX21 in Ashburn (`178.156.185.100`) |
| Deploy | Kamal 2 + kamal-proxy + GHCR. CI: GH Actions on push to master. |
| DB | SQLite (primary + queue + cable, separate files). Litestream → Cloudflare R2 backup. |
| Active Storage | Cloudflare R2 (S3-compatible). Public reads via Rails proxy URLs (non-expiring). |
| TLS | Cloudflare Full (Strict). Origin CA cert on kamal-proxy. Cert SANs: `*.whinynil.co`, `whinynil.co`, `lewsnetter.whinynil.co`. (Does NOT cover `email.influencekit.com` — that subdomain still on Flexible.) |
| Marketing SES | Per-team via `Team::SesConfiguration` (Rails 7 `encrypts`). Team #1's SES is verified for `influencekit.com` domain. |
| System mail | AWS SES v2 via `aws-actionmailer-ses`. Credentials in `Rails.application.credentials.system_mail`. From: `system@influencekit.com`. Used for Devise password reset, invitations. |
| Admin user | `bruno@influencekit.com` on Team #1 "InfluenceKit". Devise password (Bruno knows). |

### Key prod IDs (Team #1)

- `EmailTemplate#2` — "InfluenceKit Brand Newsletter" (has logo asset attached, #FF6666 links, `{{body}}` placeholder chrome)
- `Segment#1` — "Brand-company users (Intercom-defined)" — predicate `json_extract(companies.custom_attributes, '$.tenant_type') = 'brand'`. 982 matching, **745 subscribed-and-not-bounced** (today's send target).
- `Campaign#3` — "5/7/26 Newsletter - Brands" — draft. Body: verbatim Intercom content. CTAs use `{{subdomain}}.influencekit.com/<path>` for per-tenant deep links. Real IK paths (signals/mentions, saved_influencers, tokens, reports, brand_discovery) + calendar.influencekit.co for booking.
- `SenderAddress#1` — `team@influencekit.com` (InfluenceKit) — verified via domain identity.

---

## Today's send-readiness

Campaign #3 is **ready to send** modulo Bruno's last visual review. From me: 0 blocking TODOs. From Bruno: eyeball preview + send test + send preview-as a real subscriber + click "Send to 745 subscribers".

---

## Architectural decisions worth remembering

1. **SQLite over Postgres** — Rails 8 SQLite-first, single-file deploy, Litestream backup. Deliberate deviation from BulletTrain's Postgres default.
2. **Per-team SES, NOT global SES** — `Team::SesConfiguration` carries each tenant's AWS creds, region, SNS topic ARNs, config set, unsubscribe host. Marketing email goes out via the tenant's SES. (System mail uses a separate global AWS account; see Future Work.)
3. **No gem in IK** — we built and then deleted `lewsnetter-rails`. Path-vendoring was friction; single-publisher case doesn't justify package overhead. Going forward: HTTP API contract (`POST /api/v1/teams/:team_id/subscribers/bulk`, NDJSON, idempotent on external_id). When IK pushes, it uses a thin service module, not a gem.
4. **Subscriber + Company are separate models** — added 2026-05-13. Each Subscriber `belongs_to :company` (nullable). Companies carry company-level custom_attributes from Intercom. Segments can predicate on `companies.<column>` and the model auto-joins. Critical: without this, we were matching one user per company (~185) instead of all seats (~745) for brand audience.
5. **Markdown body + MJML template split** — campaigns author in markdown (compiled via commonmarker SAFE), templates carry MJML chrome. Template's `{{body}}` placeholder gets filled with the markdown→MJML body section. Authors don't touch MJML for content; only for template-level layout work.
6. **Substitute markdown BEFORE compiling** — `{{var}}` placeholders are substituted in the markdown source first, then commonmarker runs. Required because commonmarker URL-encodes `{` and `}` in hrefs (e.g. `[link](https://{{subdomain}}.foo.com)` would otherwise ship as `%7B%7Bsubdomain%7D%7D.foo.com`).
7. **Doorkeeper Platform::AccessToken for API auth** — vanilla BulletTrain Platform tokens. Token id=2 for "IK integration" application, plaintext stashed at `~/.config/lewsnetter-ik-token` on Bruno's machine (mode 600).

---

## Recently shipped (this session) — chronological-ish

- BulletTrain QA round 2 (F4-F13): subscriber show page rebuilt, campaign show recipient count + preview, imports columns, onboarding placeholder, AWS key masking, MJML textarea polish, subscribed checkbox.
- Usability overhaul (33 findings): state-aware Send buttons, sectioned campaign form, status pills, branded unsubscribe page, sender-address verify action, segment translate result panel, ejected `themes/light/fields/_field.html.erb` for required/optional markers, branded 404.
- Deep QA round 3 (21 findings): subscribers locale crash fixed, custom Stimulus controllers compiling into the JS bundle (the glob import was silently emitting empty when easymde was missing), CSV import unblocked, "Scheduled For" input fixed, Email Sending labels, SenderAddress email format validation, duplicate empty-state button dedupe, "render_failed:" prefix stripped from flash errors.
- Campaign edit: EasyMDE markdown editor + live preview iframe (debounced POST) + working AI drafter + plain HTML selects for segment/sender/template.
- System mail via SES (`aws-actionmailer-ses`, gem already in Gemfile).
- Intercom import pipeline: `migrations:import_from_intercom` (10,381 contacts), `migrations:enrich_tabs_enabled`, `migrations:import_companies_from_intercom` (9,150 companies), `migrations:link_subscribers_to_companies` (9,528 linked).
- Company model: `Company` belongs_to team, has_many subscribers. Subscriber belongs_to company optional. Segment#applies_to auto-joins `:company` when predicate references `companies.`.
- Authoring polish: search-ahead Preview-as typeahead, variable picker with built-ins + custom_attributes + sample values, `{{key|fallback}}` interpolation syntax, "Send preview as <subscriber>" action that renders with another subscriber's data and delivers to the author's inbox.
- CodeMirror 6 editor for MJML template source (line numbers, XML highlighting, bracket matching).
- Asset uploads (`has_many_attached :assets`) on EmailTemplate + Campaign. Thumbnail + URL + Copy + Delete in the form. Uses `rails_storage_proxy_url` for non-expiring public URLs.
- Template show page now renders a preview iframe instead of dumping raw MJML.
- All CTA URLs in Campaign #3 fixed against real IK routes (verified by grepping `/Users/bruno/Projects/rails/influencekit/config/routes.rb`).

---

## Known gaps / future work

### High priority (do before opening Lewsnetter to other tenants)

1. **Dedicated transactional provider for system mail.** Today system mail reuses Team #1's SES creds. If we open to other tenants, system mail should move to its own Postmark account so a tenant's SES misconfiguration can't break account flows.
2. **IK → Lewsnetter push pipeline.** Today we one-shot imported from Intercom. New IK users won't appear in Lewsnetter unless we re-run the import. The right pattern: thin `app/services/lewsnetter_client.rb` in IK + after_commit on User → push delta via HTTP API.
3. **The "Brand/Agency" segment is just `tenant_type = 'brand'`.** IK doesn't have an `agency` tenant_type today (only `brand`, `events`, `talent_manager`). Worth a conversation with Bruno about whether the audience should include talent_managers.

### Medium priority

4. **Image upload inside the editor.** Today: upload asset → copy URL → paste into MJML. Better: asset picker dropdown next to the variable picker, click an asset → insert `<mj-image src="..." />` at cursor.
5. **Authlogic touch noise.** IK's User model touches `last_request_at` on every authenticated request. If we wire ongoing sync from IK, every page load fires a sync job. Need a debounce/relevant-fields filter in the IK service module.
6. **Template-level vs. campaign-level asset reuse.** Templates and campaigns have separate `has_many_attached :assets` collections. A logo uploaded on a template isn't visible from a campaign editor. Should asset picker surface BOTH the template's + the campaign's assets?
7. **Per-team unsubscribe subdomain CNAME ops.** Each tenant configures `Team::SesConfiguration#unsubscribe_host`; we render unsubscribe URLs against that host. Kamal-proxy has multi-host wildcard, but adding a new host today requires editing `config/deploy.yml` + redeploy. Long-term we'd want a data-driven kamal-proxy config OR an Origin CA cert with wildcard SANs.
8. **Anthropic API key cleanup.** `Rails.application.credentials.anthropic.api_key` is set. `RubyLLM.config.anthropic_api_key` reads it. The stub-mode check in `AI::Base#stub_mode?` evaluates correctly in prod (real LLM fires). Worth making the initialization more obvious so future-you doesn't doubt it.

### Operational fragilities discovered this session

- **CI deploys flake on GHCR auth occasionally.** Re-running the failed step usually works. Symptom: `docker stderr: Get "https://ghcr.io/v2/": context deadline exceeded`.
- **Pre-existing BulletTrain scaffolded test failures** in `test/controllers/account/scaffolding/completely_concrete/tangible_things_controller_test.rb`. Not blocking deploy, but the suite isn't clean.
- **Factory gaps**: `:subscriber`, `:segment`, `:campaign` factories aren't registered. Several controller tests skip or error.
- **Local + prod password mismatch**: `qa@local.test` / `password123` for local QA. Bruno's password on prod is whatever he set.
- **Classifier flakes on git push to master + production writes.** Mostly recoverable by re-running with the script content visible inline OR Bruno pasting commands manually.

---

## Operational quick-reference

### Deploy

```
git push origin master   # triggers GH Actions
# OR manual:
eval "$(mise activate bash)" && bundle exec kamal deploy
```

### Run a rails runner on prod

The reliable way (shell-escaping inline runners is fighting Ruby):

```
ssh -i ~/.ssh/lewsnetter_deploy root@178.156.185.100 \
  'cid=$(docker ps -q -f name=lewsnetter-web | head -1); docker exec $cid bin/rails runner "RUBY_HERE"'
```

For multi-line scripts: write to `/tmp/foo.rb`, scp it, `docker cp` it, `docker exec runner`. See `/tmp/audit.rb` examples in the session.

### Intercom re-import (if data drifts)

```
# Get the IK Intercom token from /Users/bruno/Projects/rails/influencekit/config/initializers/intercom.rb (INTERCOM_CLIENT constant).
INTERCOM_TOKEN=<token-from-IK> TEAM_ID=1 bin/rails migrations:import_from_intercom
# then:
INTERCOM_TOKEN=... TEAM_ID=1 bin/rails migrations:import_companies_from_intercom
# then:
INTERCOM_TOKEN=... TEAM_ID=1 ONLY_NULL_COMPANY=true bin/rails migrations:link_subscribers_to_companies
```

All three are idempotent on external_id / intercom_id.

### Secrets locations

- `~/.kamal/secrets` on Bruno's machine (mode 600) — `KAMAL_REGISTRY_PASSWORD`, `RAILS_MASTER_KEY`, `LITESTREAM_REPLICA_*`, `ORIGIN_CERT`, `ORIGIN_KEY`
- `~/.config/lewsnetter-ik-token` on Bruno's machine (mode 600) — Platform::AccessToken for the IK integration (not used today since we dropped the gem; kept for the eventual push pipeline)
- `config/credentials.yml.enc` (committed encrypted) — `anthropic.api_key`, `cloudflare.r2_uploads.*`, `system_mail.{access_key_id,secret_access_key,region,from}`
- GitHub Actions secrets (set via gh secret set) — `KAMAL_REGISTRY_PASSWORD`, `RAILS_MASTER_KEY`, `LITESTREAM_REPLICA_*`, `ORIGIN_CERT`, `ORIGIN_KEY`, `SSH_PRIVATE_KEY`, `SERVER_HOST`

### Bruno's preferences (from the session)

- "Stay close to vanilla BulletTrain. Eject only when you really need to." — minimize custom partials.
- Wants parallelism when work is genuinely independent ("just make them all go"), but had to course-correct the parallel-implementer pattern when worktrees + concurrent commits caused mess.
- Wants real product feel, not raw CRUD. Voice should be humane, not column-name-y. State-aware actions. No dead buttons.
- Convert relative dates to absolute when recording state.
- Don't ask if you can do destructive prod actions without explicit context; do show dry-runs first.

---

## Files / artifacts worth knowing about

- `initiatives/lewsnetter-v2/PLAN.md` — original PRD
- `initiatives/lewsnetter-v2/PLAN-FOLLOWUPS.md` — pre-this-session followup tasks
- `initiatives/lewsnetter-v2/IK_MIGRATION_STATUS.md` — IK integration status, gem-was-dropped note at top
- `initiatives/lewsnetter-v2/BOUNCE_VERIFICATION.md` — bounce simulator round-trip evidence
- `.gstack/qa-reports/usability-pass-2026-05-13.md` — 33-finding usability audit
- `.gstack/qa-reports/deep-qa-2026-05-13.md` — 21-finding deep QA (B1-B21)
- `lib/tasks/migrations.rake` — Intercom import + company linker
- `app/services/campaign_renderer.rb` — markdown → MJML → HTML pipeline (substitute happens early in markdown path)
- `app/javascript/controllers/markdown_editor_controller.js`, `code_editor_controller.js`, `variable_picker_controller.js`, `subscriber_search_controller.js`, `ai_drafter_controller.js`, `campaign_preview_controller.js`, `clipboard_controller.js`, `segment_translator_controller.js` — the Stimulus core of the authoring UX

---

## What we agreed NOT to do (yet)

- Connect Lewsnetter directly to IK's production DB (Bruno raised, agreed it's a Week 2 conversation)
- Build per-template logo upload as a first-class field (we have generic `has_many_attached :assets` instead — author pastes URLs)
- Extract `lewsnetter-rails` to its own gem repo (revisit when there are 2+ consumers)
- Replace MJML with a WYSIWYG block editor (overhead doesn't justify; markdown body + MJML template chrome is the split)
