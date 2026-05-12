# Bounce Simulator Round-Trip Verification

**Status: ✅ SUCCESS — round-trip closes in ~2 seconds.**

## Summary

A real send via `SesSender.send_bulk` to `bounce@simulator.amazonses.com`
flips `Subscriber#bounced_at` and `Subscriber#subscribed=false` end-to-end
through SES → Configuration Set → SNS → our webhook → mailkick suppression
within seconds. Log lines confirm the controller routed the notification
through the right team and the right case branch.

## Closing run

```
t_send           = 2026-05-12T21:06:54Z
SES message_id   = 0100019e1e03a4de-68e3b84a-d186-418a-b593-62f849e6decb-000000
bounced_at flip  = 2026-05-12T21:06:56Z      (≈ 2 seconds after send return)
subscribed       = false
```

Production log lines (captured live):

```
[eb5fb87a-…] [SNS] received event_type="Bounce" team=1 topic=arn:aws:sns:us-east-1:367541997824:lewsnetter-ses-bounces
[eb5fb87a-…] [SNS:bounce] team=1 email=bounce@simulator.amazonses.com unsubscribed (permanent)
```

## What we changed to make it work

The first two attempts (documented in the Background section below) had the
notification arriving + the controller processing the POST + returning 200,
but no per-recipient handler ever firing. Root cause: **SES Event Publishing
delivers payloads keyed on `eventType` (capital-T), while the controller
was case-matching on `notificationType`** — the legacy SNS-direct shape from
SES's pre-2018 notifications. With Configuration Set event destinations,
the actual JSON shape is:

```json
{
  "eventType": "Bounce",
  "mail":   { ... },
  "bounce": { "bounceType": "Permanent", "bouncedRecipients": [...], ... }
}
```

Fixed in `544c5fb` ("SnsController: handle SES Event Publishing payloads
(eventType)") — see `app/controllers/webhooks/ses/sns_controller.rb`. The
controller now reads `eventType` first, falls back to `notificationType`
for legacy SNS-direct payloads, and added `[SNS] received` observability
at the top of every notification so future regressions surface in seconds.

## SNS topic + configuration set wiring

- Bounce topic ARN (from `Team.first.ses_configuration.sns_bounce_topic_arn`):
  `arn:aws:sns:us-east-1:367541997824:lewsnetter-ses-bounces`
- Complaint topic ARN:
  `arn:aws:sns:us-east-1:367541997824:lewsnetter-ses-complaints`
- Configuration set: `lewsnetter-default`
- Event destinations on the config set:
  - `lewsnetter-bounces` → `BOUNCE, REJECT, RENDERING_FAILURE` → bounces topic
  - `lewsnetter-complaints` → `COMPLAINT` → complaints topic
- Both topic subscriptions are HTTPS, both auto-confirmed by the webhook's
  SubscriptionConfirmation handler when their topic ARN matched a
  `Team::SesConfiguration` row.

## Sender identity

`bruno@curbly.com` — verified in SES (us-east-1), sending enabled,
production access on, `bounce@simulator.amazonses.com` not on the
account suppression list.

## What was cleaned up

- Test subscriber `bounce@simulator.amazonses.com` (the one used for both
  rounds of verification) was destroyed at the end. The real
  `bruno.bornsztein@gmail.com` row was left intact.
- `Team.first.campaigns.first` left in `status: :draft` (its original
  state had been `:sent`; safe to flip back when convenient).

---

## Background — why the first attempt was blocked

Two end-to-end attempts on the original (pre-fix) controller did **not**
flip `Subscriber#bounced_at` within the polling window (90s on attempt 1,
180s on attempt 2). All upstream layers worked:

| Layer | Evidence |
|---|---|
| SesSender returned real SES IDs (not stubs) | `0100019e1ded1a87-…` and `0100019e1df232c0-…`, `failed=[]` |
| SES generated bounces | `get-send-statistics` showed `Bounces: 2` in the test window |
| SNS delivered to webhook | kamal-proxy logged two POSTs from `Amazon Simple Notification Service Agent`, both returned 200 |
| Controller accepted the request | `[SNS] Started POST /webhooks/ses/sns` + `Completed 200 OK in 109ms` |

But the per-recipient code path never ran — no `[SNS:bounce]` log line,
`bounced_at` stayed `nil`. Diagnosis was blocked because the controller's
`handle_notification` had no observability on what `eventType` /
`notificationType` it actually received.

**The fix:** add a `[SNS] received event_type=…` log line at the top of
`handle_notification` AND switch the case statement to read `eventType`
(Event Publishing) with a fallback to `notificationType` (legacy SNS-direct).
Both attempts after the deploy succeeded on the first poll, with the new
observability line proving the event type and topic on every request.

## Surprises / observations carried forward

1. **`mailkick_subscriptions` table is half-installed.** The table exists
   but has no `email` column, so the brief's `Mailkick::Subscription.where(email: …)`
   sanity check raised `SQLite3::SQLException: no such column`. In this app,
   `Subscriber#subscribed` and `Subscriber#bounced_at` are the durable
   suppression markers. Worth a follow-up task to either complete the
   mailkick wiring or remove the gem.
2. **`Subscriber#inspect` is hiding fields** (returns `#<Subscriber id: 2>`).
   `attributes.to_json` is the workaround when ops needs to see real values.
3. **SES Event Publishing vs SNS-direct payload shapes** are different.
   The fix accommodates both, but going forward, configuration-set-based
   event destinations are the canonical path (we never publish via the
   pre-2018 SNS-direct mechanism in this codebase).

## Repro recipe (for future regressions)

1. SSH to production: `ssh -i ~/.ssh/lewsnetter_deploy root@178.156.185.100`.
2. Open a rails runner inside the running web container:
   ```
   docker exec $(docker ps --filter 'name=lewsnetter-web' --filter 'status=running' --format '{{.Names}}' | head -1) ./bin/rails runner '
     team = Team.first
     sub  = team.subscribers.find_or_create_by!(email: "bounce@simulator.amazonses.com") do |s|
       s.external_id = "bounce_test_#{Time.now.to_i}"
       s.name = "Bounce Test"
       s.subscribed = true
     end
     sub.update!(subscribed: true, bounced_at: nil)
     campaign = team.campaigns.first
     campaign.update!(status: :draft, stats: {}, sent_at: nil)
     result = SesSender.send_bulk(campaign: campaign, subscribers: [sub])
     puts result.message_ids.inspect
   '
   ```
3. Poll until `bounced_at` flips:
   ```
   docker exec ... ./bin/rails runner 'puts Subscriber.find_by(email: "bounce@simulator.amazonses.com")&.attributes&.slice("subscribed", "bounced_at").to_json'
   ```
4. Grep logs:
   ```
   docker logs $(docker ps --filter 'name=lewsnetter-web' --format '{{.Names}}' | head -1) 2>&1 | grep -E 'SNS.*event_type|SNS:bounce' | tail -5
   ```
5. Clean up: destroy the test subscriber.
