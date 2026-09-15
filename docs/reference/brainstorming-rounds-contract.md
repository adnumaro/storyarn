# Optional brainstorming rounds

> Owner: Engineering
> Last reviewed: 2026-09-15
> Scope: ENG-136

Sessions can receive ideas before, between and during rounds. Rounds are
optional iterations within the same session; timers, publication and creative
states remain independent controls. Privacy belongs to the round: the round in
progress can be private, and nothing about it is inherited by the next round.

## Lifecycle and authority

The facilitator or project owner with current edit permission can create a
planned round with an optional shared prompt, start it and close it. A session
has at most one active round. Planned rounds accept no contributions; a closed
round cannot be started again. Creating the next round preserves all previous
notes, their current state, authorship and visibility.

Before starting, the facilitator can correct or clear the question and cancel
an accidental round. Cancellation retains its identity, question and session
record with status `cancelled`; it never starts a round or creates contributions.
Cancelled rounds cannot be edited, started or receive late contributions. An
unchanged question or repeated cancellation with the current session revision
does not append another revision. Already active or closed questions are stable.

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
author or state. Groups, comments and decision sources of that round are
unavailable until the reveal, and cursors are not shared while the round in
progress is private. A canvas save in a private round does not publish; a save
in a shared round publishes atomically as before.

Setting `private: false` on a private round is the reveal, also exposed as
`reveal_round/5`. It stamps `revealed_at` and, in the same transaction under the
contribution lock, publishes the round's consenting, non-discarded contributions
that still have an author. The timer performs the same reveal when it reaches
0:00 and the round in progress has `reveal_on_expiry`. A reveal is irreversible.
Archiving a session ends the mask of every private round without revealing
anything, and reopening does not restore it.

## Contribution provenance

Each idea receives an immutable nullable `round_id` and `late_contribution` when
first saved. An omitted round selects the active round under the same session
lock; an explicit `null` selects no round. An explicit active or closed round
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

A note never changes round. **Bring to this round** (`bring_idea_forward/5`) is
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

The canvas reads its history range, active round and referenced/selected rounds
through a single authorized context query. Expanding history does not repeat
authorization for each page. No access decision or private note is cached across
requests. Refreshes follow collaboration events, reconnection and returning to
the tab; there is no periodic 20-second poll.

A prepared reveal retains its frozen manifest. Closing a round or saving a late
note never adds that note to an already prepared or completed reveal. New
contributions still follow the session's current publication policy; round
transitions do not override it.

## Recovery

The encrypted Project snapshot inventory includes round records, prompts,
lifecycle state/timestamps and idea membership/late markers. Reconstitution
validates the graph before writing, remaps round IDs and preserves privacy.
Repeated restoration reuses identical generations. Old inventories without
rounds normalize to no rounds and unassigned contributions. Inventories before
version 8 carry no round privacy: normalization marks the active round of a
session that used the former session-wide private mode as private, with no
reveal-on-expiry and no reveal timestamp, and strips that session key. See
[recovery](brainstorming-recovery-contract.md) for archive and retention details.
