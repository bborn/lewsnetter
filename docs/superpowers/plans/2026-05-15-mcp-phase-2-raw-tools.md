# MCP Raw Tools Implementation Plan (Phase 2 of 6)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mirror the existing BulletTrain HTTP API surface as MCP tools so external agents can do anything a human (or an API consumer) can do — read/write subscribers, segments, templates, campaigns, sender addresses, events.

**Architecture:** One file per tool under `app/mcp/tools/<group>/<verb>.rb`, each subclassing `Mcp::Tool::Base` (defined in Phase 1). Tools call models/services directly — they do NOT roundtrip through HTTP controllers. Authorization scopes everything to `context.team` (the token's tenant).

**Tech Stack:** Same as Phase 1 — `fast-mcp 1.6`, `Mcp::Tool::Base` with JSON Schema validation, Minitest + FactoryBot.

**Reference spec:** `docs/superpowers/specs/2026-05-15-mcp-and-in-app-agent-design.md` §"Tool surface"

**Reference plan:** `docs/superpowers/plans/2026-05-15-mcp-phase-1-chassis.md` (chassis is in place)

**Out of scope for this plan:** Skills (Phase 3), LLM-backed tools (Phase 4), in-app agent (Phase 5), cross-linking (Phase 6).

---

## Tool authoring conventions (read this first)

Every tool follows the same shape. Here's the canonical example (from Phase 1):

```ruby
# app/mcp/tools/team/get_current.rb
module Mcp
  module Tools
    module Team
      class GetCurrent < Mcp::Tool::Base
        tool_name "team_get_current"             # snake_case, group_verb
        description "Returns the id, name, and slug of the team that owns the calling token."
        arguments_schema(type: "object", properties: {}, additionalProperties: false)

        def call(arguments:, context:)
          team = context.team
          {id: team.id, name: team.name, slug: team.slug}
        end
      end
    end
  end
end
```

**Rules:**
1. **Snake-case names**, prefixed by group: `subscribers_list`, `campaigns_send_test`, etc. fast-mcp 1.6 strips dots, so don't use dots.
2. **Description** is one sentence, ≤ 140 chars, written for an LLM agent that's deciding which tool to call.
3. **`arguments_schema`** is a JSON Schema hash. Always include `additionalProperties: false`. Required fields must appear in `required: [...]`.
4. **`call(arguments:, context:)`** receives **string-keyed** `arguments` (JSON-RPC over the wire stringifies). Use `arguments["foo"]`, not `arguments[:foo]`.
5. **Always scope to `context.team`** — never look up by id without `context.team.subscribers.find(id)` or equivalent. Use of `Subscriber.find(id)` (un-scoped) is a security bug.
6. **Return JSON-serializable hashes** — no ActiveRecord objects, no Time without `.iso8601`. The wrapper JSON-encodes whatever you return, so values must round-trip through JSON.
7. **Errors are exceptions.** Raise `ActiveRecord::RecordNotFound` for missing records (the wrapper translates to a JSON-RPC error). Raise `Mcp::Tool::ArgumentError` for invalid input the schema couldn't catch.
8. **Pagination:** any `*_list` tool that could return > 50 records accepts `{limit: integer 1..200, default 50}` and `{offset: integer ≥ 0, default 0}` arguments.
9. **Serialization helper:** add `app/mcp/tools/serializers.rb` with `serialize_subscriber`, `serialize_segment`, etc. — see Task 0 below. Tools call these to keep responses consistent.

**Test conventions:**
- One test file per tool, mirroring the file path (e.g. `test/mcp/tools/subscribers/list_test.rb`).
- Always include: (a) happy path, (b) team-scoping (other team's records aren't visible), (c) one error path (e.g. invalid id → `RecordNotFound`).
- Use `Mcp::Tool::Context.new(user: @user, team: @team)` — same setup as Phase 1's `team/get_current_test.rb`.
- For destroy/delete tools: assert the target record is gone AND another team's record is unaffected.

---

## File structure (this phase)

**Created (per task):**
- `app/mcp/tools/<group>/<verb>.rb` — one file per tool
- `test/mcp/tools/<group>/<verb>_test.rb` — one test file per tool
- `app/mcp/tools/serializers.rb` (Task 0)
- `app/mcp/telemetry.rb` (Task 8)

**Modified:**
- `app/mcp/server.rb` — Task 8 wires telemetry into the wrapper

---

## Task 0: Shared serializers

Centralizes how each model becomes a hash. Keeps tools DRY and ensures all consumers see consistent shapes.

**Files:**
- Create: `app/mcp/tools/serializers.rb`
- Create: `test/mcp/tools/serializers_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# test/mcp/tools/serializers_test.rb
require "test_helper"

module Mcp
  module Tools
    class SerializersTest < ActiveSupport::TestCase
      include Serializers

      setup do
        @team = create(:team, name: "Acme")
      end

      test "serialize_subscriber produces JSON-safe hash with team-scoped fields" do
        sub = @team.subscribers.create!(email: "a@b.com", external_id: "ext-1", subscribed: true,
          custom_attributes: {plan: "pro"})
        h = serialize_subscriber(sub)
        assert_equal sub.id, h[:id]
        assert_equal "a@b.com", h[:email]
        assert_equal "ext-1", h[:external_id]
        assert_equal true, h[:subscribed]
        assert_equal({"plan" => "pro"}, h[:custom_attributes])
        assert_kind_of String, h[:created_at]  # ISO8601
      end

      test "serialize_segment includes id, name, predicate, estimated_count" do
        seg = @team.segments.create!(name: "Pro Users",
          definition: {"predicate" => "subscribers.subscribed = 1"})
        h = serialize_segment(seg)
        assert_equal seg.id, h[:id]
        assert_equal "Pro Users", h[:name]
        assert_equal "subscribers.subscribed = 1", h[:predicate]
        assert h.key?(:estimated_count)
      end

      test "serialize_campaign exposes status, subject, segment_id, sent_at iso8601 or nil" do
        camp = @team.campaigns.create!(subject: "Hi", status: "draft", body_markdown: "## hello")
        h = serialize_campaign(camp)
        assert_equal "Hi", h[:subject]
        assert_equal "draft", h[:status]
        assert_nil h[:sent_at]
      end
    end
  end
end
```

- [ ] **Step 2: Run, expect FAIL** — `Mcp::Tools::Serializers` undefined.

- [ ] **Step 3: Implement**

```ruby
# app/mcp/tools/serializers.rb
# frozen_string_literal: true

module Mcp
  module Tools
    # Module of serialization helpers shared across all MCP tools. Include
    # the module in a tool class to access them, or call the methods directly:
    # `Mcp::Tools::Serializers.serialize_subscriber(sub)`.
    #
    # All methods return JSON-serializable hashes with symbol keys (consistent
    # with the rest of the MCP wrapper, which JSON-encodes its result).
    module Serializers
      module_function

      def serialize_subscriber(sub)
        {
          id: sub.id,
          email: sub.email,
          name: sub.name,
          external_id: sub.external_id,
          subscribed: sub.subscribed,
          unsubscribed_at: sub.unsubscribed_at&.iso8601,
          bounced_at: sub.bounced_at&.iso8601,
          complained_at: sub.complained_at&.iso8601,
          company_id: sub.company_id,
          custom_attributes: sub.custom_attributes || {},
          created_at: sub.created_at.iso8601,
          updated_at: sub.updated_at.iso8601
        }
      end

      def serialize_segment(seg)
        count = begin
          seg.applies_to(seg.team.subscribers).count
        rescue Segment::InvalidPredicate
          nil
        end
        {
          id: seg.id,
          name: seg.name,
          natural_language_source: seg.natural_language_source,
          predicate: seg.predicate,
          estimated_count: count,
          created_at: seg.created_at.iso8601,
          updated_at: seg.updated_at.iso8601
        }
      end

      def serialize_email_template(t)
        {
          id: t.id,
          name: t.name,
          source_mjml: t.source_mjml,
          asset_urls: t.assets.map { |a| Rails.application.routes.url_helpers.rails_storage_proxy_url(a, only_path: true) },
          created_at: t.created_at.iso8601,
          updated_at: t.updated_at.iso8601
        }
      end

      def serialize_campaign(c)
        {
          id: c.id,
          subject: c.subject,
          preheader: c.preheader,
          status: c.status,
          body_markdown: c.body_markdown,
          email_template_id: c.email_template_id,
          segment_id: c.segment_id,
          sender_address_id: c.sender_address_id,
          scheduled_for: c.scheduled_for&.iso8601,
          sent_at: c.sent_at&.iso8601,
          created_at: c.created_at.iso8601,
          updated_at: c.updated_at.iso8601
        }
      end

      def serialize_sender_address(s)
        {
          id: s.id,
          email: s.email,
          name: s.name,
          ses_status: s.ses_status,
          verified_at: s.verified_at&.iso8601,
          created_at: s.created_at.iso8601,
          updated_at: s.updated_at.iso8601
        }
      end

      def serialize_event(e)
        {
          id: e.id,
          name: e.name,
          subscriber_id: e.subscriber_id,
          properties: e.properties || {},
          occurred_at: e.occurred_at&.iso8601,
          created_at: e.created_at.iso8601
        }
      end
    end
  end
end
```

- [ ] **Step 4: Run, expect green.**
- [ ] **Step 5: Commit**

```bash
git add app/mcp/tools/serializers.rb test/mcp/tools/serializers_test.rb
git commit -m "feat(mcp): shared serializers for tool responses"
```

**Note:** This task may surface attribute-name mismatches with the actual models (e.g. `EmailTemplate#source_mjml` may be `body_mjml`, `SenderAddress#ses_status` may be `verification_status`). Read each model's schema before implementing — adjust serializer fields to match real columns. If a model has fields the spec didn't anticipate that look useful (e.g. `description`), include them.

---

## Task 1: Subscribers tools (8 tools)

**Tools to implement:**

| Tool name | Args | Returns | Notes |
|---|---|---|---|
| `subscribers_list` | `{limit?, offset?, subscribed?: bool, query?: string}` | `{subscribers: [...], total: int, limit, offset}` | `query` matches email or external_id (`ILIKE`). Defaults `limit=50, offset=0`. |
| `subscribers_get` | `{id: integer}` | `{subscriber: {...}}` | RecordNotFound if id ∉ team. |
| `subscribers_find_by_external_id` | `{external_id: string}` | `{subscriber: {...} \| null}` | Returns null result if no match (don't raise). |
| `subscribers_create` | `{email: string, name?, external_id?, subscribed?: bool, custom_attributes?: object}` | `{subscriber: {...}}` | Idempotent on `external_id` if present (matches API controller behavior). |
| `subscribers_update` | `{id: integer, email?, name?, subscribed?: bool, custom_attributes?: object}` | `{subscriber: {...}}` | Partial update — only provided fields are written. |
| `subscribers_delete` | `{id: integer}` | `{deleted: true, id}` | RecordNotFound on miss. |
| `subscribers_bulk_upsert` | `{records: [{email, external_id?, ...}, ...]}` | `{created: int, updated: int, errors: [...]}` | Wraps in a transaction; per-record errors don't abort the batch. |
| `subscribers_count` | `{subscribed?: bool}` | `{count: int}` | Cheap count query. |

**Files:**
- Create one tool + one test per row above:
  - `app/mcp/tools/subscribers/list.rb` + `test/mcp/tools/subscribers/list_test.rb`
  - `app/mcp/tools/subscribers/get.rb` + ditto
  - ...etc

- [ ] **Step 1 (per tool): TDD cycle**

For each tool above:
1. Write the failing test (one for happy path, one for team-scoping, one for an error case appropriate to the tool — see "Test conventions" at top).
2. Run, confirm fail (`uninitialized constant`).
3. Implement the tool to the spec in the table above.
4. Run, confirm green.
5. Move to the next tool.

**Reference implementation — `subscribers_list`:**

```ruby
# app/mcp/tools/subscribers/list.rb
# frozen_string_literal: true

module Mcp
  module Tools
    module Subscribers
      class List < Mcp::Tool::Base
        include Mcp::Tools::Serializers

        tool_name "subscribers_list"
        description "Lists subscribers on the calling team. Supports limit, offset, subscribed filter, and a query that matches email or external_id."
        arguments_schema(
          type: "object",
          additionalProperties: false,
          properties: {
            limit: {type: "integer", minimum: 1, maximum: 200, default: 50},
            offset: {type: "integer", minimum: 0, default: 0},
            subscribed: {type: "boolean"},
            query: {type: "string"}
          }
        )

        def call(arguments:, context:)
          scope = context.team.subscribers
          scope = scope.where(subscribed: arguments["subscribed"]) if arguments.key?("subscribed")
          if (q = arguments["query"]).present?
            like = "%#{q}%"
            scope = scope.where("email LIKE ? OR external_id LIKE ?", like, like)
          end
          total = scope.count
          limit = arguments["limit"] || 50
          offset = arguments["offset"] || 0
          rows = scope.order(:id).limit(limit).offset(offset).map { |s| serialize_subscriber(s) }
          {subscribers: rows, total: total, limit: limit, offset: offset}
        end
      end
    end
  end
end
```

**Reference implementation — `subscribers_create` (idempotent on external_id):**

```ruby
# app/mcp/tools/subscribers/create.rb
# frozen_string_literal: true

module Mcp
  module Tools
    module Subscribers
      class Create < Mcp::Tool::Base
        include Mcp::Tools::Serializers

        tool_name "subscribers_create"
        description "Creates a subscriber on the calling team, or updates the existing one if external_id matches."
        arguments_schema(
          type: "object",
          additionalProperties: false,
          required: ["email"],
          properties: {
            email: {type: "string", format: "email"},
            name: {type: "string"},
            external_id: {type: "string"},
            subscribed: {type: "boolean"},
            custom_attributes: {type: "object"}
          }
        )

        def call(arguments:, context:)
          attrs = arguments.slice("email", "name", "external_id", "subscribed", "custom_attributes")
          existing = if attrs["external_id"].present?
            context.team.subscribers.find_by(external_id: attrs["external_id"])
          end
          if existing
            existing.update!(attrs.except("external_id"))
            {subscriber: serialize_subscriber(existing), upserted: true}
          else
            sub = context.team.subscribers.create!(attrs)
            {subscriber: serialize_subscriber(sub), upserted: false}
          end
        end
      end
    end
  end
end
```

The other six tools follow the same shape — read the canonical example (`team/get_current`), the two reference implementations above, and the test convention notes. **No tool exceeds 30 lines.** If yours does, you're probably re-implementing logic that belongs in the model — stop and put it there instead.

- [ ] **Step 2 (after all 8 tools done): Run all subscribers tests**

```bash
bin/rails test test/mcp/tools/subscribers/
```

Expected: 24+ tests, 0 failures.

- [ ] **Step 3: Run the loader test**

```bash
bin/rails test test/mcp/tool/loader_test.rb
```

Expected: still green; the uniqueness check passes because all 8 new tool names are distinct.

- [ ] **Step 4: Commit**

```bash
git add app/mcp/tools/subscribers/ test/mcp/tools/subscribers/
git commit -m "feat(mcp): subscribers tools — list, get, find_by_external_id, create, update, delete, bulk_upsert, count"
```

---

## Task 2: Segments tools (7 tools)

| Tool name | Args | Returns | Notes |
|---|---|---|---|
| `segments_list` | `{limit?, offset?}` | `{segments: [...], total, limit, offset}` | |
| `segments_get` | `{id}` | `{segment: {...}}` | |
| `segments_create` | `{name, predicate?, natural_language_source?}` | `{segment: {...}}` | `predicate` is a SQL WHERE fragment — same constraints as `Segment::FORBIDDEN_PREDICATE_TOKENS`. The model already enforces this; just propagate validation errors. |
| `segments_update` | `{id, name?, predicate?, natural_language_source?}` | `{segment: {...}}` | |
| `segments_delete` | `{id}` | `{deleted: true, id}` | If campaigns reference the segment, returns `{error: "...has campaigns"}`. The model has `dependent: :restrict_with_error`. |
| `segments_count_matching` | `{id}` | `{segment_id, count, total_team_subscribers}` | Runs the predicate; returns count vs total team population. |
| `segments_sample_matching` | `{id, limit?: int 1..50, default 10}` | `{segment_id, sample: [serialized subscribers], total_matching}` | First N matching subscribers. |

**Files:** mirror Task 1's pattern under `app/mcp/tools/segments/`.

**Important:** `count_matching` and `sample_matching` use `segment.applies_to(team.subscribers)` — see `app/models/segment.rb` for the method. It returns a scope; chain `.count` or `.limit(n).map { serialize_subscriber }` on it. Wrap in `rescue Segment::InvalidPredicate => e` and return `{error: e.message}` on bad predicate.

- [ ] Same 5 steps as Task 1: TDD per tool, batch test, commit.

```bash
git add app/mcp/tools/segments/ test/mcp/tools/segments/
git commit -m "feat(mcp): segments tools — list, get, create, update, delete, count_matching, sample_matching"
```

---

## Task 3: Email templates tools (6 tools)

| Tool name | Args | Returns | Notes |
|---|---|---|---|
| `email_templates_list` | `{limit?, offset?}` | `{email_templates: [...], total, limit, offset}` | |
| `email_templates_get` | `{id}` | `{email_template: {...}}` | |
| `email_templates_create` | `{name, source_mjml}` | `{email_template: {...}}` | |
| `email_templates_update` | `{id, name?, source_mjml?}` | `{email_template: {...}}` | |
| `email_templates_delete` | `{id}` | `{deleted: true, id}` | |
| `email_templates_render_preview` | `{id, subscriber_id?: int, sample_data?: object}` | `{html: string, subject: nil, byte_size: int}` | Calls `CampaignRenderer` with template + a stub body OR actual subscriber data. If `subscriber_id` is provided, uses that subscriber's data; otherwise uses `sample_data` hash. |

For `render_preview`, look at `app/services/campaign_renderer.rb` and how the existing template show page renders previews. Use the same code path. Don't reinvent.

**Files:** under `app/mcp/tools/email_templates/`.

- [ ] TDD + commit:

```bash
git add app/mcp/tools/email_templates/ test/mcp/tools/email_templates/
git commit -m "feat(mcp): email_templates tools — CRUD + render_preview"
```

---

## Task 4: Campaigns tools (9 tools)

| Tool name | Args | Returns | Notes |
|---|---|---|---|
| `campaigns_list` | `{limit?, offset?, status?: enum draft\|scheduled\|sending\|sent\|failed}` | `{campaigns: [...], total, limit, offset}` | |
| `campaigns_get` | `{id}` | `{campaign: {...}}` | |
| `campaigns_create` | `{subject, preheader?, body_markdown?, body_mjml?, email_template_id?, segment_id?, sender_address_id?}` | `{campaign: {...}}` | Status defaults to `draft`. |
| `campaigns_update` | `{id, ...same as create}` | `{campaign: {...}}` | Reject if `status: sent` (model already does this via `validates :body, change unless sent`; propagate errors). |
| `campaigns_delete` | `{id}` | `{deleted: true, id}` | |
| `campaigns_send_test` | `{id, recipient_email: string}` | `{enqueued: true, recipient_email, job_id}` | Uses the same code path as the existing "Send test" UI button. Likely: `SendCampaignTestJob.perform_later(@campaign, recipient_email)`. Find the actual job in `app/jobs/`. |
| `campaigns_send_now` | `{id}` | `{enqueued: true, campaign_id, status_after: "sending", subscriber_count: int}` | Refuses if `status: sent` or `status: sending`. Refuses if `segment` is unset. Calls the same enqueue path the "Send to N subscribers" UI button uses. |
| `campaigns_schedule` | `{id, scheduled_for: string ISO8601}` | `{scheduled: true, scheduled_for}` | Sets `status: scheduled`. |
| `campaigns_postmortem` | `{id}` | `{stats: {sent, opened, clicked, bounced, complained, unsubscribed}, top_links: [...], analyzed_at: iso8601}` | Read-only stats query. Distinct from Phase 4's `llm_analyze_send` which adds the LLM commentary. |

**For `campaigns_send_now`:** look at how `app/controllers/account/campaigns_controller.rb` (or wherever the Send action lives) does it. Probably enqueues `SendCampaignJob`. Mirror that exactly. Tests for this tool can use `assert_enqueued_with(job: SendCampaignJob)` rather than actually sending.

**Files:** under `app/mcp/tools/campaigns/`.

- [ ] TDD + commit:

```bash
git add app/mcp/tools/campaigns/ test/mcp/tools/campaigns/
git commit -m "feat(mcp): campaigns tools — CRUD + send_test, send_now, schedule, postmortem"
```

---

## Task 5: Sender addresses tools (4 tools)

| Tool name | Args | Returns | Notes |
|---|---|---|---|
| `sender_addresses_list` | `{}` | `{sender_addresses: [...]}` | No pagination — teams rarely have many. |
| `sender_addresses_get` | `{id}` | `{sender_address: {...}}` | |
| `sender_addresses_create` | `{email, name?}` | `{sender_address: {...}}` | Triggers SES verification request via existing model callback. |
| `sender_addresses_verify` | `{id}` | `{sender_address: {...}, verification_triggered: bool}` | Re-checks verification status against SES. Use the existing `Ses::Verifier` service. |

**Files:** under `app/mcp/tools/sender_addresses/`.

- [ ] TDD + commit:

```bash
git add app/mcp/tools/sender_addresses/ test/mcp/tools/sender_addresses/
git commit -m "feat(mcp): sender_addresses tools — list, get, create, verify"
```

---

## Task 6: Events tools (3 tools)

| Tool name | Args | Returns | Notes |
|---|---|---|---|
| `events_track` | `{external_subscriber_id: string, name: string, occurred_at?: iso8601, properties?: object}` | `{event: {...}, subscriber_id}` | Resolves subscriber by `external_id`, creates event. RecordNotFound if subscriber doesn't exist. |
| `events_bulk_track` | `{events: [{external_subscriber_id, name, ...}, ...]}` | `{created: int, errors: [{index, error}, ...]}` | Wraps in transaction; per-record errors don't abort. |
| `events_list_for_subscriber` | `{subscriber_id: int, limit?, offset?}` | `{events: [...], total, limit, offset}` | |

**Files:** under `app/mcp/tools/events/`.

- [ ] TDD + commit:

```bash
git add app/mcp/tools/events/ test/mcp/tools/events/
git commit -m "feat(mcp): events tools — track, bulk_track, list_for_subscriber"
```

---

## Task 7: Team supplementary tools (2 tools)

| Tool name | Args | Returns | Notes |
|---|---|---|---|
| `team_list_companies` | `{limit?, offset?, query?}` | `{companies: [...], total, limit, offset}` | `query` matches name or external_id. |
| `team_custom_attribute_schema` | `{}` | `{custom_attributes: {key1: "string|integer|...", ...}, sample_size: int}` | Wraps `AI::Base#custom_attribute_schema(team)` (it's a private method — extract it to a public service if cleaner, OR call it via `send(:custom_attribute_schema, team)`). |

For `custom_attribute_schema`, the cleanest path: extract the existing `AI::Base#custom_attribute_schema` (currently private) into a `app/services/team/custom_attribute_schema.rb` PORO. Refactor `AI::Base` to delegate. Then both AI services and this new MCP tool consume the same path.

**Files:** under `app/mcp/tools/team/` (alongside `get_current.rb` which exists from Phase 1).

- [ ] TDD + commit:

```bash
git add app/mcp/tools/team/ test/mcp/tools/team/ app/services/team/
git commit -m "feat(mcp): team supplementary tools — list_companies, custom_attribute_schema"
```

---

## Task 8: Telemetry — log every tool invocation

Every tool call emits one structured log line. Lets us see what agents actually do.

**Files:**
- Create: `app/mcp/telemetry.rb`
- Modify: `app/mcp/server.rb` (the `wrap` method)

- [ ] **Step 1: Write the failing test**

```ruby
# test/mcp/telemetry_test.rb
require "test_helper"

module Mcp
  class TelemetryTest < ActiveSupport::TestCase
    test "log_invocation emits a tagged structured line" do
      log_io = StringIO.new
      Rails.logger.silence do
        Telemetry.with_logger(Logger.new(log_io)) do
          Telemetry.log_invocation(tool_name: "team_get_current", team_id: 7, latency_ms: 12, success: true)
        end
      end
      assert_match(/\[mcp\]/, log_io.string)
      assert_match(/team_get_current/, log_io.string)
      assert_match(/team_id=7/, log_io.string)
      assert_match(/success=true/, log_io.string)
    end
  end
end
```

- [ ] **Step 2: Implement**

```ruby
# app/mcp/telemetry.rb
# frozen_string_literal: true

module Mcp
  # Structured logging for every MCP tool invocation. One line per call, tagged
  # `[mcp]`, format: `tool=<name> team_id=<id> latency_ms=<int> success=<bool> [error=<class>]`.
  # Cheap enough to leave on in production; future analytics piping can grep on
  # `[mcp]` and parse the kv pairs.
  module Telemetry
    module_function

    def with_logger(logger)
      previous = Thread.current[:mcp_telemetry_logger]
      Thread.current[:mcp_telemetry_logger] = logger
      yield
    ensure
      Thread.current[:mcp_telemetry_logger] = previous
    end

    def log_invocation(tool_name:, team_id:, latency_ms:, success:, error_class: nil)
      logger = Thread.current[:mcp_telemetry_logger] || Rails.logger
      parts = ["[mcp]", "tool=#{tool_name}", "team_id=#{team_id}", "latency_ms=#{latency_ms}", "success=#{success}"]
      parts << "error=#{error_class}" if error_class
      logger.info(parts.join(" "))
    end

    # Wraps a block, times it, and logs an invocation. Returns the block's value.
    def around(tool_name:, team_id:)
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = yield
      latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round
      log_invocation(tool_name: tool_name, team_id: team_id, latency_ms: latency_ms, success: true)
      result
    rescue => e
      latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round
      log_invocation(tool_name: tool_name, team_id: team_id, latency_ms: latency_ms, success: false, error_class: e.class.name)
      raise
    end
  end
end
```

- [ ] **Step 3: Wire into the server wrapper**

In `app/mcp/server.rb`'s `wrap` method, change the `define_method(:call)` block to wrap the invoke call in `Mcp::Telemetry.around`:

```ruby
define_method(:call) do |**args|
  ctx = Thread.current[:mcp_context]
  raise "missing per-request MCP context" if ctx.nil?

  result = Mcp::Telemetry.around(tool_name: our_tool._tool_name, team_id: ctx.team.id) do
    our_tool.new.invoke(arguments: args, context: ctx)
  end
  result.is_a?(String) ? result : JSON.generate(result)
end
```

- [ ] **Step 4: Run the telemetry test + integration tests** (the integration test should still pass — telemetry is observable but not behavior-changing).

```bash
bin/rails test test/mcp/
```

Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add app/mcp/telemetry.rb test/mcp/telemetry_test.rb app/mcp/server.rb
git commit -m "feat(mcp): telemetry — one log line per tool invocation"
```

---

## Task 9: Full suite + smoke

- [ ] **Step 1:** Run the full suite. Expect no NEW failures attributable to MCP changes (pre-existing factory/scaffold gaps remain).

```bash
bin/rails test
```

- [ ] **Step 2: Smoke test against live dev server**

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

# tools/list — should now show ~30 tools, not just 1
curl -s -X POST http://localhost:3000/mcp/messages \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d['result']['tools']), 'tools'); [print(' ', t['name']) for t in d['result']['tools']]"

# subscribers_list against a real team
curl -s -X POST http://localhost:3000/mcp/messages \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"subscribers_list","arguments":{"limit":3}}}' \
  | python3 -m json.tool

pkill -9 -f "puma\|bin/dev\|foreman" 2>/dev/null
```

Expected: `~30 tools` printed; `subscribers_list` returns a real (or empty) JSON array of subscribers, plus a `total` count.

- [ ] **Step 3: Push when ready**

```bash
git push -u origin feature/mcp-chassis  # same branch — Phase 2 commits ride on top
```

(If you'd prefer a separate Phase 2 branch off `feature/mcp-chassis`, that's also fine — Bruno's flow is master-direct so it doesn't matter much.)

---

## Self-review

**Spec coverage:**
- [x] All tools listed in spec §"Tool surface" except the LLM ones (Phase 4) → Tasks 1–7.
- [x] Telemetry hooks (`[mcp]` tag with team_id, tool_name, latency, success) → Task 8.
- [x] All tools scope to `context.team` (security invariant) → enforced by convention + tested in each task's team-scoping test.

**Type / name consistency:**
- All tools follow `<group>_<verb>` snake-case convention (locked in by Phase 1's renaming fix).
- Serializer method names match: `serialize_<thing>` everywhere, taking a single record, returning a hash with symbol keys.
- Pagination args are always `limit` + `offset` (never `page` + `per_page` — be consistent across the surface).

**Placeholders:** none. Each task either has full code (Tasks 0, 1's reference impls, 8) or a precise table of (name, args, returns, notes) the implementer can complete from the references.

**Scope check:** seven tool-implementation tasks + one telemetry + one verification = 9 tasks. Each task ships ~3-9 tools. Manageable size; each commits independently.

**Important deviations the implementer may need to make:**
- Model attribute names may differ from the table (e.g. `EmailTemplate#source_mjml` may be `body_mjml`, `SenderAddress` may not have `verified_at`). Read each model's schema before writing the serializer; serializer task surfaces the issue first.
- `campaigns_send_now` and `campaigns_send_test` may need to look up the actual job class names by reading `app/controllers/account/campaigns_controller.rb`. Don't invent the enqueue API — match what the UI does.
- `team_custom_attribute_schema` requires extracting a private method from `AI::Base`; the task notes this as an explicit refactor, but if the implementer prefers to call the private method via `send`, that's also acceptable for v1.
