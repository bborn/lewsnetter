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

---

## 2026-05-14 evening — full app design overhaul

Bruno: "literally every page needs to be reviewed and improved according to a coherent, modern, excellent design imperative." Did that. 20 commits beyond the original ask. Branch is ~21 commits ahead of `origin/master`, **nothing pushed yet** — Bruno will verify visually first.

### What shipped (in order)

**Foundation (4 commits)** — DESIGN.md + theme tokens + partial-ejection chrome.
- `d7dea01` apply Lewsnetter design system via BulletTrain theme (Tailwind primary palette → orange; `theme.rb` color → `:orange`; Geist Sans + Geist Mono loaded; `--lw-accent` tokens; badge restyle).
- `2f913f9` rebuild app chrome via BulletTrain partial ejections — `layouts/_account.html.erb` (kills the gradient body + bg-primary navbar), `_box.html.erb` (hairline border, no shadow, Geist title), `_title.html.erb` (Geist 28/600, no divider line), `menu/_logo` + `menu/_top` + `menu/_item` + `menu/_heading` + `menu/_subsection` + `menu/_account` + `menu/_user` (Lewsnetter wordmark + accent dot, text-first nav, white-card dropdowns, zinc-on-white). Also restructured `account/shared/_menu.html.erb` to flatten Dashboard + Campaigns and group Audience (Subscribers, Segments) + Sending (Templates, Senders) into dropdowns; Team Settings + Members moved into the avatar dropdown via `_user_items.html.erb`.

**Editorial moments (4 commits)** — campaign show / edit / template show / sender show.
- `6ef6c0c` campaign show editorial moment (designed by `compound-engineering:design:design-iterator`, 8 iterations). Hero eyebrow + 38px subject + tiered action row (`Send to N subscribers →` `.btn-xl` + `Send test` secondary + Preview-as input + ghost preview), orange confidence callout / amber warning callout, hairline-bordered Details card with mono-caps keys, framed Rendered preview iframe with byte size, state-aware sent collapse.
- `a02921d` campaign edit form rebuild (design-iterator, 10 iterations). Editorial header + sticky-action footer + four sectioned cards (AI Drafter / Content / Audience / Settings) + Assets section + locked banner for sent campaigns. Mono-caps form labels with quiet optional/required markers. AI Drafter has an orange-tinted card so it reads as a smart suggestion.
- `d3cb218` editorial template show + editorial sender show (mono caps `TEMPLATE · ID · N CAMPAIGNS USING THIS` eyebrow + 32px Geist name + Rendered preview card with byte count + MJML source disclosure; sender show has verification-card pattern that's primary when unverified / quiet recheck when verified + clean 2-col Details grid).

**Cross-cutting button + link system (1 commit)**
- `471f931` discoverable buttons + tone down default link color. `.button-secondary` was rendering as orange text with underline-on-hover (BulletTrain default); promoted globally to a hairline-bordered button (zinc text, white bg, hover-bg). Cascades to every Edit / Delete / Back / Cancel / Import on every page. `.button-light` for tertiary. `.button-smaller` for compact inline. `.button-danger` for destructive. Plus `<a>` default tone toned down: zinc-on-default, orange + underline on hover (was orange-everywhere). `.card-action` Mono caps class for card-header inline links like the dashboard "VIEW ALL" and campaign show "EDIT CAMPAIGN."

**Pills + attribute rendering (2 commits)**
- `4033f67` empty-state polish + eject `attributes/_base.html.erb` for mono-caps labels everywhere with `with_attribute_settings strategy: :label` — sender addresses, subscribers, segments, email templates.
- `d3cb218` (same as above) `subscribed_pill` helper: green Subscribed / neutral Unsubscribed / rose Bounced. Replaces "Yes/No" everywhere a subscriber's state is shown.

**Devise auth screens (1 commit)**
- `f5657af` rebuild devise auth screens per DESIGN.md (design-iterator, 8 iterations). Killed `bg-gradient-to-br from-secondary-200 to-primary-400`. Sign in / Sign up / Password reset / Accept invitation all share the same chrome now: Lewsnetter wordmark + accent dot above, hairline-bordered card with Geist 28/600 sentence-case title + Geist Mono 13 tagline, orange-600 full-width primary CTA, quiet zinc body links, "LEWSNETTER · AI-NATIVE EMAIL MARKETING" mono-caps footer.

**Empty states + index/show polish (4 commits)**
- `9966469` empty states + postmortem chrome — index pages (campaigns, subscribers, segments, senders), subscriber events, segment predicate, postmortem panel all share a `mono caps eyebrow + Geist heading + sentence + single CTA` pattern.
- `bafd3ce` emerald success flash alerts + mono caps custom_attributes — `_alert.html.erb` ejected, default tone emerald with mono caps "Done"/"Heads up"/"Error" eyebrow; subscriber `_custom_attributes` partial uses mono-caps key + Geist value + framed code block for hash/array.
- `6abb5cf` imports KPI strip + status pill mappings — `subscribers/imports/show.html.erb` rebuilt as a 5-cell KPI strip (Status pill + Processed/Created/Updated/Errors) with mono caps captions, plus a clearly rose-tinted error log table. `processing → warn`, `completed → success` added to `status_pill_helper`.
- `d482dd7` shared asset uploader chrome — zinc card, mono caps "Assets / Hosted images" eyebrow, hint about drag-and-drop, smaller danger Delete buttons. Replaces the stale dark-sky-blue chrome.

**Drag-and-drop image upload (1 commit)**
- `8ce784a` `POST /account/campaigns/:id/assets` upload endpoint + EasyMDE `imageUploadFunction` binding. Drop a file in the markdown body, paste from clipboard, or click the toolbar image button → uploads to Active Storage / R2 → inserts `![name](url)` at cursor. Disabled on `/campaigns/new` (no campaign yet).

**Public-facing screens (2 commits)**
- `62ecf64` brand public error pages + unsubscribe to design system — 404 / 422 / 500 with Lewsnetter wordmark, mono-caps eyebrow, Geist Sans heading, orange-600 CTA. Unsubscribe public layout: zinc instead of slate, orange accent dot, mono-caps footer "POWERED BY LEWSNETTER," zinc → orange-on-hover re-subscribe link.
- `74997a1` 422 error page to match (separate commit because the first write got skipped).

**Polish (3 commits)**
- `9c53f98` campaign list row mono+tabular treatment.
- `37bb3d5` AI translator panel — orange-tinted intentional feel (matches the campaign-show confidence callout).
- `bad6597` email template form variables disclosure — zinc card with mono-caps `AVAILABLE VARIABLES` eyebrow, Show/Hide affordance, mono variable names in zinc-900 so they pop, MJML docs link toned to zinc-on-default.
- `6ba084a` gitignore root-level QA pngs + `.gstack`.

### Cross-cutting helpers / partials worth knowing about

| | What it does | Where |
|---|---|---|
| `.button` | Primary CTA, orange-600 | application.css |
| `.button-secondary` | Hairline-bordered secondary, zinc text | application.css |
| `.button-light` | Ghost: transparent, no border | application.css |
| `.button-danger` | Stacks on -secondary, red text + border | application.css |
| `.button-smaller` | Compact size modifier (4/10 padding, 12px font) | application.css |
| `.button.button-back` | Same as -secondary, with a ← arrow | application.css |
| `.card-action` | Mono-caps card-header link (like dashboard "VIEW ALL") | application.css |
| `.badge` | Status pill — Mono caps, 11px, hairline state-color border | application.css |
| `.callout-confidence` / `.campaign-show-callout--accent` | Orange-tinted "About to send" callout | application.css |
| `.campaign-show-hero` / `.campaign-show-meta` | Campaign show editorial primitives | application.css |
| `.campaign-edit-section` / `.campaign-edit-hero` / `.btn-editorial--*` | Campaign edit primitives | application.css |
| `.auth-card` | Devise screen card chrome | application.css |
| `status_pill(status)` | Maps status string → badge | `status_pill_helper.rb` |
| `subscribed_pill(subscriber)` | Subscribed/Unsubscribed/Bounced pill | `status_pill_helper.rb` |
| `sender_address_status_pill(sender)` | Maps SES status → humane label + pill | `status_pill_helper.rb` |

### Ejected partials under `app/views/themes/light/`

- `layouts/_account.html.erb`
- `layouts/_devise.html.erb`
- `_box.html.erb`
- `_title.html.erb`
- `_alert.html.erb`
- `attributes/_base.html.erb`
- `menu/_account.html.erb`
- `menu/_heading.html.erb`
- `menu/_item.html.erb`
- `menu/_logo.html.erb`
- `menu/_subsection.html.erb`
- `menu/_user.html.erb`
- `workflow/_box.html.erb`
- `fields/_field.html.erb` (existed before today; required/optional markers)

Stay close to vanilla BulletTrain elsewhere — these are the only ejections.

### Verification status

- Manually verified in Playwright (logged in as `qa@local.test`): dashboard, campaigns index, campaign show, subscribers index (subscribed pills visible), segments index/show, email templates index/show, sender addresses index, team settings, email sending settings.
- Devise screens verified at the URL but couldn't sign in via Playwright reliably during this session — Bruno will verify manually. The pages render perfectly when navigated to.
- Campaign edit page screenshots captured by the design-iterator and look correct. Bruno: please verify the drag-and-drop image upload works end-to-end (drop a PNG into the markdown body field on `/account/campaigns/:id/edit`).
- Public error pages: rendered statically; not yet tested by triggering a real 500. Visual layout matches design system.

### Known imperfections

- The signed-in flash callout uses the new emerald `_alert` chrome. Looks great. The `tighter` local doesn't currently route through to the new design — there if a future caller wants it.
- A handful of older shared partials (`shared/limits/form`, `shared/forms/errors`) still use BT-default chrome. Visible in form error states. Functional but slightly off the design system.
- `subscribers/imports/new.html.erb` file input uses its own bespoke styling (not the shared assets uploader). On-spec but slightly different visual weight.
- The mini-profiler badge in the top-left corner shows during dev; it's BT/dev-tooling and doesn't appear in production builds.

### Push status

21+ commits ahead of `origin/master`. **Nothing pushed.** When Bruno is ready: `git push origin master` triggers GH Actions → Kamal deploy. CSS auto-rebuilds; no migration needed (only views/CSS/JS/config changed).
