# Lewsnetter 2.0 — Plan

**Status:** Drafted 2026-05-12
**Owner:** Bruno
**Name:** Lewsnetter (locked — keep heritage, repo lives at [bborn/lewsnetter](https://github.com/bborn/lewsnetter), open source from day 1)

## One-liner

An AI-native, owned-audience email marketing platform. Brief in, segmented blast out. Multitenant SaaS from day 1. Bruno's IK is the first tenant; Wovenmade and future projects come next; eventually sold to indie SaaS operators who want to leave Mailchimp/Intercom.

## Why now

1. **IK needs to move off Intercom for marketing email** — that's the forcing function.
2. **Bruno already designed this in 2014** ([bborn/lewsnetter](https://github.com/bborn/lewsnetter)). The data model and lifecycle hold up. Modern Rails + AI eliminates most of the original code surface.
3. **AI changes the product category.** Mailchimp/ConvertKit haven't been rebuilt for the AI era. There's a credible $100–500/mo tier opening up.
4. **Bruno has multiple projects** that need this. Building it once and reusing across IK + Wovenmade + future is leverage.

## What's different from 2014 Lewsnetter

2014 model: write one email → blast → measure.

2026 model: write a brief → agent drafts, segments, personalizes, sends, analyzes → human approves at each gate. The product is a **marketing co-pilot**, not a sender.

| Lewsnetter 2014 | Lewsnetter 2026 |
|---|---|
| Standalone Heroku app, single tenant | Multitenant SaaS, Stripe-billed |
| Subscriber model, CSV import | Push API + Ruby gem, source-app driven |
| Hand-built filter UI for segments | Natural-language segment translator |
| WYSIWYG editor for one HTML body | Brief → draft via LLM, MJML body, voice-matched |
| One blast, one body for everyone | Per-recipient AI personalization (premium tier) |
| Post-send: open/click counts | Post-send: AI postmortem, pattern surfacing |
| Hand-rolled bounce/complaint via SNS | `mailkick` reads SES suppression list automatically |
| Web UI only | Every action also an MCP tool — agents can drive it |

## Naming

**Locked: Lewsnetter.** Heritage name, Bruno-flavored, the [2014 repo at bborn/lewsnetter](https://github.com/bborn/lewsnetter) becomes the home for v2 (clean-slate the codebase, keep the repo and history). Open source from day 1 — the indie/Bruno brand IS the positioning.

## Stack

**Foundation: BulletTrain** ([bullettrain.co](https://bullettrain.co/), MIT-licensed OSS Community Edition).

Picked over Jumpstart Pro specifically because **Lewsnetter is open source from day 1** — Jumpstart Pro's paid/closed license would block redistribution. BulletTrain's MIT license lets us ship the full app publicly.

BulletTrain provides:
- Rails 8, Hotwire (Turbo + Stimulus), Tailwind
- **Teams = tenant boundary**, Devise + invitations + role-based authorization (CanCanCan)
- Stripe billing via "Membership" / Pay
- `super_scaffolding` generator (fast model + UI scaffolds aware of the multitenant model)
- Magic Test for system specs
- Active admin-style internal tooling

Implication for development speed: BulletTrain has more boilerplate than Jumpstart but the `super_scaffolding` generator partially compensates by scaffolding tenant-aware CRUD in one command. Net: maybe a day slower than Jumpstart for the foundation, but the OSS unlock is worth it.

**Email + jobs:**
- `aws-sdk-sesv2` — SendBulkEmail, suppression list API
- `mailkick` 2.0 — subscription state, one-click unsubscribe, RFC 8058 List-Unsubscribe headers, SES suppression sync
- `mjml-rails` — responsive HTML templates
- `solid_queue` (Rails 8 default) — background jobs
- `solid_cache` (Rails 8 default) — caching

**AI:**
- `ruby_llm` + `ruby_llm-agent` (already proven in IK Kit refactor)
- `pgvector` — only when needed (lookalike segments, voice matching). Skip MVP.

**MCP / agent surface:**
- `mcp-rb` or roll our own — every capability also a tool. Tenant-scoped API key + MCP endpoint.

**Hosting:**
- Kamal 2 deploy to a Hetzner box (~$5–20/mo). Postgres + Redis + Rails app + Solid Queue worker on one box for MVP.

## Multitenant model

**Tenant = `Team`** (BulletTrain's Team model).

Each team has:
- Users (team members, via Jumpstart invitations)
- Sending domains (SES-verified, DKIM/SPF/DMARC tracked)
- Sender addresses (verified senders on those domains)
- Subscribers (their owned audience)
- Events (behavioral data on subscribers)
- Segments (saved queries / NL-defined)
- Templates (MJML layouts)
- Campaigns (a send)
- API keys (for the push API + MCP)
- Stripe subscription (Pay gem)

**Plan tiers (initial sketch):**

| Plan | Price | Subscribers | Sends/mo | AI features |
|---|---|---|---|---|
| Starter | $29/mo | 2,500 | 10,000 | Segment translator, brief→draft |
| Growth | $99/mo | 25,000 | 100,000 | All Starter + post-send analyst + reply triage |
| Pro | $299/mo | 100,000 | 500,000 | All Growth + per-recipient personalization + MCP access |
| Custom | — | — | — | High-volume + dedicated IPs |

Pricing is illustrative — refine after IK is the first user and we know the cost curve.

## Data model

```
Team (tenant — BulletTrain built-in)
  has_many :memberships  # BulletTrain's user-team join
  has_many :sending_domains
  has_many :sender_addresses
  has_many :subscribers
  has_many :events
  has_many :segments
  has_many :templates
  has_many :campaigns
  has_many :api_keys
  has_one :stripe_subscription  # via Pay / BulletTrain billing

Subscriber
  belongs_to :team
  external_id (FK to source app, unique per team)
  email, name
  custom_attributes :jsonb  # ANY keys/values the source app wants — see below
  subscribed :boolean (per-list state via mailkick)
  unsubscribed_at, complained_at, bounced_at
  has_many :events

Event
  belongs_to :team
  belongs_to :subscriber
  name (e.g. "report_viewed", "upgraded_to_flex")
  occurred_at
  properties :jsonb

Segment
  belongs_to :team
  name
  definition :jsonb  # SQL predicate or NL source
  natural_language_source :text  # what the user typed
  computed_count, last_computed_at

Template
  belongs_to :team
  name
  mjml_body :text
  rendered_html :text  # cached, premailer-inlined

Campaign
  belongs_to :team
  belongs_to :template, optional: true
  belongs_to :segment
  belongs_to :sender_address
  subject, preheader, body_mjml, body_html
  status (draft / scheduled / sending / sent / failed)
  scheduled_for, sent_at
  stats :jsonb (sent, delivered, bounced, complained, opened, clicked, unsubscribed)

Send (one row per recipient — only at Pro tier for personalization)
  belongs_to :campaign
  belongs_to :subscriber
  personalized_body :text (nullable; only set if AI personalization enabled)
  ses_message_id
  delivered_at, opened_at, clicked_at, bounced_at, complained_at
```

### Subscriber `custom_attributes` — arbitrary tenant-defined data

Lewsnetter accepts **any** key/value pairs on a subscriber, just like Intercom / Customer.io / Segment. The source app decides what's worth syncing; Lewsnetter doesn't enforce a schema. No migration needed when a tenant wants to add a new attribute.

Column is named `custom_attributes` (not `attributes`) because ActiveRecord reserves `attributes`. In the API payload it's surfaced as `attributes:` so it reads naturally.

**Reference shape — what IK pushes today (from `User#analytics_data` + `Tenant#analytics_data`):**

```ruby
# Per-user attributes (the subscriber)
{
  email:                       "alicia@influencekit.com",
  role:                        "admin",
  is_admin:                    true,
  tenant_type:                 "brand_account",
  tokens_count:                42,
  deliverables_count:          17,
  partner_id:                  nil,
  partner_name:                nil,
  subdomain:                   "alicia",        # IK's tenant subdomain
  affiliate_code:              "BORN20",
  plan:                        "growth",
  plan_status:                 "active",        # active / cancelled / past_due
  tenant_id:                   1234,
  flex_signup:                 false
}

# Per-tenant attributes IK also pushes (relevant for company-level segmentation)
{
  name:                        "Alicia's Brand",
  tenant_type:                 "brand_account",
  tabs_enabled:                "reports,calendar,partners",
  plan:                        "growth",
  plan_status:                 "active",
  trial_days_remaining:        nil,
  subdomain:                   "alicia",
  affiliate:                   "bruno@ik.com",
  affiliate_code:              "BORN20",
  report_credits:              50,
  assignments_quota:           100,
  influencer_hub_campaigns:    3,
  influencer_hub_assignments:  27,
  topic_tags:                  "fashion,lifestyle,wellness"
}
```

For Lewsnetter MVP we merge both shapes into a flat `custom_attributes` hash on the subscriber. Tenant-level attributes get a `tenant_` prefix (e.g. `tenant_subdomain`, `tenant_plan`, `tenant_mrr`) so the segment translator can disambiguate.

**Indexing:** `custom_attributes` is a plain `jsonb` column with no index initially. Postgres handles `WHERE custom_attributes->>'plan' = 'growth'` fine up to a few hundred thousand rows. Add a GIN index when query latency demands it:

```sql
CREATE INDEX index_subscribers_on_custom_attributes
  ON subscribers USING GIN (custom_attributes);
```

**Type handling:** All values pass through as-is (jsonb preserves types — string, number, boolean, null, nested object). The segment translator's prompt includes the *observed* set of keys + value types per tenant (sampled from `subscribers.custom_attributes`) so the LLM doesn't have to guess what's available.

## Sync architecture

**Push from source app to Lewsnetter via API.** Never pull from source DBs (couples schemas, leaks credentials, breaks SaaS isolation).

### API endpoints (tenant-scoped via API key)

```
POST /api/v1/subscribers          # idempotent upsert by external_id
  { external_id, email, name, attributes: {...}, subscribed: true }

POST /api/v1/subscribers/bulk     # NDJSON or CSV upload, for backfill
  Content-Type: application/x-ndjson

POST /api/v1/events               # behavioral event
  { external_id, name, occurred_at, properties: {...} }

POST /api/v1/events/bulk          # batch events

DELETE /api/v1/subscribers/:external_id   # GDPR-style hard delete
```

### `lewsnetter-rails` gem (or whatever it's named)

```ruby
# Gemfile
gem "lewsnetter-rails"

# config/initializers/lewsnetter.rb
Lewsnetter.configure do |c|
  c.api_key = Rails.application.credentials.lewsnetter_api_key
  c.endpoint = "https://app.lewsnetter.com/api/v1"
end

# app/models/user.rb
class User < ApplicationRecord
  acts_as_lewsnetter_subscriber(
    external_id: :id,
    email: :email,
    name: :full_name,
    attributes: ->(u) {
      {
        plan: u.tenant.plan_tier,
        mrr: u.tenant.mrr_cents,
        signed_up_at: u.created_at,
        is_paying: u.tenant.paying?
      }
    }
  )
end

# Track events from anywhere
Lewsnetter.track(user, "report_viewed", report_id: report.id)
```

`acts_as_lewsnetter_subscriber` hooks `after_commit` on the model, enqueues a `Lewsnetter::SyncJob` to POST the upsert. Idempotent. Failure → retry with backoff.

Backfill from console: `User.find_each(&:sync_to_lewsnetter!)` or `Lewsnetter.bulk_upsert(User.all)` which streams NDJSON.

### Why this beats pull / reverse-ETL

- **Tenant isolation** — each tenant only exposes the fields they want
- **Schema-agnostic** — Lewsnetter doesn't care about your User model
- **Multi-source** — same gem in IK, Wovenmade, ten other apps; each is a separate Lewsnetter account
- **Latency** — events arrive within seconds, not nightly
- **Simple to debug** — failed sync = a job in your app's queue, you can see it

## AI feature spine

Three features for MVP. Don't build all six on day 1.

### 1. Natural-language segment translator (highest leverage)

UI: text field. User types: *"Paying brands who haven't logged in for 30 days but viewed a report this week."*

`SegmentTranslator` agent (RubyLLM::Agent):
- System prompt: schema of `subscribers` + `events` tables, tenant-scoped
- Tools: `query_attribute_keys`, `query_event_names`, `validate_sql(predicate)`
- Output: a SQL predicate + a human-readable description for review
- Optional: show 5 sample subscribers matching the segment before saving

Stored as `Segment.definition` jsonb (the predicate) and `Segment.natural_language_source` (the original text). Recompute count nightly + on demand.

### 2. Brief → draft

UI: "Compose campaign" → user enters subject hint, 5 bullets, picks segment, picks tone (or attaches voice samples).

`CampaignDrafter` agent:
- Tools: `fetch_voice_samples(team_id)` (last 10 sent campaigns), `fetch_segment_context(segment_id)` (sample subscribers, common attributes), `render_mjml(body)`
- Output: 5 subject candidates with rationale, MJML body, suggested send time
- User reviews/edits in MJML textarea with live preview

### 3. Post-send analyst

After a campaign sends, agent reads:
- This campaign's stats (open, click, bounce, complaint rates)
- Tenant's historical campaigns (baseline)
- Subject + body

Generates a 3-paragraph postmortem:
- What worked
- What didn't (with hypotheses)
- What to try next campaign

Surfaced in the campaign detail view + an optional email to the team owner.

### v2 (next 30 days)

4. **Per-recipient personalization** — at send time, generate a tailored opening paragraph per subscriber. Pro tier only. Economics: ~$0.0005/email × 5k = $2.50/blast on Haiku-class models. Premium tier absorbs.
5. **Reply triage** — SES inbound or IMAP. Classify replies (question/complaint/lead/unsub/autoresponder). Hot replies surface in inbox; complaints auto-suppress.

### v3 (90 days)

6. **Auto-sourcing** — RSS / changelog / git log → drafted recurring newsletters. Brand newsletter writes itself from blog feed.
7. **Lookalike segments** — pgvector embeddings on subscriber attribute vectors. "Find subscribers similar to my top 10 engaged."

## MCP / agent-native surface

**Every capability is also an MCP tool**, exposed per-tenant via API key. The agent-native architecture skill in the compound-engineering plugin governs this pattern.

Initial tools:
- `lewsnetter.subscriber.upsert(external_id, email, attributes)`
- `lewsnetter.event.track(external_id, name, properties)`
- `lewsnetter.segment.define_from_text(natural_language)` → returns segment_id + preview
- `lewsnetter.segment.list()`
- `lewsnetter.campaign.draft(brief, segment_id, voice)` → returns campaign_id (draft state)
- `lewsnetter.campaign.preview(campaign_id, to: email)`
- `lewsnetter.campaign.queue(campaign_id, send_at: ...)`
- `lewsnetter.campaign.cancel(campaign_id)`
- `lewsnetter.campaign.stats(campaign_id)`
- `lewsnetter.template.create(name, mjml)`

Implication: the IK GM (Claude Code) gets MCP access to Lewsnetter. *I* can draft and queue the brand newsletter — not just file a Linear ticket for Alicia. Same for Wovenmade and any future tenant's agent.

## Pricing & business model

Bootstrap: Bruno is tenant zero. Don't sell publicly until IK has sent 10 successful campaigns and the workflow feels right.

Pricing logic:
- SES costs ~$0.10/1k emails. Mailchimp charges $0.50–$3/1k. Lewsnetter sits in between but adds AI.
- AI per-recipient personalization adds ~$0.0005/email cost. Pro tier pricing must cover this with margin.
- The pricing sketch (Starter $29 / Growth $99 / Pro $299) is illustrative. Adjust once we know real usage curves.

Distribution path (later):
1. IK + Wovenmade as anchors
2. Indie SaaS Slack/Discord communities (Indie Hackers, Rails World)
3. ProductHunt launch when feature spine is real
4. The "I built Mailchimp on Rails with AI in 2 weeks" blog post writes itself

## MVP scope (week 1–2)

Goal: Bruno sends the first IK brand newsletter through Lewsnetter, replacing Intercom.

**Week 1: Foundation**
- [ ] Clean-slate the `bborn/lewsnetter` repo: archive 2014 code on a `legacy-2014` branch, scaffold v2 on `main` with BulletTrain
- [ ] BulletTrain Team model active as tenant boundary + Stripe billing via Pay
- [ ] Subscriber + Event + Segment + Template + Campaign models + migrations
- [ ] Push API (subscribers + events + bulk endpoints) with API key auth
- [ ] `lewsnetter-rails` gem skeleton + `acts_as_lewsnetter_subscriber` concern
- [ ] SES integration (sending domain setup, DKIM, SPF, DMARC docs)
- [ ] mailkick install + one-click unsubscribe + List-Unsubscribe headers
- [ ] SES SNS webhook → suppression sync
- [ ] Campaign composer UI (MJML textarea + live preview + segment picker + audience count)
- [ ] SendCampaignJob using SES SendBulkEmail in batches of 50
- [ ] Deploy to Hetzner via Kamal

**Week 2: AI spine + IK migration**
- [ ] SegmentTranslator agent (NL → SQL)
- [ ] CampaignDrafter agent (brief → subject + MJML body)
- [ ] Post-send analyst (auto-postmortem)
- [ ] IK Rails app: install `lewsnetter-rails` gem, sync existing Users
- [ ] Export Intercom subscriber state, bulk import to Lewsnetter
- [ ] Send first IK brand newsletter via Lewsnetter
- [ ] MCP tool surface (basic — campaign + subscriber + segment tools)

**Out of scope for MVP:**
- Per-recipient personalization
- Reply triage / inbound email
- Drag-and-drop visual editor
- Multi-list management beyond a single "newsletter" list per tenant
- Public signup / billing portal (only Bruno's accounts exist for now)
- Lookalike segments / pgvector

## Open questions

1. **MJML editor.** Pure textarea + preview iframe is fine for MVP. Add Action Text or a visual editor only if it's the limiting factor for real users.
2. **Inbound email.** SES inbound (S3 → Lambda → webhook) is the cheap path. Skip until reply triage is on the roadmap.
3. **Dedicated IPs.** Don't bother until a tenant sends >100k/month. Shared SES pool with clean auth is fine to start.
4. **Migration tooling for Intercom.** Build a one-off importer, or rely on CSV. CSV likely sufficient.
5. **Personalization scope.** Per-campaign opt-in or global per-team? Probably per-campaign (cost control) with a per-team default.
6. **OSS license + contributor model.** MIT to match BulletTrain. Decide on CLA or DCO before accepting external PRs.
7. **Hosted vs self-hosted positioning.** Lewsnetter ships OSS, Bruno also runs a hosted SaaS at lewsnetter.com (the BulletTrain model). Need to be explicit in README about which features are hosted-only vs always-OSS.

## References

- 2014 Lewsnetter: https://github.com/bborn/lewsnetter (clean-slate to v2, preserve as `legacy-2014` branch)
- BulletTrain: https://bullettrain.co/ (MIT-licensed Rails SaaS starter — the foundation)
- mailkick: https://github.com/ankane/mailkick
- SES SendBulkEmail: https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/SESV2/Client.html#send_bulk_email-instance_method
- MJML: https://mjml.io/
- RubyLLM::Agent (used in IK Kit refactor — see `project_kit_refactor_status.md` in GM memory)
- Customer.io API (sync architecture reference): https://customer.io/docs/api/track/
- Agent-native architecture skill: `compound-engineering:agent-native-architecture`
