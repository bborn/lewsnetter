# Lewsnetter v2 — Post-Launch Follow-ups

**Status:** Drafted 2026-05-12, branch `master` (already deployed at https://lewsnetter.whinynil.co)
**Owner:** Bruno via Claude subagent-driven development

Four tasks closing the loop on production hardening + the IK migration. Each task is independent; execute sequentially (per the subagent-driven-development discipline — no parallel implementer subagents).

---

## Task 1 — Verify bounce simulator round-trip

**Why:** SES → SNS → webhook → mailkick suppression pipeline is wired up but never end-to-end tested against a real SES event. Until verified, we don't know whether the webhook signature handling, topic-ARN routing, or mailkick update path actually works against AWS's actual notification format. We don't want to find out at scale.

**Approach:** Use SES's `bounce@simulator.amazonses.com` reserved address to trigger a real Permanent bounce. SES will publish a Bounce event to our `lewsnetter-ses-bounces` SNS topic, which delivers a Notification POST to `https://lewsnetter.whinynil.co/webhooks/ses/sns`. Our controller looks up the team by topic ARN, then sets `subscriber.subscribed=false, bounced_at=Time.current`.

**Workflow:**

1. SSH to the production server.
2. Via `docker exec ... bin/rails runner`, create a one-off test Subscriber on Team 1 with `email: "bounce@simulator.amazonses.com"`.
3. Trigger a real send via `SesSender.send_bulk` against that subscriber. The send returns a real SES message_id (configuration set is attached so events publish).
4. Poll the subscriber for up to 90 seconds (`subscriber.reload` every 5s). The webhook should fire within ~30s of SES generating the bounce event.
5. Verify `subscribed == false` AND `bounced_at` is present AND within the last 2 minutes.
6. Clean up: destroy the test subscriber.
7. Write a one-screen summary at `initiatives/lewsnetter-v2/BOUNCE_VERIFICATION.md` with the actual timestamps + the production log lines that proved the loop closed (the `[SNS:bounce] team=1 email=bounce@simulator.amazonses.com unsubscribed (permanent)` log line).
8. Commit the doc. Don't push.

**Acceptance criteria:**
- The doc exists and contains real timestamps from a successful round-trip.
- The doc references the actual server log line (not a hypothetical one).
- The Subscribers test row is cleaned up afterward (no stale `bounce@simulator.amazonses.com` row left).
- No code changes needed in this task — the wiring is already deployed. This task is verification only.

**File boundaries:** `initiatives/lewsnetter-v2/BOUNCE_VERIFICATION.md` (new). Nothing else.

**If the loop doesn't close:** capture exactly where it broke (subscription confirmation? topic ARN mismatch? webhook 500? mailkick update failure?) and report BLOCKED with the specific failure mode. The controller will dispatch a follow-up implementer with a targeted fix.

---

## Task 2 — Per-team unsubscribe subdomain (`email.influencekit.com`)

**Why:** Unsubscribe URLs currently land on `https://lewsnetter.whinynil.co/unsubscribe/:token`. When IK sends from `@influencekit.com`, the cross-domain unsubscribe link triggers Gmail/Outlook/Apple Mail anti-phishing heuristics. Mailbox providers materially downgrade deliverability when the unsub host doesn't match the sending domain's organizational identity.

**Approach:** Add a `unsubscribe_host` column on `Team::SesConfiguration` (e.g. `"email.influencekit.com"`). When set, ApplicationMailer's `List-Unsubscribe` header + the in-body unsubscribe link both use that host. The team's tenants configure a DNS CNAME from `email.influencekit.com` → `lewsnetter.whinynil.co` on their side; the kamal-proxy is reconfigured to accept multiple host names so the same Rails app responds.

**Steps:**

1. **Migration** `db/migrate/20260512220000_add_unsubscribe_host_to_team_ses_configurations.rb` — adds a nullable `unsubscribe_host` string column.
2. **Model** — `Team::SesConfiguration#unsubscribe_host` accessor (provided by AR). Add `validates :unsubscribe_host, format: {with: /\A[a-z0-9.\-]+\z/i, allow_blank: true}`.
3. **UI** — Add the field to `app/views/account/email_sending/_form.html.erb` with a helper text like "Optional. CNAME this to lewsnetter.whinynil.co for branded unsubscribe URLs."
4. **Mailer helper** — Create `app/helpers/unsubscribe_url_helper.rb` (or extend ApplicationMailer) with `unsubscribe_url_for(subscriber)`. Returns `"https://#{team.ses_configuration&.unsubscribe_host || default_host}/unsubscribe/#{token}"`. Apply in `ApplicationMailer`'s `List-Unsubscribe` headers AND in `CampaignRenderer`'s body substitution (so `{{unsubscribe_url}}` works in MJML templates).
5. **kamal-proxy host list** — Extend `config/deploy.yml`'s `proxy.host` from a single string to the rotation pattern (Kamal 2 supports comma-separated hosts in the `host:` field, OR `hosts:` array). Verify by reading the Kamal 2 docs / proxy source. The list should at minimum include `lewsnetter.whinynil.co` and `email.influencekit.com`. Bruno will add the CNAME in Cloudflare; kamal-proxy starts answering for it once the deploy lands.
6. **Tests** — Minitest:
   - `test/models/team/ses_configuration_test.rb`: unsubscribe_host validation
   - `test/helpers/unsubscribe_url_helper_test.rb`: returns team's host if configured, falls back otherwise
   - `test/mailers/application_mailer_test.rb`: List-Unsubscribe header uses team's host

**Acceptance criteria:**
- A team with `unsubscribe_host = "email.influencekit.com"` set produces unsub URLs on that host.
- A team without it set falls back to `lewsnetter.whinynil.co`.
- The kamal-proxy `host:` configuration includes both at deploy time.
- Migration runs cleanly on SQLite (don't introduce PG-specific syntax).

**Open question for human:** TLS for the new host. Cloudflare Flexible terminates TLS at the edge and talks plain HTTP to origin, so the Origin CA cert on kamal-proxy doesn't need to cover the new domain. **Don't introduce a second cert in this task** — that's Task 3's territory.

**File boundaries (implementer touches only these):**
- `db/migrate/20260512220000_add_unsubscribe_host_to_team_ses_configurations.rb` (NEW)
- `app/models/team/ses_configuration.rb` (add validation)
- `app/views/account/email_sending/_form.html.erb` (add field)
- `config/locales/en/email_sending.en.yml` (label for the new field)
- `app/mailers/application_mailer.rb` (use helper)
- `app/helpers/unsubscribe_url_helper.rb` (NEW)
- `app/services/campaign_renderer.rb` (add `{{unsubscribe_url}}` substitution using helper)
- `app/controllers/account/email_sending_controller.rb` (permit the new param in strong params)
- `config/deploy.yml` (multi-host proxy)
- `test/...` per the list above

Do not touch the existing unsubscribe controller (`app/controllers/unsubscribe_controller.rb`) or the SNS webhook.

---

## Task 3 — Cloudflare Full (Strict) with Origin CA cert on kamal-proxy

**Why:** Production currently runs Cloudflare Flexible SSL (TLS terminates at the edge; CF → origin is plain HTTP). Mailer links in production-grade email systems should be served over HTTPS end-to-end; mailbox providers also factor this into reputation. The Origin CA cert pair is already in `.kamal/secrets` (`ORIGIN_CERT` / `ORIGIN_KEY`) — they just aren't mounted into kamal-proxy.

**Approach:** Kamal 2 supports custom certs for its proxy via `proxy.ssl: true` + writing the cert/key to specific paths the proxy reads. The exact mechanism varies by kamal-proxy version — research the current Kamal 2 docs (find them under `/Users/bruno/.local/share/mise/installs/ruby/4.0.3/lib/ruby/gems/4.0.0/gems/kamal-2.*/` and `kamal-proxy-*/`). Two viable patterns:

**Option A: Custom TLS via Kamal's built-in mechanism.** `proxy.ssl: true` + `proxy.host:` + an extra config (e.g. `proxy.tls_keypair:`) that points at the secrets. If kamal-proxy 2 supports this natively, this is the right path.

**Option B: Bind-mount a host directory.** Add a pre-deploy hook (`.kamal/hooks/pre-deploy`) that writes `ORIGIN_CERT` + `ORIGIN_KEY` from secrets to `/etc/kamal-proxy/cert.pem` and `/etc/kamal-proxy/key.pem` on the host, then configure kamal-proxy to use them. This requires `proxy.options:` or similar to mount the directory.

Pick the option that exists in the installed kamal-proxy version. Document the choice.

**Steps:**

1. Read Kamal 2 / kamal-proxy source to find the supported pattern for custom certs.
2. Implement that pattern.
3. Verify locally: `mise x -- bundle exec kamal config` should show the new proxy block. `mise x -- bundle exec kamal proxy boot` (against the live server) should reload the proxy with the new cert. (If that's destructive, document the exact deploy step.)
4. Flip Cloudflare SSL mode from Flexible → Full (Strict) — this requires a human (the dashboard).
5. Smoke-test: `curl -sI https://lewsnetter.whinynil.co/up` should still return 200. From the origin server: `curl -sIk https://178.156.185.100/up -H 'Host: lewsnetter.whinynil.co'` should return 200 over the Origin CA cert.
6. Capture the proof (curl output + cert subject from `openssl s_client`) in `initiatives/lewsnetter-v2/SSL_FULL_STRICT_VERIFICATION.md`.
7. Commit. Don't push.

**Acceptance criteria:**
- kamal-proxy serves HTTPS with the Cloudflare Origin CA cert (subject contains "CloudFlare Origin CA").
- Cloudflare SSL mode is Full (Strict) and end-to-end browser tests still pass.
- The doc records the verification.

**Open question for human:** Bruno needs to flip Cloudflare SSL mode → Full (Strict) at the right moment (after the cert is mounted but before the next deploy that might cycle the proxy). The plan documents both states clearly so Bruno can do it without ambiguity.

**File boundaries:**
- `config/deploy.yml` (modify proxy block)
- `.kamal/hooks/pre-deploy` (NEW if Option B)
- `initiatives/lewsnetter-v2/SSL_FULL_STRICT_VERIFICATION.md` (NEW)

---

## Task 4 — IK migration prep: install the gem in IK, prepare bulk_upsert

**Why:** The whole point of Lewsnetter v2 is to replace IK's Intercom-based marketing email pipeline. The Lewsnetter side is live and working. The IK side now needs the gem installed, the User model annotated, and an initial bulk_upsert of the existing audience.

**Approach:** This task crosses into a different repository: `~/Projects/rails/influencekit/`. The implementer will:

1. Switch to that repo.
2. Add the vendored gem to IK's Gemfile (path-vendored against `~/Projects/rails/lewsnetter/vendor/gems/lewsnetter-rails` for now; we'll extract to a public repo later).
3. `bundle install` in IK.
4. Add an initializer `config/initializers/lewsnetter.rb` in IK that configures `Lewsnetter.endpoint`, `.api_key`, `.team_id` from IK's Rails credentials.
5. Mint an API key on the live Lewsnetter via the **Doorkeeper Platform::AccessToken** flow (or — since we never built that UI — via a rails runner against the production container).
6. Add `acts_as_lewsnetter_subscriber` to `app/models/user.rb` in IK, mapping:
   - `external_id: :id`
   - `email: :email`
   - `name: :full_name`
   - `attributes: ->(u) { u.analytics_data.merge(tenant_attributes_prefixed) }` — combine IK's existing User#analytics_data + Tenant#analytics_data (with `tenant_` prefix on the latter, so segments can disambiguate)
7. Run a **dry-run bulk_upsert** of, say, 100 active users to Lewsnetter. Verify they land. Look at one sample in the Lewsnetter UI.
8. **DO NOT** run a full `Lewsnetter.bulk_upsert(User.active)` against IK's full audience yet — that's a separate "go live" step Bruno will trigger when he's ready to send the first newsletter.
9. Write `initiatives/lewsnetter-v2/IK_MIGRATION_STATUS.md` documenting:
   - The exact code changes in IK (file paths + line counts)
   - The API key minting procedure (since the UI isn't built yet)
   - The dry-run results (sample count, time elapsed, errors)
   - The exact one-line command Bruno will run to do the full backfill: `Lewsnetter.bulk_upsert(User.active)`
   - A "rollback plan" — if something goes wrong, how to disable the integration in IK (one-line change to the initializer)

**Acceptance criteria:**
- IK's Gemfile + Gemfile.lock + initializer + User.rb changes are committed in the IK repo (separate from the Lewsnetter repo).
- A dry-run of ~100 users pushed successfully to the live Lewsnetter team and is visible in `/account/teams/.../subscribers`.
- The status doc exists in the Lewsnetter repo (NOT in IK — the Lewsnetter repo is the SOR for the migration plan).
- The full backfill is documented but NOT yet executed.

**Open questions for human (surface early):**
- Should the lewsnetter-rails gem be extracted to its own GitHub repo now, or stay path-vendored? (Decision affects how the gem is installed in IK.)
- Does IK have a Bundler private gem source set up, or does it pull from the local filesystem? (Affects deploy story for IK.)
- Which IK environment should we test the dry-run against — production User table or a staging clone?

**File boundaries:**
- `initiatives/lewsnetter-v2/IK_MIGRATION_STATUS.md` (NEW — Lewsnetter repo)
- In IK repo (`~/Projects/rails/influencekit/`):
  - `Gemfile`
  - `Gemfile.lock`
  - `config/initializers/lewsnetter.rb` (NEW)
  - `app/models/user.rb` (add `acts_as_lewsnetter_subscriber`)
  - `config/credentials.yml.enc` (add Lewsnetter API key + team_id)

The implementer should commit in BOTH repos but push neither.

---

## Execution order

1. Task 1 (verification — no code change, useful sanity check before more changes)
2. Task 2 (per-team unsub subdomain — small, additive)
3. Task 3 (CF Full Strict — touches deploy infrastructure, do after Task 2 lands so the multi-host change is in)
4. Task 4 (IK migration prep — biggest, depends on nothing structurally but is the most expensive context-switch)

After all tasks: final code review for the cumulative diff; push to origin.
