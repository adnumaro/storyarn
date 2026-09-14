# Independent brainstorming timer

> Owner: Engineering
>
> Last reviewed: 2026-09-15
>
> Scope: ENG-137

## Product behavior

A session can have one shared countdown. It is independent of optional rounds and
round privacy: starting, pausing, extending or cancelling the clock never creates,
starts, closes or reveals a round on its own. A round never starts or stops a clock. Session archive
cancels a running or paused timer; reopening does not restart it.
Recovering a session replaced by a snapshot also cancels its old timer before
archiving it. Reopening that generation cannot reactivate an old expiry job.

The header of the round in progress shows the same digits to all participants,
including viewers; the board header keeps a compact chip with the same countdown.
A facilitator or project owner with current edit permission types a duration into
the digits (minutes, `m:ss` or `h:mm:ss`) and presses play or Enter, then can
pause, resume, add one minute or cancel beside them. Durations range from 1
second to 24 hours; extensions keep the accumulated duration within 24 hours. A
paused clock resumes its exact remainder. Cancelling is available at any moment
while the round is in progress, so a running clock is reset by cancelling and
starting again. Reaching 0:00 is the whole signal in the round header: the
digits stay at 0:00, muted, without a message, and become editable again for
the facilitator.

Expiry marks the clock finished and then applies what was asked of it:

- If the round in progress is private and its own **Reveal when time is up**
  setting is on, expiry reveals that round with the same publication policy as
  the manual reveal. This is a round setting from the round header's settings
  menu, not a timer option.
- If the timer was started with `close_contributions_on_expiry`, expiry closes
  new contributions. The current UI does not offer this option.

`start_timer` accepts `seconds` (1–86,400) and the optional boolean
`close_contributions_on_expiry`, `false` when omitted and rejected when not
boolean. The timer row carries no reveal flag of its own: the reveal follows the
round's setting. Recovery inventory version 8 drops the old timer flag from
timer rows and from the timer snapshots of session revisions. The UI always
sends `close_contributions_on_expiry` as `false`.

Revealing the round publishes the current heads of its consenting contributions,
including notes created during the countdown. Discarded notes, missing authors
and legacy author-only consent remain excluded from assisted publication. It
does not republish an old prepared reveal or bypass publication consent, and a
revealed round cannot become private again.

Closing contributions blocks new notes, duplication and pasting new cards. It
preserves editing, moving, deleting and undoing a matching deletion of existing
notes. Replaying an already committed creation still returns its original
receipt. Closing and reopening contributions is a session action offered from
the timer chip; a manager can use it without starting a timer. It does not
archive the session or change a round's state.

## Persisted state and execution

Sessions owns `ideation_timers` and `sessions.contributions_open`. The timer row
has a stable identity, monotonically increasing version, status, UTC deadline,
last saved remaining duration, original duration plus extensions, initiating
actor, configuration version and the two persisted expiry flags. A new start after
completion reuses the timer row and increments its version. Terminal outcomes
are completed, skipped authorization, skipped configuration or skipped session.

Every control checks current Project edit access, current session management
responsibility and the caller's session revision. Controls on an existing timer
also require its version. Pause, extension, cancellation, restart and expiry
invalidate older scheduled messages. Resume renews the initiating actor and
configuration after current authorization; extension does not silently renew
an actor or policy that has changed since the timer was started.

A backward server-clock correction cannot increase saved remaining time beyond
the configured duration or put a completion timestamp before its start. Pausing,
extending and completing remain valid for persistence and snapshot capture.

Expiry rechecks the persisted version and deadline under the session lifecycle
lock, then current actor access, managerial responsibility and configuration.
If authority or configuration changed, it records a skipped outcome and performs
neither the round reveal nor the contribution closure. Reveal, contribution
closure, timer completion and the session audit commit in one transaction. Concurrent deliveries cannot publish
or apply either action twice. Repeated and stale deliveries are harmless.

The actorless expiry port is sealed to its worker; Web code uses only authorized
controls. The runtime invokes the same command within the owning capability.
Public board projections omit actor identity, recovery identity and internal
policy version. Countdown updates are local; a browser reaching zero requests
one fresh board state and never applies expiry actions itself.
The header recalibrates from individual clock fields when LiveVue patches props
in place. Controls wait for the acknowledged session revision and timer version
to be rendered before accepting another write; pausing and resuming preserve
the focused button.

## Scheduling and recovery after failure

A supervised runtime subscribes before its initial read and schedules the nearest
persisted deadline. It rereads on startup, schedule invalidation and completion,
handles system-clock offset changes, and stops scheduling when no timers remain.
There are no per-second database queries or idle timer polls. Reads and expiry
transactions execute outside the scheduler process, with bounded concurrency and
backoff so a slow transaction cannot block cancellation or a newer deadline.
Multiple application nodes can deliver the same deadline safely.

Every running timer version also writes a scheduled Oban job in the same
transaction. The runtime normally delivers at the deadline, including while all
browsers are closed. A process/application restart rereads persisted deadlines.
If a post-commit notification is lost while the runtime stays alive, Oban supplies
the durable fallback. That exceptional path retains the application's existing
15-minute staging cadence, plus queue/retry delay; it is not a strict real-time
guarantee during infrastructure failure. This feature does not increase global
Oban polling or keep an otherwise idle database awake with timer polls.

## Snapshots

The inner recovery inventory is version 8; timers joined it in version 3. It
includes the timer, its persisted flags, outcome, contribution gate and session
audit. Version 1 and 2 inventories remain accepted, normalizing to no timer and
open contributions. Timer validation accepts durations from 1 to 86,400 seconds.

Capture uses persisted values only. It does not rewrite remaining duration from
the wall clock, which would make an unchanged project's canonical digest vary
every second. Restoring a running timer clears its deadline, increments its
version and pauses it at the last saved remaining duration. Restored paused or
terminal timers retain their state. No restoration starts a job or invokes
publication. Explicit resume reauthorizes the operation and writes a new deadline.

Generation matching uses this same pure normalization. Restoring identical data
reuses the existing paused generation, including when the original running row
still exists; its obsolete delivery cannot execute. Actor and session references
are remapped through the existing recovery identity contract. Malformed lifecycle
state, duplicate timers for one session and invalid references are rejected
before changing the project.

See [privacy and recovery](brainstorming-recovery-contract.md) and
[round independence](brainstorming-rounds-contract.md).
