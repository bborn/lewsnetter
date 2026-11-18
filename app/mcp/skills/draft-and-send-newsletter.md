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

1. **Pick the audience.** Use `segments_list` to see existing segments. If none fits, create one with `segments_create`, using the `segment-cookbook` skill for predicate patterns, and check its size with `segments_count_matching`.
2. **Draft the body.** Call `llm_draft_campaign` or write the body yourself. The body is markdown; it gets composed into the team's email template at render time.
3. **Pick a template.** `email_templates_list` to see options. Templates carry the chrome (header, logo, footer, unsubscribe link). The body fills the `{{body}}` placeholder.
4. **Pick a sender.** `sender_addresses_list`; only verified senders can send. If the desired one is unverified, use `sender_addresses_verify` to re-check or trigger verification.
5. **Create the campaign.** `campaigns_create` with `subject`, `body_markdown`, `email_template_id`, `segment_id`, `sender_address_id`. Status defaults to `draft`.
6. **Preview it.** `email_templates_render_preview` with the campaign's template + a sample subscriber, OR just call `campaigns_get` to inspect the body.
7. **Send a test.** `campaigns_send_test` with `recipient_email` (defaults to the calling user; only team members' addresses are accepted). The test email lands in their inbox prefixed `[TEST]`. Confirm it looks right.
8. **Send for real.** `campaigns_send_now`. This enqueues a job that delivers to the segment. Status moves to `sending` → `sent` when complete.

## Common pitfalls

- **Empty body** — both `body_markdown` and `body_mjml` blank → validation error. At least one must have content.
- **Unverified sender** — `campaigns_send_now` will succeed but messages will fail at SES. Confirm `sender_addresses_get` returns `verified: true` first.
- **Segment with bad predicate** — `segments_count_matching` returns `predicate_error: "..."` — fix the predicate before sending.
- **No segment set** — the campaign would go to every subscribed contact, so `campaigns_send_now` refuses unless you pass `all_subscribers: true`. Only do that when the user asked for everyone.
- **Send failed or stalled partway** — status `failed`, or `sending` with no progress for 15 minutes. Use `campaigns_resume_send`; it only mails subscribers who don't already have a delivery for the campaign. Never duplicate the campaign to "resend" it, because the copy goes to everyone again.
- **Scheduled sends** — `campaigns_schedule` sets `scheduled_for`; a job checks every minute and sends once that time has passed (including after downtime, on the first check back).

## What "done" looks like

`campaigns_get(id: ...)` returns `status: "sent"` with a non-null `sent_at`. `campaigns_postmortem` will start showing delivery stats once the job finishes.
