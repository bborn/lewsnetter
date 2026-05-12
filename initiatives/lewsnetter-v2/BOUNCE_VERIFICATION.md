# Bounce Simulator Round-Trip Verification

**Status: BLOCKED — round-trip did NOT close.**

## Summary

Two end-to-end attempts against `bounce@simulator.amazonses.com` from
production did **not** flip `Subscriber#bounced_at` within the polling
window (90s on attempt 1, 180s on attempt 2). The SES send is real (real
message IDs, no stubs). SES recognizes the result as a bounce (account-level
`get-send-statistics` shows `Bounces: 2`). SNS delivered notifications to
our webhook endpoint (kamal-proxy logged two POSTs from
`Amazon Simple Notification Service Agent`, both returned 200). But the
controller never logged `[SNS:bounce] team=1 email=… unsubscribed
(permanent)` — so the per-recipient handler either never ran, or ran and
took no action because `bounceType` wasn't `"Permanent"` (or the
recipient lookup failed).

The most suspicious signal: both SNS POSTs arrived **~0.6 seconds** after
the SES send returned, which is far faster than a real Internet round-trip
to a bouncing recipient. Possible reasons:

1. The notification really is a `Bounce` but with `bounceType` other than
   `"Permanent"` (e.g. `Undetermined`), so `handle_bounce` exits early at
   line 94 of `app/controllers/webhooks/ses/sns_controller.rb`. SES often
   delivers the simulator bounce as `Permanent`, but the wire shape on
   this account hasn't been confirmed.
2. The notification might be a `Reject` (the bounces configuration set
   event destination has `BOUNCE`, `REJECT`, `RENDERING_FAILURE` enabled).
   The controller's case statement has no branch for `"Reject"`, so it
   silently does nothing. But the SES sending statistics show `Rejects: 0`
   and `Bounces: 2`, which contradicts this theory.
3. The recipient email lookup at line 99 (`team.subscribers.find_by(email:
   email)`) missed for some reason (case mismatch is unlikely — the
   controller already downcases — but the simulator reply could carry the
   address in an unexpected wrapper).

Without seeing the raw notification body, the ambiguity can't be resolved
non-invasively. The next step the controller follow-up should take is to
add a debug log of `payload["Message"]` (or at least
`message["notificationType"]` + `bounce["bounceType"]`) inside
`handle_notification`, redeploy, and re-run the simulator.

## Timeline

| Marker | Value |
|---|---|
| Attempt 1 — subscriber created (t0) | `2026-05-12T20:42:17.683821Z` |
| Attempt 1 — `SesSender.send_bulk` started | `2026-05-12T20:42:17.742360Z` |
| Attempt 1 — `SesSender.send_bulk` finished | `2026-05-12T20:42:18.725794Z` |
| Attempt 1 — SNS POST hit kamal-proxy | `2026-05-12T20:42:19.343150Z` |
| Attempt 1 — poll gave up at iter=29 | `2026-05-12T20:44:43Z` (150s, no bounce) |
| Attempt 2 — `SesSender.send_bulk` started | `2026-05-12T20:47:51.651120Z` |
| Attempt 2 — `SesSender.send_bulk` finished | `2026-05-12T20:47:52.599732Z` |
| Attempt 2 — SNS POST hit kamal-proxy | `2026-05-12T20:47:53.261071Z` |
| Attempt 2 — poll gave up at iter=35 | `2026-05-12T20:50:47Z` (180s, no bounce) |
| Subscriber state when cleanup ran | `bounced_at=nil, subscribed=true` |

Total latency: **N/A — bounce never landed in the database on either run.**

## Real SES message_ids

These are full-format SES IDs (`01000...-uuid-000000`), not stubs:

- Attempt 1: `0100019e1ded1a87-a6ed5634-d8d8-49de-a308-ce570e5ed564-000000`
- Attempt 2: `0100019e1df232c0-b020be1a-b21d-4d01-861b-2bd489fb1938-000000`

`SesSender#send_bulk` returned `failed=[]` both times, so SES accepted the
sends.

## SES sending statistics (account-level confirmation)

After the second attempt:

```
| Bounces | Complaints | DeliveryAttempts | Rejects |        Timestamp           |
|   2     |    0       |       0          |    0    | 2026-05-12T20:36:00+00:00  |
```

SES sees both sends as bounces. This rules out the test sends silently
dropping; the bounce event was generated upstream of our webhook.

## SNS topic + configuration set

Both match the brief.

- Bounce topic ARN (from `Team.first.ses_configuration.sns_bounce_topic_arn`):
  `arn:aws:sns:us-east-1:367541997824:lewsnetter-ses-bounces`
- Complaint topic ARN (from `…sns_complaint_topic_arn`):
  `arn:aws:sns:us-east-1:367541997824:lewsnetter-ses-complaints`
- Configuration set name (from `…configuration_set_name`): `lewsnetter-default`
- Bounce-topic subscription:
  `arn:aws:sns:us-east-1:367541997824:lewsnetter-ses-bounces:bd6470e9-edfd-4772-817b-185ff1c25bdb`
  → `https://lewsnetter.whinynil.co/webhooks/ses/sns`
- Complaint-topic subscription:
  `arn:aws:sns:us-east-1:367541997824:lewsnetter-ses-complaints:e324d61e-271c-4534-ad4e-8e86aad4c182`
  → same URL
- Configuration set event destinations:
  - `lewsnetter-bounces` enabled, matches `BOUNCE,REJECT,RENDERING_FAILURE`,
    routes to the bounces topic.
  - `lewsnetter-complaints` enabled, matches `COMPLAINT`, routes to the
    complaints topic.
- `bounce@simulator.amazonses.com` is NOT on the account suppression list
  (`sesv2 get-suppressed-destination` returns NotFoundException).
- Sender identity `bruno@curbly.com` is verified, sending enabled,
  production access on.

## What the webhook DID see

Both notifications were delivered by SNS, accepted (200) by kamal-proxy,
and reached `Webhooks::Ses::SnsController#create`:

Attempt 1 (kamal-proxy log line, abridged):
```
{"time":"2026-05-12T20:42:19.343150249Z","msg":"Request","path":"/webhooks/ses/sns",
 "request_id":"35280b52-ed39-496a-837c-6e527685b544","status":200,
 "service":"lewsnetter-web","target":"2452b194913f:3000",
 "duration":135550654,"method":"POST","req_content_length":2849,
 "req_content_type":"text/plain; charset=UTF-8",
 "user_agent":"Amazon Simple Notification Service Agent",
 "remote_addr":"15.221.160.7"}
```

Attempt 2 (kamal-proxy log line, abridged):
```
{"time":"2026-05-12T20:47:53.261070956Z","msg":"Request","path":"/webhooks/ses/sns",
 "request_id":"c9fbe09e-fc43-4ec9-bffa-35887f505583","status":200,
 "service":"lewsnetter-web","target":"2452b194913f:3000",
 "duration":29261973,"method":"POST","req_content_length":2851,
 "user_agent":"Amazon Simple Notification Service Agent",
 "remote_addr":"15.221.161.37"}
```

Inside `lewsnetter-web` for the same two request IDs:
```
[35280b52-ed39-496a-837c-6e527685b544] Started POST "/webhooks/ses/sns" for 172.71.222.190 at 2026-05-12 20:42:19 +0000
[35280b52-ed39-496a-837c-6e527685b544] Processing by Webhooks::Ses::SnsController#create as HTML
[35280b52-ed39-496a-837c-6e527685b544] Completed 200 OK in 109ms (ActiveRecord: 5.6ms (2 queries, 0 cached) | GC: 0.2ms)

[c9fbe09e-fc43-4ec9-bffa-35887f505583] Started POST "/webhooks/ses/sns" for 172.70.174.46 at 2026-05-12 20:47:53 +0000
```

## What the webhook DID NOT see

The expected log line:

```
[SNS:bounce] team=1 email=bounce@simulator.amazonses.com unsubscribed (permanent)
```

…never appeared in `docker logs lewsnetter-web` during either attempt
(the same is true for `[SNS:complaint]` and `[SNS:delivery]`). The
controller ran (2 ActiveRecord queries in the 5.6ms — that's
`Team::SesConfiguration` topic-ARN lookup, then nothing else), but
neither `handle_bounce` nor `handle_complaint` reached the
`subscriber.update!` line, and `handle_notification`'s case statement
either didn't match (`Reject` or another type) or matched `Bounce` with
`bounceType != "Permanent"` (early return at line 94).

No errors/warnings in the container's stderr for the test window.

## Surprises / observations

1. **The SNS POST arrives 0.6 seconds after the SES send returns.** A
   real bounce simulator round-trip is normally 5–60 seconds. This is the
   strongest signal that what's hitting our webhook is *not* the
   `Permanent`/`Transient` Bounce shape `handle_bounce` expects. The
   simulator may be returning a synchronous `Reject` for sandbox-style
   reasons, or the `Bounce` payload SES synthesizes for the simulator
   address may have a `bounceType` we don't handle.
2. **Both POST bodies are essentially identical in size** (2849 vs 2851
   bytes), suggesting they're the same event type for the same payload.
3. **The mailkick sanity check failed**: the SQLite production DB has a
   `mailkick_subscriptions` table but it does NOT have an `email` column,
   so `Mailkick::Subscription.where(email: …)` raised
   `SQLite3::SQLException: no such column: mailkick_subscriptions.email`.
   This means the brief's expectation that "mailkick subscription record
   vs the subscriber column flag — both should reflect unsubscribed" is
   probably stale: in this app `Subscriber#subscribed` and
   `Subscriber#bounced_at` are the only durable suppression markers.
   Worth flagging to the controller — the mailkick integration may have
   never been wired in this build, or it's keyed off something other than
   `email`.
4. **`Subscriber#inspect` is hiding fields** (returns `#<Subscriber id:
   2>`); had to use `attributes.to_json` to see real column values. Not
   wrong, just slowed the loop. Worth knowing for future ops.
5. **No source code was changed** during this verification. The next
   investigator needs ONE temporary log line —
   `Rails.logger.info("[SNS:debug] type=#{message["notificationType"]} bounceType=#{(message["bounce"]||{})["bounceType"]} body=#{payload["Message"][0,500]}")`
   in `handle_notification` — to see what SES is actually publishing.
   That single log line will close this loop in one more send.

## What was cleaned up

- Test subscriber `bounce@simulator.amazonses.com` (id=2, team_id=1,
  external_id=`bounce_test_1778618537`) was destroyed via
  `Subscriber.find_by(email: …)&.destroy!`. Verified the real
  `bruno.bornsztein@gmail.com` subscriber row was left alone.
- `Team.first.campaigns.first` was left in `status: :draft`. It was
  `:sent` before this verification and was reset to draft so SesSender
  would target the test recipient. It is safe to set back to `:sent` if
  desired; no email body was modified.

## Repro recipe for the next investigator

1. SSH: `ssh -i ~/.ssh/lewsnetter_deploy root@178.156.185.100`.
2. Add ONE temporary log line in
   `app/controllers/webhooks/ses/sns_controller.rb#handle_notification`
   that dumps `message["notificationType"]`,
   `(message["bounce"] || {})["bounceType"]`, and the first 500 chars of
   `payload["Message"]`. Redeploy.
3. Rerun the workflow in this doc (subscriber create → reset campaign
   → `SesSender.send_bulk` → poll). The next SNS POST will reveal
   exactly which branch is misbehaving.
4. Revert the log line before merging.
