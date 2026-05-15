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
