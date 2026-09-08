# Optional brainstorming rounds

> Owner: Engineering
> Last reviewed: 2026-09-08
> Scope: ENG-136

Sessions can receive ideas before, between and during rounds. Rounds are
optional iterations within the same session; timers, private mode, publication
and creative states remain independent controls.

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

Existing canvas links can connect readable notes across rounds without copying
their content. They are visual relationships, not a new derivation workflow or
a replacement for the retained source provenance in older notes. Link endpoints
remain subject to the reader's current privacy rules.

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
rounds normalize to no rounds and unassigned contributions. See
[recovery](brainstorming-recovery-contract.md) for archive and retention details.
