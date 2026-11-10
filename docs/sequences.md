# Sequences

Automated multi-step email flows (the Intercom Series replacement). A
sequence has a trigger, an ordered list of steps (each an email with a wait),
and optional exit and re-entry rules.

## Turning it on

Sequences are gated per team by `teams.sequences_enabled` (off by default).
With the flag off the UI 404s, nothing enrolls and nothing sends, whatever a
sequence's own status says.

- Avo: Teams → edit → **Sequences enabled**.
- Console: `Team.find(id).update!(sequences_enabled: true)`.

## How a subscriber moves through

1. **Enroll.**
   - *Event trigger*: a tracked event (`POST /api/v1/teams/:team_id/events/track`,
     or `LewsnetterRails.track`) with the sequence's event name enrolls the
     subscriber. Events whose `occurred_at` is more than 24 hours old don't
     enroll, so backfills don't fire sequences.
   - *Segment trigger*: `SegmentEnrollmentSweepJob` runs hourly and enrolls
     everyone who matches the trigger segment.
2. **Wait, then send.** Step 1's wait counts from enrollment; each later
   step's wait counts from the previous send. `SequenceDispatchJob` runs every
   minute and hands due enrollments to `SequenceStepSendJob`.
3. **Before every step** the subscriber is checked: unsubscribed → exits
   (`unsubscribed`); on the suppression list → `suppressed`; in the exit
   segment → exits (`exit_segment`); in the step's skip segment → the step is
   skipped (counted) and the next one is scheduled.
4. **Finish.** After the last step the enrollment is `completed`. With a
   *wait after last step* it stays active that long first (so a goal or exit
   segment can still take it out), then completes. *Tag on finish* tags
   everyone who completes.

The hourly sweep also exits active enrollments that have entered the exit
segment between sends.

Nobody enrolls who is unsubscribed, suppressed, already in the exit segment,
already active in the sequence, or has ever been enrolled in one of the
sequences listed under *Not if enrolled in*.

## Goals, tags and step actions

- **Tags** live on the subscriber (`subscribers.tags`), separate from
  `custom_attributes`, so the app sync doesn't wipe them. Segment rules can
  filter on them (*Tags contains …*), which makes them usable in trigger,
  exit, skip and goal segments.
- **Goal.** A sequence goal is a segment, an event name, or both. It is "hit"
  when the subscriber is in the goal segment or tracks the goal event after
  the step was sent.
- **Tag when sent** tags the subscriber as each step sends.
- **Step action.** *On goal hit* or *on link clicked* (a human click on a link
  in that step's email), add a tag, exit the sequence, or both. The action is
  checked hourly and once more just before the next step sends; after the
  last step it is checked only during the *wait after last step*.

This is how Intercom Series branches flatten: "if goal → tag and exit" is a
step action, "send only if not X" is a skip segment, and "no goal by the end →
tag" is a finish wait plus tag on finish.

## Relative dates in segments

*Within the last N days* and *more than N days ago* are evaluated when the
segment runs, not when it's saved. Epoch-second attributes whose key ends in
`_at` (for example `last_active_at`) get the same day-window operators.

## Importing Intercom Series

`bin/rails sequences:import_intercom_series TEAM_ID=… EXPORT_DIR=… SPEC=spec.yml
SENDER_ADDRESS_ID=… [EMAIL_TEMPLATE_ID=…]` reads a Series export (one JSON per
series) and a YAML spec that says how each series flattens (segments to create,
trigger, exclusions, goal, steps with their ruleset ids, waits, skip segments,
tags and actions). Email bodies convert to Markdown and Intercom merge tags
(`{{custom_data.x|fallback:"y"}}`, URL-encoded tags) are rewritten. Sequences
are created as drafts; nothing sends until someone activates them. Rerunning
skips series that already exist. See `Sequences::IntercomSeriesImporter`.

## Re-entry

- Blank re-entry days: once per subscriber, ever.
- `N` days: may enroll again once the previous enrollment started at least
  `N` days ago (and isn't still active).

## Sending

Each step owns a hidden backing campaign (status `sequence`, not listed with
regular campaigns) and sends through the same SES path as campaigns. Opens,
clicks, bounces, complaints and unsubscribe links all work as they do for
campaigns, and every `Delivery` carries `sequence_step_id`. A failed send is
retried hourly up to 3 times, then the enrollment exits with `send_failed`.

Pausing a sequence holds enrollments where they are; activating it again
resumes them. A sequence needs a sender address and at least one step to
activate.

Removing a step moves anyone waiting on it to the next step.

## Stats

The sequence page shows enrollment counts by state (with exit reasons) and,
per step: waiting, sent, delivered, opened, clicked, bounced, unsubscribed and
skipped. The same numbers are available over MCP via `sequences_list` and
`sequences_stats`.
