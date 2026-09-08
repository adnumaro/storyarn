# Independent brainstorming timer

> Owner: Engineering
>
> Last reviewed: 2026-09-08
>
> Scope: ENG-137

## Product behavior

A session can have one shared countdown. It is independent of optional rounds and
private mode: starting, pausing, extending or cancelling the clock never creates,
starts or closes a round. A round never starts or stops a clock. Session archive
cancels a running or paused timer; reopening does not restart it.

The existing board header shows the same deadline to all participants, including
viewers. A facilitator or project owner with current edit permission can start,
pause, resume, extend or cancel it. Durations range from 15 seconds to 24 hours;
extensions keep the accumulated duration within 24 hours. A paused clock may
have fewer than 15 seconds remaining and can resume that exact remainder.

The default expiry only marks the clock finished. Two independent options are
off by default:

- End private mode when the clock expires, using the existing session reveal
  policy. This option requires private mode when starting or resuming the clock.
- Close new contributions when the clock expires.

Ending private mode uses current eligible heads, including notes created during
the countdown. Discarded notes, missing authors and legacy author-only consent
remain excluded from assisted publication. It does not republish an old prepared
reveal or bypass publication consent.

Closing contributions blocks new notes, duplication and pasting new cards. It
preserves editing, moving, deleting and undoing a matching deletion of existing
notes. Replaying an already committed creation still returns its original
receipt. A manager can reopen contributions explicitly without starting a timer.
It does not archive the session or change a round's state.

## Persisted state and execution

Sessions owns `ideation_timers` and `sessions.contributions_open`. The timer row
has a stable identity, monotonically increasing version, status, UTC deadline,
last saved remaining duration, original duration plus extensions, initiating
actor, configuration version and independent expiry options. A new start after
completion reuses the timer row and increments its version. Terminal outcomes
are completed, skipped authorization, skipped configuration or skipped session.

Every control checks current Project edit access, current session management
responsibility and the caller's session revision. Controls on an existing timer
also require its version. Pause, extension, cancellation, restart and expiry
invalidate older scheduled messages. Resume renews the initiating actor and
configuration after current authorization; extension does not silently renew
an actor or policy that has changed since the timer was started.

Expiry rechecks the persisted version and deadline under the session lifecycle
lock, then current actor access, managerial responsibility and configuration.
If authority or configuration changed, it records a skipped outcome and performs
neither optional action. Reveal, contribution closure, timer completion and the
session audit commit in one transaction. Concurrent deliveries cannot publish
or apply either action twice. Repeated and stale deliveries are harmless.

The actorless expiry port is sealed to its worker; Web code uses only authorized
controls. The runtime invokes the same command within the owning capability.
Public board projections omit actor identity, recovery identity and internal
policy version. Countdown updates are local; a browser reaching zero requests
one fresh board state and never applies expiry actions itself.

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

The inner recovery inventory is version 3. It includes the timer, options,
outcome, contribution gate and session audit. Version 1 and 2 inventories remain
accepted, normalizing to no timer and open contributions.

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
