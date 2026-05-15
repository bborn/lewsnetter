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
