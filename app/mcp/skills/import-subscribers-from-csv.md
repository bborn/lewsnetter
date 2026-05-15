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
