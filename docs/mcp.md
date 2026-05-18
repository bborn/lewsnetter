# MCP — using Lewsnetter from an agent

Lewsnetter exposes a [Model Context Protocol](https://modelcontextprotocol.io) server. Every action a human can take in the UI, an agent can take through MCP. Same controllers, same services, same authorization.

This is the wedge. If you're building an agent that needs to send email — Lewsnetter is the only platform designed for that workflow from the ground up rather than retrofitted.

## Connecting

The MCP endpoint is at `/mcp/messages` (HTTP) on your Lewsnetter host.

**OAuth 2.1 with Dynamic Client Registration (RFC 7591)** — Claude Desktop, Cursor, Codex, and any MCP-compliant client can register themselves. From the client's side, it's just "Add a server: https://app.lewsnetter.dev/mcp" — the OAuth dance happens automatically and the user signs in once.

For programmatic use (your own scripts, agents you run yourself), use a personal access token:
1. Sign in to Lewsnetter
2. **Developers → Sync setup** — generate a token
3. Send it as `Authorization: Bearer <token>` on requests to `/mcp/messages`

## Tools

Lewsnetter ships ~43 MCP tools. Source of truth: `app/mcp/tools/`. They're grouped by domain:

| Domain | Tools (selection) |
|---|---|
| **Subscribers** | `subscribers.list`, `.get`, `.create`, `.update`, `.delete`, `.bulk_upsert`, `.find_by_external_id`, `.count` |
| **Campaigns** | `campaigns.list`, `.get`, `.create`, `.update`, `.delete`, `.schedule`, `.send_now`, `.send_test`, `.postmortem` |
| **Segments** | `segments.list`, `.get`, `.create`, `.update`, `.delete`, `.count_matching`, `.sample_matching` |
| **Email templates** | `email_templates.list`, `.get`, `.create`, `.update`, `.delete` |
| **Sender addresses** | `sender_addresses.list`, `.get`, `.create`, `.verify`, `.delete` |
| **Events** | `events.list`, `.create` (custom subscriber events you segment on) |
| **Team** | `team.get` (current team metadata + limits) |
| **LLM (introspection)** | `llm.*` (agent-side conveniences — usually you don't need these directly) |

### Example tool: `subscribers.list`

```json
{
  "name": "subscribers.list",
  "arguments": {
    "segment_id": "abc123",
    "limit": 100,
    "page": 1
  }
}
```

Returns subscribers matching the segment, paginated. Read the tool source for the full schema:

```sh
cat app/mcp/tools/subscribers/list.rb
```

### Example tool: `campaigns.send_now`

```json
{
  "name": "campaigns.send_now",
  "arguments": {
    "campaign_id": "xyz789"
  }
}
```

Sends a previously-drafted campaign immediately. The agent picks the campaign; the rendering, segment resolution, and SES dispatch happen server-side.

## Agent recipes

### 1) Daily summary

Run on a schedule. Posts a brief to wherever you read it (Slack, your inbox, your own dashboard).

```
Every weekday at 9am:
  1. subscribers.count → total subscribers
  2. events.list(after: yesterday) → new signups + unsubscribes
  3. campaigns.list(status: "sent", since: 7.days.ago)
     → for each, campaigns.postmortem(campaign_id) for open/click/bounce stats
  4. Compose a summary, send to me
```

### 2) Drip campaigns via cron (instead of native drip)

Lewsnetter doesn't ship native drip sequences. Reasonable indie-dev workaround: the agent IS the drip engine.

```
Every 6 hours:
  1. subscribers.list(filter: { custom_attr: { signed_up_at: { gt: 7.days.ago },
                                                 welcome_3_sent: false } })
  2. For each: campaigns.send_now(campaign_id: "welcome_email_3", to: [subscriber.id])
  3. For each: subscribers.update(id, custom_attributes: { welcome_3_sent: true })
```

The "drip" is one cron schedule + one segment definition + a custom attribute marking sent state. More flexible than visual drip builders — you can change the logic in plain language without dragging boxes.

### 3) Compose + send from a spec

```
Prompt: "Draft a release-notes email about our new search feature.
Audience: brand-tier customers active in the last 30 days. Send tomorrow at 10am ET."

Agent:
  1. segments.list → find the "brand-tier active 30d" segment, or:
  2. segments.create → build one if missing
  3. segments.count_matching → confirm size before composing
  4. campaigns.create → draft MJML + Markdown body
  5. campaigns.send_test → preview to the operator
  6. campaigns.schedule(send_at: tomorrow 10am ET)
```

The agent owns the workflow. Lewsnetter owns the primitives.

## Permissions

The MCP token inherits the user's team membership and role. An agent can do exactly what its user can do — no more. CanCanCan abilities apply identically.

## Webhooks (outgoing)

If you want your agent to react to events Lewsnetter generates (campaign sent, subscriber bounced, etc.), set up an outgoing webhook in **Developers → Webhooks**. POST destinations get JSON payloads when events fire. Your agent can react in real time instead of polling.

## Limitations

- **No streaming yet.** All tool responses are single JSON payloads. Long operations (big bulk imports) block until done.
- **No tool-level rate limiting yet** — please don't hammer `subscribers.bulk_upsert` in a tight loop.
- **No multi-tenant agent token scoping** — a token is bound to one team. If your agent needs to act across multiple teams, request a token per team.

## Reading the source

The MCP server lives at `app/mcp/`. Entry point: `app/mcp/server.rb`. Each tool is a class in `app/mcp/tools/<domain>/<verb>.rb` — the file IS the schema + the implementation. Reading the source for any tool is faster than reading docs about it.
