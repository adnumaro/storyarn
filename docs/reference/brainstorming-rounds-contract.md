# Brainstorming rounds

> Owner: Engineering
> Last reviewed: 2026-09-15
> Scope: ENG-136, rounds redesign (PR #164)

Every session has at least one round: Round 1 is born with the session. Rounds
are horizontal bands of the session canvas, stacked in order; timers,
publication and creative states remain independent controls. Privacy belongs to
the round: the round in progress can be private, and nothing about it is
inherited by the next round.

## Lifecycle and authority

The facilitator or project owner with current edit permission starts the next
round with `new_round/5`, one step that closes the round in progress and opens
the next one with an optional question, and closes the round in progress without
opening another with `close_round/5`, for the convergence at the end. A session
has one round in progress until it is closed, never more than one, and a closed
round cannot be reopened. There are no planned or cancelled rounds; recovery
inventories before version 7 drop them on normalization. Creating the next round
preserves all previous notes, their current state, authorship and visibility.

The question of the round in progress is edited in place on its header
(`update_round/6`). An unchanged question with the current session revision does
not append another revision. Closed questions are stable.

Each lifecycle command enters the existing Project access locks and session
lock, checks the caller's session revision, and commits the new round state and
session revision together. Subscribers receive the existing content-free session
invalidation. No polling or background task executes round transitions.

Question editing retains the revision at which editing began. If the session
changes meanwhile, the canvas preserves the draft and asks the facilitator to
compare it with the current question before explicitly replacing it.

Closing a round never reveals notes, prevents editing, changes creative state,
starts a timer or creates another round. Archived/replaced sessions keep their
existing lifecycle restrictions. All members with current read access can read
round metadata; a prompt is shared session context, not a private draft.

## Privacy

Each round has two settings, `private` and `reveal_on_expiry`, both `false` by
default and never copied from the previous round or from the session. The
facilitator or project owner with current edit permission changes them through
`set_round_privacy/6`, from the settings menu of the round in progress. The
change requires the caller's session revision and records a `round_updated`
session revision. A closed round can only be set to not private; a round that
has already been revealed rejects `private: true` with `round_revealed`.

While a round is private, its contributions stay with their authors. Every other
participant, the facilitator included, reads that round's other notes as
placeholders: identity, round and canvas position/width only, with no text,
author or state. A placeholder stands only for what the reveal will show: a
draft nobody consented to publish, a discarded note or a note without a place
on the canvas has none. A group of a private round is hidden with its notes,
comment thread included. Groups, comments and decision sources of that round are
unavailable until the reveal, and cursors are not shared while the round in
progress is private. A canvas save in a private round does not publish; a save
in a shared round publishes atomically as before.

Setting `private: false` on a private round is the reveal, also exposed as
`reveal_round/5`. It stamps `revealed_at` and, in the same transaction under the
contribution lock, publishes the round's consenting, non-discarded contributions
that still have an author. The timer performs the same reveal when it reaches
0:00 for every private round with `reveal_on_expiry`: the round in progress and
any round closed since the clock started. A reveal is irreversible. Archiving a
session ends the mask of every private round for good: each counts as revealed
without publishing anything, and after reopening it cannot be made private again.

## Bands

Nothing about a band's height is stored. The canvas measures each band from its
lowest note or group frame, with a floor for empty bands, and derives every
header offset from that, so a band grows as content lands below it and pushes
the later rounds down. Note and group positions are stored relative to their
round header (`y >= 0`); a placement above the header is rejected with
`outside_band`. The band under a new note decides its round. The canvas loads
every round of the session through one authorized context query, without
pagination.

## Contribution provenance

Each idea receives an immutable `round_id` and `late_contribution` when first
saved. An omitted round selects the round in progress under the same session
lock; an explicit `null` is rejected with `round_required`. An explicit round
must belong to that session. A first save targeting a closed round is marked
late; edits to an existing note never change its round or late flag.

The canvas captures the active round when beginning a local note,
so a delayed first save remains attributed to the round in which writing began.
Uncertain retries preserve that target and the complete original creation
request. Retrying a committed creation returns the original note without
recalculating its provenance after subsequent round transitions.

This provenance is creative context selected by an authorized collaborator,
not proof of when they began writing. Explicit no-round and closed-round targets
remain supported for delayed or asynchronous work.

Creation-request identity distinguishes omitted and explicit-null round values.
Existing request fingerprints without a round field remain compatible. The
recovery compartment remaps round references, while receipt fingerprints retain
the original request identity.

A note never changes round. **Bring to the active round** (`bring_idea_forward/5`) is
the only way an idea crosses rounds: a new note of the actor's own under the
header in progress, copying the title, body and look of the revision the actor
can read, linked to it through `source_idea_id`/`source_revision`. The original
stays where it was, in its state; a parked original with a copy ahead no longer
counts as waiting for later. The copy follows the canvas contribution policy
(shared unless the round in progress is private), takes the placement the caller
gives it inside the band (`y >= 0`, the original's look otherwise), needs open
contributions, a readable source and a source outside the round in progress
(`same_round`), and replays its request key like any creation.

Existing canvas links can still connect readable notes across rounds without
copying their content. They are visual relationships, not provenance. Link
endpoints remain subject to the reader's current privacy rules.

## Reading and publication

The idea list and counts accept all rounds, no round, or one authorized
session round. Filtering applies before pagination and after the normal
visibility boundary. A round never grants access to another author's private
draft, including its text, counts or connections.

The canvas reads every round and the round in progress through a single
authorized context query. No access decision or private note is cached across
requests. Refreshes follow collaboration events, reconnection and returning to
the tab; there is no periodic 20-second poll.

A prepared reveal retains its frozen manifest. Closing a round or saving a late
note never adds that note to an already prepared or completed reveal. New
contributions still follow the session's current publication policy; round
transitions do not override it.

## Recovery

The encrypted Project snapshot inventory includes round records, prompts,
lifecycle state/timestamps, header-relative positions and idea membership/late
markers. Reconstitution validates the graph before writing, remaps round IDs and
preserves privacy. Repeated restoration reuses identical generations. Old
inventories without rounds gain a first round on normalization, and inventories
before version 7 drop their planned and cancelled rounds. Inventories before
version 8 carry no round privacy: normalization marks the active round of a
session that used the former session-wide private mode as private, with no
reveal-on-expiry and no reveal timestamp, and strips that session key. See
[recovery](brainstorming-recovery-contract.md) for archive and retention details.
