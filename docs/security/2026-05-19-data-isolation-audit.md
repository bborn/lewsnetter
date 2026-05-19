# Multi-Tenant Data Isolation Audit — 2026-05-19

## Executive Summary

Overall posture: **good on the BulletTrain-scaffolded surfaces, weak on the bespoke ones**. The Account web controllers, REST API v1 (CRUD endpoints), MCP tools, search service, tracking endpoints, jobs, and Avo admin gate are correctly scoped to `team` via either `account_load_and_authorize_resource` or explicit `context.team.<assoc>` queries. Three structural problems undermine the directive that "no data should ever be viewable, listable, or editable across Teams": the MCP layer authenticates the *user* but derives team via `user.current_team` (not the token's bound team); the public `/unsubscribe/:token` endpoint accepts a bare integer fallback that lets an unauthenticated attacker mass-unsubscribe any team's subscribers by enumerating IDs; and the SNS webhook updates `Delivery` rows by `ses_message_id` without verifying the row belongs to the team that owns the SNS topic. **2 Critical, 3 High, 4 Warning, 1 Gray Area.** No remediation should disable security controls — each finding has a specific fix.

## Critical Findings

### C1. `/unsubscribe/:token` falls back to integer ID lookup — anyone can unsubscribe any subscriber
- **Location:** `app/controllers/unsubscribe_controller.rb:57-58`
- **Evidence:**
  ```ruby
  GlobalID::Locator.locate_signed(token, for: "unsubscribe") ||
    Subscriber.find_by(id: token)
  ```
- **Attack vector:** unauthenticated, no rate limit visible on this route. `GET /unsubscribe/1`, `/unsubscribe/2`, ... iterates over every Subscriber row across every team. Each hit sets `subscribed: false, unsubscribed_at: now` via `update_columns` (bypasses callbacks). Mailkick `unsubscribe(list)` also fires. A trivial loop unsubscribes every recipient on the platform — campaign-level integrity attack across all tenants.
- **Reproduction:** `for i in $(seq 1 100000); do curl -X POST https://host/unsubscribe/$i; done` — every existing Subscriber with id in range gets unsubscribed.
- **Suggested fix:** drop the `|| Subscriber.find_by(id: token)` branch. Require the signed GlobalID token in 100% of cases. The comment "legacy / manual link" is the smoking gun — there is no scenario where an integer ID should be honored as a credential.

### C2. MCP token is not bound to a team — uses `user.current_team`
- **Location:** `app/mcp/doorkeeper_auth.rb:32`
- **Evidence:**
  ```ruby
  team = user.current_team
  return error(env, 401, "Token resource owner has no current team") if team.nil?
  ```
  Combined with `Mcp::Tool::Context.new(user: user, team: team)` and every MCP tool keying off `context.team`.
- **Attack vector:** Doorkeeper access tokens *are* bound to a team through `Platform::Application#team_id` (`Platform::AccessToken has_one :team, through: :application`), but the MCP middleware throws that away and uses whatever `user.current_team` happens to be. `current_team_id` is a mutable column on `users` that is overwritten **anytime a request to a different team's web UI succeeds** (see `BulletTrain::LoadsAndAuthorizesResource#load_team:172` — `current_user.update_column(:current_team_id, @team.id)`). So a user on Teams A + B who provisions a sync token for Team A, logs into the web UI to view Team B, then runs an MCP client — the MCP token now reads/writes Team B's subscribers, campaigns, segments, deliveries, etc., despite being "the Team A token."
- **Reproduction:** create user U as member of Team A and Team B. Mint a Platform::Application+AccessToken bound to Team A via `/account/teams/A/developers/create_sync_app`. Log into the web UI and click around Team B (sets `current_team_id = B`). Now call any MCP tool with the Team A bearer token — `subscribers_list`, `campaigns_create`, `subscribers_delete` — all hit Team B.
- **Suggested fix:** in `DoorkeeperAuth#call`, replace `team = user.current_team` with `team = Platform::AccessToken.find_by(token: ...)&.application&.team`. Reject tokens whose application has no team (system-level apps from `/oauth/register` should be rejected at the MCP boundary, or routed through an explicit `team_id` arg checked against the user's memberships).

## High Findings

### H1. REST API tokens are not bound to a team either — same root cause as C2
- **Location:** `bullet_train-api-1.45.1/app/controllers/concerns/api/controllers/base.rb:92-95`
  ```ruby
  def current_team
    current_user&.teams&.first
  end
  ```
- **Attack vector:** identical shape to C2 for the JSON API at `/api/v1/...`. Although most v1 controllers use `account_load_and_authorize_resource` (which loads via `params[:team_id]` from URL and authorizes through CanCan), this still means **any Doorkeeper token issued to a user who belongs to multiple teams can write to any of those teams** by simply putting a different `team_slug` in the URL. The `lewsnetter-rails` gem at `gems/lewsnetter-rails/lib/lewsnetter_rails/client.rb:55` POSTs to `/api/v1/teams/#{config.team_slug}/subscribers/bulk` — there is no enforcement that the token's bound team matches `config.team_slug`.
- **Reproduction:** mint a sync token for Team A; configure `LewsnetterRails.configuration.team_slug = "B"`; the source app now writes Team A's data into Team B (assuming U is a member of both). User-error scenario but the architecture should prevent it.
- **Suggested fix:** in `Api::V1::ApplicationController` (or `Api::Controllers::Base`), add a `before_action` that, when authenticated via `doorkeeper_token`, asserts `doorkeeper_token.application.team_id == params[:team_id].to_i` (when `:team_id` is in the URL). For nested shallow routes where `:team_id` isn't present, derive the team via the loaded resource and compare. Reject mismatches with `:forbidden`.

### H2. SNS webhook updates Delivery rows without verifying team ownership
- **Location:** `app/controllers/webhooks/ses/sns_controller.rb:232-244` (`update_delivery_for`)
- **Evidence:**
  ```ruby
  delivery = Delivery.find_by(ses_message_id: message_id)
  ```
  Called from `handle_bounce`/`handle_complaint`/`handle_reject`/`handle_delivery`. The team is resolved via `config_for_topic(topic_arn)` (good), but the Delivery lookup is global and the caller does not assert `delivery.campaign.team_id == team.id`.
- **Attack vector:** a malicious tenant points their own SNS topic at `/webhooks/ses/sns`, completes the SubscriptionConfirmation flow (which the controller auto-confirms), then emits a forged Bounce/Complaint payload whose `mail.messageId` matches another team's recently-sent message id (these are SES UUIDs but appear in postmortem CSVs and SNS audit logs that the attacker may legitimately see for their own sends). Result: another team's Delivery row gets flipped to `bounced` / `complained`, polluting that team's postmortem and skewing their reputation dashboard. Combined with the missing SNS-signature verification (already acknowledged in the controller comment at line 10), even the topic-ARN tie can be spoofed.
- **Suggested fix:** scope the lookup to the resolved team: `Delivery.joins(:campaign).where(campaigns: {team_id: team.id}).find_by(ses_message_id: message_id)`. Separately, implement SNS signature verification — the deferred work in the controller comment is now overdue given two new fields (Delivery, Suppression) depend on this trust boundary.

### H3. SNS webhook auto-confirms arbitrary topics whose ARN matches any team
- **Location:** `app/controllers/webhooks/ses/sns_controller.rb:46-62`
- **Evidence:** `handle_subscription_confirmation` GETs the `SubscribeURL` for any topic whose ARN already appears in any `Team::SesConfiguration` row.
- **Attack vector:** if Team A configures `sns_bounce_topic_arn = X` and an attacker can guess/observe X (ARNs leak in many places), the attacker can re-create that SNS topic in their own AWS account and trigger a SubscriptionConfirmation. The webhook will GET the SubscribeURL — but that URL is signed by AWS's TLS endpoint with the topic owner's account ID. Lower-impact than H2 but still a confused-deputy: confirms subscriptions for topics it shouldn't validate.
- **Suggested fix:** verify the `SignatureVersion` + signing certificate against the AWS SNS public cert before processing any payload (including SubscriptionConfirmation). This is the proper fix and also closes H2's spoofing branch.

## Warnings

### W1. `revoke_token` looks up by global ID before scoping
- **Location:** `app/controllers/account/developers_controller.rb:61-65`
- **Evidence:** `token = Doorkeeper::AccessToken.find(params[:id])` then `authorize! :destroy, token.application`. CanCan's `Platform::AccessToken` ability is `application: {team_id: user.team_ids}, provisioned: true` (`app/models/ability.rb:24`), so a non-member's destroy attempt does fail authorization — but the load is unscoped. Returns 403 (cancan-style) instead of 404, which is an enumeration oracle: an attacker can map which token IDs exist across all teams.
- **Suggested fix:** `Platform::AccessToken.joins(:application).where(applications: {team_id: @team.id}).find(params[:id])`.

### W2. Account::SubscribersController#search uses LIKE on a deterministic-encrypted column
- **Location:** `app/controllers/account/subscribers_controller.rb:28-31`
- **Evidence:** `where("LOWER(email) LIKE :n OR LOWER(name) LIKE :n OR LOWER(external_id) LIKE :n", n: needle)`. The email column is deterministic-encrypted so `LIKE` over ciphertext is meaningless. Not a leak (still team-scoped via `@team.subscribers`), but a functional bug — and any future "let me unencrypt-then-search" remediation must preserve the team scope.

### W3. `Account::SubscribersController#search`, `Account::SearchController#index`, and `Account::SuppressionsController` accept `params[:team_id]` directly
- **Location:** subscribers_controller.rb:17, search_controller.rb:14, suppressions_controller.rb:61
- **Evidence:** `@team = current_user.teams.find(params[:team_id])` + `authorize! :show, @team`. This is correct (`current_user.teams.find` scopes to the user's memberships and raises RecordNotFound otherwise), but the authorize check is `:show`/`:manage` on the Team — *all* members of a team can hit Cmd+K search regardless of their role. Editor-only viewers can search subscribers they should be able to read; current roles.yml grants subscribers `:read` to default role, so this is consistent. Flag for review only — confirm that `:show` on Team is the right gate for search.

### W4. Bulk API endpoints (`subscribers#bulk`, `subscribers#destroy_by_external_id`, `events#track`, `events#bulk`) skip `account_load_and_authorize_resource`
- **Location:** `app/controllers/api/v1/subscribers_controller.rb:64,104`; `app/controllers/api/v1/events_controller.rb:48,82,125`
- **Evidence:** `@team = Team.find(params[:team_id])` then `authorize! :create, @team.subscribers.new` (or equivalent). The authorize check does block cross-team writes for users who are not members of the URL team — but failure on the raw `Team.find` raises 404 instead of CanCan's `:access_denied` rescue, and the pattern means any new bulk action could silently skip the authorize step. Combined with H1 (token not bound to team), these endpoints are the most exposed surface for the gem and Push API.
- **Suggested fix:** prefer `current_user.teams.find(params[:team_id])` to scope at lookup; or add a shared `before_action` that loads `@team` and authorizes against the team's resources collection.

## Confirmed Safe

- **MCP tools (40+ files in `app/mcp/tools/`):** every database access starts from `context.team.<association>` — verified via grep that no tool uses raw `Subscriber.`, `Campaign.`, `Segment.`, `EmailTemplate.`, `Delivery.`, or `Suppression.` finder calls. (The exceptions in `email_templates/render_preview.rb:33,68,78` are in-memory `Subscriber.new(team: context.team, ...)` and `Campaign.new(team: context.team, ...)` — never persisted, never queried.) See `app/mcp/tools/subscribers/{list,get,update,delete,create,bulk_upsert,find_by_external_id,count}.rb`, `app/mcp/tools/campaigns/*.rb`, `app/mcp/tools/segments/*.rb`, `app/mcp/tools/email_templates/*.rb`, `app/mcp/tools/sender_addresses/*.rb`, `app/mcp/tools/events/*.rb`, `app/mcp/tools/llm/*.rb`. **However:** all of these rely on `context.team` being the right team — see C2 for why the binding itself is broken.
- **Account REST CRUD controllers:** `CampaignsController`, `SubscribersController`, `SegmentsController`, `EmailTemplatesController`, `SenderAddressesController`, `Subscribers::ImportsController`, `Campaigns::DeliveriesController`, `Account::CampaignPostmortemsController` all use `account_load_and_authorize_resource :resource, through: :team`. The shallow-route loader (`bullet_train-super_load_and_authorize_resource-1.45.1/.../loads_and_authorizes_resource.rb:126-142`) ensures member actions load through CanCan, which evaluates `permit user, through: :memberships, parent: :team` from `app/models/ability.rb:13`.
- **Account::Search service** (`app/services/account/search.rb:36-285`): every query (subscribers, companies, segments, campaigns, email templates, sender addresses) flows through `team.<association>` — see lines 107, 142, 159, 182, 208, 238, 264. Empty-query recent rows are likewise scoped.
- **Tracking endpoints** (`app/controllers/tracking/opens_controller.rb:29`, `tracking/clicks_controller.rb:19-21,36-46`): signed message-verifier tokens carry `delivery_id` and (for clicks) the destination URL inside the signed payload. Open redirect is closed by signing the URL. No team field is needed because the token itself is the unforgeable credential.
- **Suppression model** (`app/models/suppression.rb`): `for_team_emails(team, emails)` and `suppress(team:, ...)` both scope by `team_id`. `SesSender` calls `Suppression.for_team_emails(team, batch_emails)` (`app/services/ses_sender.rb:42`) with `team = campaign.team` — correctly scoped.
- **Delivery model** (`app/models/delivery.rb`): `belongs_to :campaign` + `belongs_to :subscriber`, both team-scoped via parent. Queries via `@campaign.deliveries` in the controller (`app/controllers/account/campaigns/deliveries_controller.rb:79`) and via `campaign.deliveries.<scope>` in the postmortem MCP tool. The only unscoped raw query — `Delivery.find_by(ses_message_id: message_id)` in the SNS webhook — is flagged as H2.
- **Background jobs:** `SendCampaignJob#audience_for` reads `campaign.team.subscribers.subscribed` (`app/jobs/send_campaign_job.rb:74`). `ImportSubscribersJob#upsert_row` takes `import.team` and uses `team.subscribers.find_or_initialize_by` (`app/jobs/import_subscribers_job.rb:94-101`). Both correctly carry team context from their arguments — `current_user.current_team` is never consulted in a worker.
- **PaperTrail History partial** (`app/views/account/shared/_history.html.erb:9`): `record.versions.reorder(...)` is scoped to the parent record (which is team-scoped via its controller). No global `PaperTrail::Version.find` is reachable from any user-facing controller.
- **Active Storage attachments** on Campaign + EmailTemplate: `destroy_asset` actions use `@campaign.assets.attachments.find_by(id: params[:asset_id])` (`app/controllers/account/campaigns_controller.rb:97`), team-scoped via parent. URLs are `rails_storage_proxy_url(blob)` — proxied through Rails (not direct R2 URLs), so blob IDs are not directly enumerable from outside.
- **Subscriber email deterministic encryption**: `where(email: q)` lookups in MCP `subscribers_list` and Account search are gated by `team.subscribers.where(email: q)` — even though deterministic ciphertext is the same across teams, the team_id constraint forbids cross-team match. Verified in `app/mcp/tools/subscribers/list.rb:30` and `app/services/account/search.rb:145`.

## Gray Areas / By Design

- **Avo admin** (`config/routes/avo.rb`): mounted inside `authenticate :user, lambda { |u| u.developer? }`. `developer?` reads `DEVELOPER_EMAILS` env. Avo is intentionally cross-team for operators. No vulnerability — but worth confirming `DEVELOPER_EMAILS` is set conservatively in production and rotated when an employee leaves.

## Coverage Gaps

- **Stripe webhooks (BulletTrain ships these):** I didn't open the BulletTrain-billing gem's webhook controller because it wasn't in the project source. If it routes by Stripe customer ID, audit it separately — same shape as the SNS webhook concern.
- **Webhooks::Outgoing::EndpointsController** (BulletTrain gem): not present in `app/controllers/webhooks/outgoing/` in this repo; skip until that gem is enabled.
- **Rate limiting on `/unsubscribe/:token`, `/track/o/:token.gif`, `/track/c/:token`, `/webhooks/ses/sns`:** I didn't audit Rack::Attack / rate-limiter configuration. Even with C1 fixed, signed-token endpoints should be rate-limited per IP to slow forging attempts.
- **`Platform::Application` records created via `/oauth/register`** (`app/controllers/oauth/registrations_controller.rb:31`): these are system-level (no `team_id`). Tokens minted against them have no team binding at all. The fix proposed in C2 should reject these tokens at the MCP boundary, or require a follow-up `team_id` selection step that writes the team to the application.
- I did not enumerate every `app/models/*.rb` for missing `belongs_to :team`; I spot-checked Subscriber, Campaign, Suppression, Delivery, EmailTemplate. A grep of `belongs_to :team` against the full models tree would round this out.
