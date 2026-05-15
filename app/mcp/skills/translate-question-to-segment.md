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
