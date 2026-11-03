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
4. **Finish.** After the last step the enrollment is `completed`.

The hourly sweep also exits active enrollments that have entered the exit
segment between sends.

Nobody enrolls who is unsubscribed, suppressed, already in the exit segment,
or already active in the sequence.

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
