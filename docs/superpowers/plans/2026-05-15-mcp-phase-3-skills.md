# MCP Skills Implementation Plan (Phase 3 of 6)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Expose markdown-authored "skill" documents as MCP resources so agents can read playbooks for common workflows (drafting a newsletter, translating a question into a segment, analyzing a recent send, etc.). Skills can interpolate live team context via ERB.

**Architecture:** Skills live at `app/mcp/skills/*.md`. Each has YAML frontmatter (`name`, `description`, `when_to_use`) and a markdown body that may contain ERB. A loader enumerates them, registers each as an MCP resource at URI `skill://<name>`. When the agent reads the resource, the body is rendered with the per-request `Mcp::Tool::Context` so live data (team's custom_attribute schema, recent campaign voice, segment names, etc.) is interpolated in.

**Tech Stack:** Same as Phases 1-2 — `fast-mcp 1.6`, ERB, YAML, Minitest.

**Reference spec:** `docs/superpowers/specs/2026-05-15-mcp-and-in-app-agent-design.md` §"Skills"

**Out of scope:** LLM-backed tools (Phase 4), in-app agent (Phase 5), cross-linking (Phase 6).

---

## File structure

**Created:**
- `app/mcp/skill/base.rb` — represents a parsed skill (frontmatter + body)
- `app/mcp/skill/loader.rb` — enumerates `app/mcp/skills/*.md`, returns `Skill::Base` instances
- `app/mcp/skill/renderer.rb` — given a Skill + Context, returns the rendered markdown body
- `app/mcp/skills/draft-and-send-newsletter.md`
- `app/mcp/skills/translate-question-to-segment.md`
- `app/mcp/skills/analyze-recent-send.md`
- `app/mcp/skills/import-subscribers-from-csv.md`
- `app/mcp/skills/segment-cookbook.md`
- `app/mcp/skills/voice-samples.md`
- `test/mcp/skill/base_test.rb`
- `test/mcp/skill/loader_test.rb`
- `test/mcp/skill/renderer_test.rb`
- `test/mcp/skill/registration_integration_test.rb`

**Modified:**
- `app/mcp/server.rb` — register each skill as a `FastMcp` resource at boot

---

## Task 1: `Mcp::Skill::Base` — represents one parsed skill

**Files:**
- Create: `app/mcp/skill/base.rb`
- Create: `test/mcp/skill/base_test.rb`

- [ ] **Step 1: Failing test**

```ruby
# test/mcp/skill/base_test.rb
require "test_helper"

module Mcp
  module Skill
    class BaseTest < ActiveSupport::TestCase
      SAMPLE = <<~MD
        ---
        name: example-skill
        description: A demonstration skill
        when_to_use: When the user asks for an example
        ---

        # Hello

        Body text here, with <%= 1 + 1 %> ERB tag.
      MD

      test ".parse pulls frontmatter and body" do
        skill = Base.parse(SAMPLE)
        assert_equal "example-skill", skill.name
        assert_equal "A demonstration skill", skill.description
        assert_equal "When the user asks for an example", skill.when_to_use
        assert_match(/^# Hello/, skill.raw_body)
        assert_match(/<%= 1 \+ 1 %>/, skill.raw_body)
      end

      test ".parse raises if frontmatter is missing" do
        assert_raises(Base::InvalidFormat) { Base.parse("just markdown, no frontmatter") }
      end

      test ".parse raises if name is missing" do
        body = "---\ndescription: x\nwhen_to_use: y\n---\n\nbody"
        assert_raises(Base::InvalidFormat) { Base.parse(body) }
      end

      test ".load reads a file and parses it" do
        path = Rails.root.join("tmp/test_skill.md")
        File.write(path, SAMPLE)
        skill = Base.load(path)
        assert_equal "example-skill", skill.name
      ensure
        File.delete(path) if File.exist?(path)
      end

      test "#uri returns skill://<name>" do
        skill = Base.parse(SAMPLE)
        assert_equal "skill://example-skill", skill.uri
      end
    end
  end
end
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement**

```ruby
# app/mcp/skill/base.rb
# frozen_string_literal: true

require "yaml"

module Mcp
  module Skill
    # One parsed skill: frontmatter (name, description, when_to_use) plus the
    # raw markdown body (which may contain ERB). Rendering happens elsewhere
    # (Mcp::Skill::Renderer) so that Base instances are pure data and safe to
    # cache between requests.
    class Base
      class InvalidFormat < StandardError; end

      FRONTMATTER_PATTERN = /\A---\n(.*?)\n---\n(.*)\z/m

      attr_reader :name, :description, :when_to_use, :raw_body, :source_path

      def self.parse(text, source_path: nil)
        match = text.match(FRONTMATTER_PATTERN)
        raise InvalidFormat, "missing frontmatter" unless match

        front = YAML.safe_load(match[1])
        body = match[2].sub(/\A\n+/, "")

        name = front["name"]
        raise InvalidFormat, "missing 'name'" if name.to_s.strip.empty?

        new(
          name: name,
          description: front["description"].to_s,
          when_to_use: front["when_to_use"].to_s,
          raw_body: body,
          source_path: source_path
        )
      end

      def self.load(path)
        parse(File.read(path), source_path: path.to_s)
      end

      def initialize(name:, description:, when_to_use:, raw_body:, source_path: nil)
        @name = name
        @description = description
        @when_to_use = when_to_use
        @raw_body = raw_body
        @source_path = source_path
        freeze
      end

      def uri
        "skill://#{name}"
      end
    end
  end
end
```

- [ ] **Step 4: Run, expect green.**

- [ ] **Step 5: Commit**

```bash
git add app/mcp/skill/base.rb test/mcp/skill/base_test.rb
git commit -m "feat(mcp): Mcp::Skill::Base — parses frontmatter + body"
```

---

## Task 2: `Mcp::Skill::Renderer` — ERB-render body with context

**Files:**
- Create: `app/mcp/skill/renderer.rb`
- Create: `test/mcp/skill/renderer_test.rb`

- [ ] **Step 1: Failing test**

```ruby
# test/mcp/skill/renderer_test.rb
require "test_helper"

module Mcp
  module Skill
    class RendererTest < ActiveSupport::TestCase
      setup do
        @user = create(:onboarded_user)
        @team = @user.current_team
        @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
      end

      def make_skill(body)
        Base.parse(<<~MD)
          ---
          name: test
          description: x
          when_to_use: x
          ---

          #{body}
        MD
      end

      test "renders plain markdown unchanged" do
        skill = make_skill("Hello world")
        assert_equal "Hello world\n", Renderer.new(skill: skill, context: @ctx).call
      end

      test "renders ERB with access to context.team" do
        skill = make_skill("Team is <%= context.team.name %>.")
        assert_includes Renderer.new(skill: skill, context: @ctx).call, "Team is #{@team.name}."
      end

      test "renders ERB with access to context.user" do
        skill = make_skill("User: <%= context.user.email %>")
        assert_includes Renderer.new(skill: skill, context: @ctx).call, "User: #{@user.email}"
      end

      test "rescues ERB errors and returns a clear inline error block" do
        skill = make_skill("<%= raise 'boom' %>")
        out = Renderer.new(skill: skill, context: @ctx).call
        assert_match(/skill render error/i, out)
        assert_match(/boom/, out)
      end
    end
  end
end
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement**

```ruby
# app/mcp/skill/renderer.rb
# frozen_string_literal: true

require "erb"

module Mcp
  module Skill
    # Renders a Skill::Base's raw_body as ERB, with an Mcp::Tool::Context
    # available as `context` inside ERB tags. Errors don't raise — they're
    # surfaced inline so an LLM consuming the resource sees a useful message
    # rather than a silent empty body.
    class Renderer
      def initialize(skill:, context:)
        @skill = skill
        @context = context
      end

      def call
        binding_with_context = Binder.new(@context).get_binding
        ERB.new(@skill.raw_body, trim_mode: "-").result(binding_with_context)
      rescue => e
        <<~ERR
          [skill render error]
          The skill `#{@skill.name}` could not be fully rendered:
          #{e.class}: #{e.message}
        ERR
      end

      # Provides the binding that ERB tags evaluate against. Only exposes
      # `context` — keeps the surface area tight and predictable.
      class Binder
        def initialize(context)
          @context = context
        end

        def context
          @context
        end

        def get_binding
          binding
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run, expect green.**
- [ ] **Step 5: Commit**

```bash
git add app/mcp/skill/renderer.rb test/mcp/skill/renderer_test.rb
git commit -m "feat(mcp): Mcp::Skill::Renderer — ERB-render skill body with context"
```

---

## Task 3: `Mcp::Skill::Loader`

**Files:**
- Create: `app/mcp/skill/loader.rb`
- Create: `test/mcp/skill/loader_test.rb`

- [ ] **Step 1: Failing test**

```ruby
# test/mcp/skill/loader_test.rb
require "test_helper"

module Mcp
  module Skill
    class LoaderTest < ActiveSupport::TestCase
      test ".load_all returns Base instances for every skill in app/mcp/skills" do
        skills = Loader.load_all
        assert_kind_of Array, skills
        assert(skills.all? { |s| s.is_a?(Base) })
      end

      test "skill names are unique" do
        names = Loader.load_all.map(&:name)
        duplicates = names.tally.select { |_, c| c > 1 }.keys
        assert_empty duplicates, "Duplicate skill names: #{duplicates.inspect}"
      end

      test "every skill has a non-empty description and when_to_use" do
        Loader.load_all.each do |s|
          refute s.description.strip.empty?, "#{s.name} missing description"
          refute s.when_to_use.strip.empty?, "#{s.name} missing when_to_use"
        end
      end
    end
  end
end
```

- [ ] **Step 2: Run, expect FAIL** (constant undefined).

- [ ] **Step 3: Implement**

```ruby
# app/mcp/skill/loader.rb
# frozen_string_literal: true

module Mcp
  module Skill
    # Enumerates app/mcp/skills/*.md, parses each via Skill::Base.load,
    # returns an array sorted by name. Idempotent.
    module Loader
      module_function

      def load_all
        Dir.glob(Rails.root.join("app/mcp/skills/*.md")).sort.map { |path| Base.load(path) }
      end
    end
  end
end
```

- [ ] **Step 4: At this point the test will pass with an empty array** — no skills exist yet. The "every skill has description" assertion runs vacuously. That's fine. Tasks 4–9 add the actual skills.

- [ ] **Step 5: Run, expect green (vacuously).**
- [ ] **Step 6: Commit**

```bash
git add app/mcp/skill/loader.rb test/mcp/skill/loader_test.rb
git commit -m "feat(mcp): Mcp::Skill::Loader — enumerates app/mcp/skills"
```

---

## Tasks 4-9: Author the six starter skills

Each task writes one `.md` file. They're small (≤ 100 lines each). Run after each: `bin/rails test test/mcp/skill/loader_test.rb` to confirm uniqueness + description present + parses cleanly.

### Task 4: `app/mcp/skills/draft-and-send-newsletter.md`

```markdown
---
name: draft-and-send-newsletter
description: End-to-end playbook for drafting a campaign with the LLM, previewing it, sending a test, and shipping it.
when_to_use: When the user asks to draft a newsletter, write a campaign, or send something to subscribers.
---

# Draft and send a newsletter

You're helping the user ship an email campaign on Lewsnetter. The team you're working in:

- **Team:** <%= context.team.name %> (id: <%= context.team.id %>)
- **Subscribers:** <%= context.team.subscribers.subscribed.count %> subscribed (out of <%= context.team.subscribers.count %> total)
- **Last 3 sent campaigns:** <% sent_excerpt = context.team.campaigns.where(status: "sent").order(sent_at: :desc).limit(3).pluck(:subject) %>
  <% sent_excerpt.each do |subject| %>
  - "<%= subject %>"
  <% end %>
  <% if sent_excerpt.empty? %>
  (none yet)
  <% end %>

## The flow

1. **Pick the audience.** Use `segments_list` to see existing segments. If none fits, use the `translate-question-to-segment` skill first.
2. **Draft the body.** Call `llm_draft_campaign` (Phase 4 — once available) or write the body yourself. The body is markdown; it gets composed into the team's email template at render time.
3. **Pick a template.** `email_templates_list` to see options. Templates carry the chrome (header, logo, footer, unsubscribe link). The body fills the `{{body}}` placeholder.
4. **Pick a sender.** `sender_addresses_list`; only verified senders can send. If the desired one is unverified, use `sender_addresses_verify` to re-check or trigger verification.
5. **Create the campaign.** `campaigns_create` with `subject`, `body_markdown`, `email_template_id`, `segment_id`, `sender_address_id`. Status defaults to `draft`.
6. **Preview it.** `email_templates_render_preview` with the campaign's template + a sample subscriber, OR just call `campaigns_get` to inspect the body.
7. **Send a test.** `campaigns_send_test` with `recipient_email` (defaults to the calling user). The test email lands in their inbox prefixed `[TEST]`. Confirm it looks right.
8. **Send for real.** `campaigns_send_now`. This enqueues a job that delivers to the segment. Status moves to `sending` → `sent` when complete.

## Common pitfalls

- **Empty body** — both `body_markdown` and `body_mjml` blank → validation error. At least one must have content.
- **Unverified sender** — `campaigns_send_now` will succeed but messages will fail at SES. Confirm `sender_addresses_get` returns `verified: true` first.
- **Segment with bad predicate** — `segments_count_matching` returns `predicate_error: "..."` — fix the predicate before sending.
- **No segment set** — `campaigns_send_now` will refuse. A campaign without a segment can't know who to send to.

## What "done" looks like

`campaigns_get(id: ...)` returns `status: "sent"` with a non-null `sent_at`. `campaigns_postmortem` will start showing delivery stats once the job finishes.
```

Commit:

```bash
git add app/mcp/skills/draft-and-send-newsletter.md
git commit -m "feat(mcp): skill — draft-and-send-newsletter"
```

### Task 5: `app/mcp/skills/translate-question-to-segment.md`

```markdown
---
name: translate-question-to-segment
description: Convert a natural-language audience description into a SQL predicate, preview matches, save as a Segment.
when_to_use: When the user describes an audience in plain language ("brand-tier customers who haven't logged in this month") and wants a saved Segment to send to.
---

# Translate a question into a segment

The user described an audience. Your job: turn it into a `Segment` they can use in a campaign.

## The team's data shape

The team's subscribers carry `custom_attributes` (a JSON column). Sample of observed keys + types:

<% schema = Team::CustomAttributeSchema.new(team: context.team).call %>
<% if schema[:sample].any? %>
```
<% schema[:sample].each do |key, type| %>
- <%= key %>: <%= type %>
<% end %>
```
(sampled from <%= schema[:sample_size] %> subscribers)
<% else %>
The team has no `custom_attributes` data yet — predicates will need to use base columns only (`subscribers.email`, `subscribers.subscribed`, `subscribers.created_at`, etc.).
<% end %>

If subscribers have a linked `Company`, predicates can also reference `companies.<column>` (auto-joined).

## The flow

1. **Call `llm_translate_segment`** (Phase 4) with the user's description. It returns a SQL predicate, a human description, an estimated count, and 5 sample subscribers.
2. **Sanity-check the predicate.** Does the human description match what the user asked for? Does the count make sense (not 0 unless the audience really is empty; not the entire team unless they asked for "all")?
3. **Preview matches.** Call `segments_count_matching(id: ...)` after creating, OR call the same predicate via `subscribers_list` filters if you want to see actual rows before saving.
4. **Create the segment.** `segments_create(name: <short name>, predicate: <SQL fragment>, natural_language_source: <user's original description>)`.
5. **Confirm.** `segments_count_matching(id: <new segment id>)` should return the same count the LLM estimated, plus `total_team_subscribers` for context.

## Predicate constraints

- **WHERE clause only.** No `JOIN`, no `SELECT`, no `;`. The system has a hard FORBIDDEN_PREDICATE_TOKENS list — anything looking like a statement (DROP, DELETE, UPDATE, etc.) gets rejected.
- **Reference allowed columns only:** `subscribers.id`, `subscribers.email`, `subscribers.subscribed`, `subscribers.unsubscribed_at`, `subscribers.bounced_at`, `subscribers.complained_at`, `subscribers.company_id`, `subscribers.custom_attributes`, `subscribers.created_at`, `subscribers.updated_at`. Plus `companies.*` (joined automatically when referenced).
- **For `custom_attributes` access**, use SQLite's `json_extract`: `json_extract(subscribers.custom_attributes, '$.plan') = 'pro'`. For companies: `json_extract(companies.custom_attributes, '$.tenant_type') = 'brand'`.

## Common pitfalls

- **`subscribed = 1`** vs `subscribed = TRUE` — SQLite stores booleans as integers. Use `= 1` and `= 0`.
- **NULL in custom_attributes** — `json_extract` returns NULL for missing keys; `WHERE json_extract(...) = 'x'` excludes NULLs. Use `IS NOT NULL` check first if needed.
- **Bounced/complained subscribers** — `subscribers_count` defaults to all; `segments_count_matching` returns matches without filtering bounce state. Most send-targeting predicates should include `subscribed = 1`.
```

Commit:

```bash
git add app/mcp/skills/translate-question-to-segment.md
git commit -m "feat(mcp): skill — translate-question-to-segment"
```

### Task 6: `app/mcp/skills/analyze-recent-send.md`

```markdown
---
name: analyze-recent-send
description: Pull stats from the most recent sent campaign and surface 3 actions.
when_to_use: When the user asks "how did the last send do?", "analyze the recent campaign", or wants performance commentary on a campaign.
---

# Analyze a recent send

## Find the campaign

<% recent = context.team.campaigns.where(status: "sent").order(sent_at: :desc).first %>
<% if recent %>
The most recent sent campaign for **<%= context.team.name %>**:

- **Subject:** "<%= recent.subject %>"
- **Sent at:** <%= recent.sent_at %>
- **ID:** <%= recent.id %>

You can use this campaign id directly. Or call `campaigns_list(status: "sent", limit: 5)` to let the user pick a different one.
<% else %>
The team has no sent campaigns yet. There's nothing to analyze. Suggest the user use `draft-and-send-newsletter` instead.
<% end %>

## The flow

1. **Pull the stats.** `campaigns_postmortem(id: ...)` returns a `stats` hash (sent, opened, clicked, bounced, complained, unsubscribed) and `top_links`.
2. **Get LLM commentary.** `llm_analyze_send(id: ...)` (Phase 4) returns markdown commentary with 3 specific actions.
3. **Cross-reference with subscribers.** If `bounced` is high, run `subscribers_list(query: ...)` to spot patterns. If `unsubscribed` is high, look at the subject + first paragraph; the user may want to revise tone.

## What the numbers mean

- **Sent vs delivered** — `sent` is what SES accepted; bounces happen later. A 2-5% bounce rate is normal-ish for a list with stale entries.
- **Open rate** — only meaningful if open tracking is set up. Currently Lewsnetter does NOT track opens (Apple Mail Privacy Protection broke this metric anyway). Treat `opened` as undercounted.
- **Click rate** — link clicks proxy through `/r/<token>` (if rewriting is enabled). Counts here are reliable.
- **Unsubscribe rate** — > 0.5% is worth flagging. > 1% means you misjudged the audience or content.

## Don't over-index on a single send

One bad send isn't a trend. Compare against the team's last 3-5 sends (use `campaigns_list(status: "sent")`) before declaring a strategy change.
```

Commit:

```bash
git add app/mcp/skills/analyze-recent-send.md
git commit -m "feat(mcp): skill — analyze-recent-send"
```

### Task 7: `app/mcp/skills/import-subscribers-from-csv.md`

```markdown
---
name: import-subscribers-from-csv
description: Walk through importing a CSV of subscribers — column mapping, dedupe by external_id, dry-run before commit.
when_to_use: When the user wants to import subscribers in bulk from a CSV, spreadsheet, or external system dump.
---

# Import subscribers from a CSV

## Today's state

- **Current subscribers:** <%= context.team.subscribers.count %>
- **Subscribed (sendable) count:** <%= context.team.subscribers.subscribed.count %>

## The MCP path (no UI)

1. **Map the CSV columns to subscriber fields.** Required: `email`. Recommended: `external_id` (your source system's stable ID — enables idempotent re-runs). Optional: `name`, `subscribed`, `custom_attributes` (any JSON-serializable hash).
2. **Dry-run with a small batch first.** Call `subscribers_bulk_upsert(records: [first 10 rows])`. Inspect the `created`, `updated`, and `errors` arrays. Fix CSV parsing problems before running the rest.
3. **Run the full batch in chunks of ≤ 500 records.** `subscribers_bulk_upsert` wraps in a transaction per call; smaller chunks mean a parse error in row 47,213 doesn't roll back the prior 47k. Iterate the CSV, batch, call.
4. **Verify the count.** `subscribers_count` should now match (existing + new from CSV) minus any in-CSV duplicates that resolved to upserts.

## The UI path (also valid)

The team can also use `/account/teams/<team_id>/subscribers/imports/new` in the Lewsnetter UI to upload a CSV directly. That goes through the same `subscribers_bulk_upsert`-equivalent code path under the hood. Use it if the user has a CSV file rather than data already in memory.

## Idempotent on `external_id`

If `external_id` is present, the upsert finds-or-creates: subsequent imports of the same source data don't duplicate. This is the biggest reason to include `external_id` even if your source system doesn't have a clean ID — you can synthesize one from email + something stable (e.g., signup_year).

## Custom attributes

`custom_attributes` is a JSON column. Anything you can JSON-serialize works: strings, numbers, booleans, nested objects, arrays. Keys you put here become available to:
- segment predicates (via `json_extract(subscribers.custom_attributes, '$.your_key')`)
- variable substitution in campaign bodies (via `{{your_key}}`)
- the `team_custom_attribute_schema` tool (which surfaces them to LLM tools)

## Common pitfalls

- **Email format errors** — the model validates email format; rows with bad email come back as per-record errors (don't abort the batch).
- **Subscribed defaulting** — if `subscribed` is omitted, the model default applies (currently `true`). If your CSV has unsubscribed users, set `subscribed: false` explicitly.
- **Hash custom_attributes vs string** — `custom_attributes: '{"plan":"pro"}'` (string) gets stored as a string, not a hash; predicates won't work. Pass a real hash.
```

Commit:

```bash
git add app/mcp/skills/import-subscribers-from-csv.md
git commit -m "feat(mcp): skill — import-subscribers-from-csv"
```

### Task 8: `app/mcp/skills/segment-cookbook.md`

```markdown
---
name: segment-cookbook
description: Reference patterns for common segment predicates, grounded in this team's actual custom_attribute schema.
when_to_use: When the user is composing a segment and wants examples to copy from, or when an LLM is generating a predicate and needs canonical patterns.
---

# Segment cookbook

Sample predicates that work against `<%= context.team.name %>`'s data. Adapt as needed — the predicate is a SQL WHERE fragment scoped to `subscribers` (with `companies` auto-joined when referenced).

## Subscribed-only

```sql
subscribers.subscribed = 1
```

The baseline filter for any campaign-targeted segment. Excludes unsubscribed AND bounced users (bounced sets `subscribed = 0` via the SNS webhook).

## Recently signed up

```sql
subscribers.subscribed = 1 AND subscribers.created_at >= datetime('now', '-30 days')
```

SQLite uses `datetime('now', '-N days')` for relative time. Last 7, 30, 90 days are common ranges.

## Has a specific custom attribute

<% schema = Team::CustomAttributeSchema.new(team: context.team).call %>
<% if schema[:sample].any? %>
This team's observed `custom_attributes` keys:

<% schema[:sample].each do |key, type| %>
- `<%= key %>` (<%= type %>)
<% end %>

Example with one of those keys:
```sql
subscribers.subscribed = 1 AND json_extract(subscribers.custom_attributes, '$.<%= schema[:sample].keys.first %>') = 'some_value'
```

<% else %>
This team's subscribers don't have any `custom_attributes` populated yet. Add some via `subscribers_update` or via CSV import to enable attribute-based predicates.
<% end %>

## Numeric comparison on a custom attribute

```sql
subscribers.subscribed = 1 AND CAST(json_extract(subscribers.custom_attributes, '$.signups_count') AS INTEGER) >= 5
```

Wrap `json_extract` in `CAST(... AS INTEGER)` for numeric comparisons.

## Excluding bounced or complained

```sql
subscribers.subscribed = 1 AND subscribers.bounced_at IS NULL AND subscribers.complained_at IS NULL
```

Belt-and-suspenders — `subscribed = 0` should already exclude these, but be explicit for sensitive sends.

## Company-scoped (linked Company)

```sql
subscribers.subscribed = 1 AND json_extract(companies.custom_attributes, '$.tenant_type') = 'brand'
```

Referencing `companies.*` auto-joins. The team's primary use case for this: segment by company-level metadata even when each company has multiple subscriber seats.

## NOT in a recent campaign

```sql
subscribers.subscribed = 1 AND subscribers.id NOT IN (SELECT subscriber_id FROM events WHERE name = 'campaign_sent' AND occurred_at >= datetime('now', '-7 days'))
```

Useful for "give people a break between sends." Requires events to be tracking `campaign_sent` (Lewsnetter doesn't auto-track this; the IK push pipeline would need to.)

## Anti-patterns (these will fail)

- `DROP TABLE` or any non-WHERE keyword → rejected by `Segment::FORBIDDEN_PREDICATE_TOKENS`
- `LEFT JOIN ...` → segments don't accept JOIN clauses; reference `companies.*` to trigger the auto-join instead
- `subscribers.subscribed = TRUE` → SQLite stores booleans as integers; use `= 1`
```

Commit:

```bash
git add app/mcp/skills/segment-cookbook.md
git commit -m "feat(mcp): skill — segment-cookbook"
```

### Task 9: `app/mcp/skills/voice-samples.md`

```markdown
---
name: voice-samples
description: The team's last 10 sent campaigns (subject + body excerpt) for grounding draft prompts.
when_to_use: When generating a campaign draft, include this resource so the new draft matches the team's established voice.
---

# Voice samples — <%= context.team.name %>

The last 10 campaigns this team sent, in reverse-chronological order. Use these to ground the tone of any new draft.

<% samples = context.team.campaigns.where(status: "sent").order(sent_at: :desc).limit(10) %>
<% if samples.any? %>
<% samples.each_with_index do |c, i| %>
## <%= i + 1 %>. <%= c.sent_at&.strftime("%Y-%m-%d") %> — "<%= c.subject %>"

<%= (c.body_markdown.presence || c.body_mjml.to_s.gsub(/<[^>]+>/, " ").squish).to_s[0, 600] %>...

<% end %>
<% else %>
The team hasn't sent any campaigns yet. There are no voice samples to learn from. The drafter should use a default friendly-clear tone.
<% end %>

## Voice notes

When drafting:
- **Match the salutation pattern.** If past sends use first-name greetings, do the same. If they jump straight into the news, do that.
- **Match the CTA style.** "Read more →", "Get started", "Book a call" — whatever pattern is established.
- **Match the length.** If past sends are 3 short paragraphs, don't ship a wall of text.
- **Match the formality.** Past sends set the register; departing from it without intent reads as a different brand.
```

Commit:

```bash
git add app/mcp/skills/voice-samples.md
git commit -m "feat(mcp): skill — voice-samples"
```

---

## Task 10: Register skills as MCP resources

Wire skills into `Mcp::Server` so external clients can list them via `resources/list` and read them via `resources/read`.

**Files:**
- Modify: `app/mcp/server.rb` — register each skill as a `FastMcp` resource
- Create: `test/mcp/skill/registration_integration_test.rb`

- [ ] **Step 1: Failing integration test**

```ruby
# test/mcp/skill/registration_integration_test.rb
require "test_helper"

module Mcp
  module Skill
    class RegistrationIntegrationTest < ActionDispatch::IntegrationTest
      setup do
        @user = create(:onboarded_user)
        @team = @user.current_team
        @team.update!(slug: "test-team-slug") unless @team.slug?
        @app = create(:platform_application, team: @team)
        @token = Doorkeeper::AccessToken.create!(
          resource_owner_id: @user.id, application: @app,
          scopes: "read write delete", token: SecureRandom.hex
        )
      end

      def post_mcp(body)
        post "/mcp/messages",
          params: body.to_json,
          headers: {"Authorization" => "Bearer #{@token.token}", "Content-Type" => "application/json"}
      end

      test "resources/list includes all six starter skills" do
        post_mcp(jsonrpc: "2.0", id: 1, method: "resources/list")
        assert_response :success
        body = JSON.parse(response.body)
        uris = body.dig("result", "resources").map { |r| r["uri"] }
        %w[
          skill://draft-and-send-newsletter
          skill://translate-question-to-segment
          skill://analyze-recent-send
          skill://import-subscribers-from-csv
          skill://segment-cookbook
          skill://voice-samples
        ].each { |u| assert_includes uris, u, "missing #{u}" }
      end

      test "resources/read renders a skill body with team context interpolated" do
        post_mcp(jsonrpc: "2.0", id: 2, method: "resources/read",
          params: {uri: "skill://voice-samples"})
        assert_response :success
        body = JSON.parse(response.body)
        contents = body.dig("result", "contents")
        text = contents.first["text"]
        assert_includes text, @team.name
      end
    end
  end
end
```

- [ ] **Step 2: Run, expect FAIL** — server doesn't register skills as resources yet.

- [ ] **Step 3: Update `app/mcp/server.rb`**

In the `build` method (where tools are registered), add skill registration:

```ruby
def build
  server = FastMcp::Server.new(name: "lewsnetter", version: "0.1.0", logger: Rails.logger)
  Mcp::Tool::Loader.load_all.each do |tool_class|
    server.register_tool(wrap(tool_class))
  end
  Mcp::Skill::Loader.load_all.each do |skill|
    server.register_resource(wrap_skill(skill))
  end
  server
end

# Adapter from our Mcp::Skill::Base to a FastMcp::Resource subclass.
# Renders body per-request using the Thread-local context (same threading
# pattern as tool wrappers).
def wrap_skill(skill)
  skill_obj = skill

  Class.new(FastMcp::Resource) do
    define_singleton_method(:uri) { skill_obj.uri }
    define_singleton_method(:name) { skill_obj.name }
    define_singleton_method(:description) { skill_obj.description }
    define_singleton_method(:mime_type) { "text/markdown" }

    define_method(:content) do
      ctx = Thread.current[:mcp_context]
      raise "missing per-request MCP context" if ctx.nil?
      Mcp::Skill::Renderer.new(skill: skill_obj, context: ctx).call
    end
  end
end
```

> **CAVEAT:** the actual `FastMcp::Resource` API may differ. Discover it with:
> ```bash
> grep -rn "class Resource\|def register_resource\|FastMcp::Resource" $(bundle show fast-mcp)
> ```
> Adapt the registration call + the wrapper class to match. The contract is: a class with `uri`, `name`, `description`, `mime_type`, and an instance-level `content` method that returns a string. If `register_resource` accepts a hash + block instead of a class, use that form.

- [ ] **Step 4: Run integration test, expect green.** Adapt assertions to actual response shape if needed (same way Phase 1's integration test was adapted).

- [ ] **Step 5: Commit**

```bash
git add app/mcp/server.rb test/mcp/skill/registration_integration_test.rb
git commit -m "feat(mcp): register skills as MCP resources at skill://<name>"
```

---

## Task 11: Smoke + suite

- [ ] **Step 1:** `bin/rails test test/mcp/` — all green.
- [ ] **Step 2:** Live smoke:

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

# resources/list
curl -s -X POST http://localhost:3000/mcp/messages \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"resources/list"}' \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print('resources:'); [print(' ', r['uri']) for r in d['result']['resources']]"

# resources/read on voice-samples
curl -s -X POST http://localhost:3000/mcp/messages \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":2,"method":"resources/read","params":{"uri":"skill://voice-samples"}}' \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['result']['contents'][0]['text'][:600])"

pkill -9 -f "puma\|bin/dev\|foreman" 2>/dev/null
```

Expected: `resources/list` shows 6 `skill://...` entries; `resources/read` returns the rendered voice-samples body with the team name and (if any) recent campaign subjects interpolated.

- [ ] **Step 3:** Push when ready.

---

## Self-review

**Spec coverage:**
- [x] Spec §"Skills" — all 6 starter skills (Tasks 4-9)
- [x] ERB-rendered per-request with team context — Tasks 2 (Renderer) + 10 (registration)
- [x] Frontmatter (`name`, `description`, `when_to_use`) — Task 1 (Base)
- [x] Resources mounted at `skill://<name>` — Task 1 (`#uri`) + Task 10 (registration)

**Type / name consistency:** `Mcp::Skill::{Base,Loader,Renderer}` mirrors `Mcp::Tool::{Base,Loader,Context}`.

**Placeholders:** none.

**Implementation deviations expected:**
- The `FastMcp::Resource` API in Task 10 — confirm with `grep` + adapt as needed.
- Skill body ERB tags reference real model methods. If a method name differs (e.g. `Campaign#body_markdown` vs `body_text`), adjust at write-time.
