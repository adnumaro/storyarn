# Ideation context

Ideation owns brainstorming sessions, responsibilities, configuration, ideas,
authored revisions, publication and explicit decisions. External callers enter `Storyarn.Ideation`;
its root facade delegates through Sessions, Ideas, Groups, Decisions, References and Recovery without importing private
roles. Capabilities collaborate through their own facades.

## Sessions capability

| Role         | Responsibility                                                                |
| ------------ | ----------------------------------------------------------------------------- |
| `commands/`  | Session lifecycle, responsibilities, round and timer lifecycle                |
| `queries/`   | Authorized, bounded reads of session data and revision history                |
| `entities/`  | Session, configuration, round, timer and revision schemas; no persistence I/O |
| `execution/` | Locked, atomic session mutation and revision recording                        |
| `adapters/`  | Project authorization and candidate eligibility for mutations                 |

The capability facade is the only implementation file at `sessions/` root.
Schema module identities are stable even though their files live in `entities/`.
Queries cannot enter command, execution or mutation-adapter roles. Entities and
adapters cannot become application orchestrators. The architecture ratchet and
`ideation_internal_structure_test.exs` enforce these directions and locations.

## Ideas capability

Ideas owns `ideation_ideas`, immutable `ideation_idea_revisions`, idempotent
`ideation_idea_edits` (including private conflicting input), frozen
`ideation_reveal_operations` and `ideation_idea_publications`. Its `commands/`
implement creation, save, delete, undo of a matching deletion, placement, connections and round reveal; `execution/` retains
atomic transaction/revision/publication workflows. `queries/` selects authorized
revisions before decryption; `contracts/` builds safe views; `rules/` validates
content, policy and selection; `events/` sends content-free invalidations.

Connection batches use independent per-source link versions and one bounded last
acknowledgement per source. Creating connected notes adds all selected incoming
links in the same creation transaction; a bounded creation acknowledgement lets
the browser reconcile its own undo versions. Neither acknowledgement is exposed
as note history or copied into snapshots. Connection state and its versions are
included in recovery, with endpoints remapped alongside the notes.

Content revisions and edit receipts are internal records for current heads,
pinned publications, concurrency, retries and compatible recovery capsules. They
are not a user-facing card history: historical-revision, conflict-list and receipt
queries have been removed. The immediate save-conflict response remains available.
`bring_idea_forward/5` is the one derivation command: it copies the revision of a
readable note into the round in progress as the actor's own note, linked through
`source_idea_id`/`source_revision`; older capsules retain their existing provenance.

`restore_idea/6` only reverses a particular deletion of the acting author's note,
guarded by its revision and deletion marker. It restores that identity with an
incremented revision, not arbitrary historical content. Browser undo/redo keeps
its own local, ephemeral operation stack and still enters authorized domain writes.

Sessions exposes a transaction-participating contribution port to Ideas. It locks
current Project access and the session lifecycle without granting managerial
draft access. Ideas owns the outer transaction and emits invalidations only after
commit. Other capabilities cannot import private implementation modules.

## Groups capability

Groups owns shared canvas containers, optional plain-text synthesis, retained source
memberships and immutable actor revisions that also serve as durable write receipts.
Each note belongs to at most one active group. Membership pins the published source
revision at joining; removing or deleting a group never deletes its source notes.
Empty membership may retain synthesis as an independent canvas container. Detaching
and reattaching may restore its anchor without moving sources; populated group moves
remain atomic. Reattachment preserves the most recent retained source pin for the
same group and note, including undo after the note receives a newer revision.
Changing visible members keeps the membership of a deleted note; separating removes all.

Every write uses current project editor access, the open session contribution lock,
an optimistic group version and a UUID request identity. A group records its round;
a private round hides its groups before decryption and rejects their writes with
`private_round`. Group movement delegates geometry
writes through Ideas' closed transaction port and checks every live member version.
Revisions support provenance and exact browser undo only, with no history endpoint.
Deleting a group permits only its deleting actor to restore that exact deletion.
Queries and entities stay passive; events emit content-free invalidations after commit.
Recovery includes groups, memberships and revisions in its sealed inventory.

## Decisions capability

Decisions owns what a team agreed to do and how far it has been applied, in
`ideation_decisions`, `ideation_decision_revisions` and
`ideation_decision_applications`. A decision is an object: one verb (create,
change, test, keep or discard), up to five affected Sheets, Flows or Scenes or
free labels for something not yet created, a conclusion, an optional reason and
an optional next action with its owner. Sources pin shared idea or group
revisions and their recovery identities; affected content is pinned by type, ID
and creation identity, with its name frozen in encrypted context so a replaced
target reads as unavailable instead of silently pointing at a newcomer. The
round of a decision is the newest round among its sources.

Propose, revise, accept, withdraw and declare are distinct atomic commands with
current Project and session authorization, optimistic versions and durable
request receipts. Registering is proposing and accepting in one command when the
proposer is the responsible person; it writes two consecutive records. Accepting a
proposal that names a decision it replaces supersedes that decision with a
closing record on its own history. Withdrawing a revision keeps the earlier
agreement in force; withdrawing a proposal without one retires it. Nothing is
deleted and nothing is rejected.

Application is declared per target of the agreement in force, by any editor, as a
statement rather than a verification. Declarations are append-only and belong to
one agreement: accepting a revision starts over with every target not applied,
while earlier declarations stay in the history. Decisions never read or write the
affected content.

Decisions expose a `comment_source` port for their discussion, like sessions,
ideas and groups. A decision's discussion is readable by every project reader and
never has a canvas position.

Recovery retains every revision, declaration, supersession link and receipt, and
never executes acceptance. Receipts in replaced generations of the same logical
session prevent reexecuting commands after rollback. See the
[decision contract](../../../docs/reference/brainstorming-decisions-contract.md).

## References capability

References owns explicit, many-to-many links from sessions and shared ideas to
existing Sheets, Flows, Scenes, Assets and active localization text rows. A link
never duplicates or edits the destination. Private ideas do not yet admit shared
references, even for their author; publication is a separate operation. Current
audience is checked again on reads, inverse links, history and mutation retries.

The saved `overview_v1` is a bounded, explicitly selected overview of the target,
not an editable copy or a universal content version. Name, description and typed
metadata are compared; Sheet blocks, Flow nodes and Scene layers are outside this
comparison. Refreshing is explicit and preserves prior consulted contexts. Missing
or inaccessible destinations return no title, saved context, locator or preview.
Destination generations are fenced by their recorded creation identity, never name.

Each source permits up to 100 active references; pages contain at most 50 entries.
A reference retains up to 49 consulted contexts and a final unlink receipt (50
revisions maximum), without silently pruning provenance. Reaching the context
limit does not prevent unlinking. Create/refresh/remove use session-scoped actor
request identities, optimistic revisions and after-commit content-free events.
Reference changes do not refresh notification inboxes. Snapshots include references
and retained context, independently of conversations, which are never rewound.

Editors can open a bounded context picker, create an exploration with an origin,
link an open session, or resume an existing whole-session link. Creation records
the session and its origin in one transaction; the origin revision carries the
durable creation receipt and is included in recovery. An exclusive Project lock
serializes creation retries before a session exists. Receipts in replaced sessions
fence retries after restoring an earlier snapshot. Existing session links are
reused without duplicating or changing their relation; an audited `context_linked`
session revision preserves the reuse receipt and stable reference identity so a
retry cannot undo a later unlink. New writes compare the
consulted target identity and overview fingerprint; retries preserve the original
context and never silently refresh it. Archived linked sessions remain readable.
Drafts and automatic application remain separate features.

## Project authority

Projects owns identity and effective membership, including inherited access and
direct-role precedence. The read query uses its ordinary authorization port.
Mutation authorization uses shared locks in the caller's transaction before the
session row lock. A candidate is checked by ID through an actor-scoped Projects
port; the candidate is not impersonated and receives no membership or assignment
from that check. Ideation separately owns authority to manage each session.

The facilitator and decision owner are independent responsibilities. Replacing a
facilitator removes their management role. If account deletion clears either
assignment, the other can still be repaired independently. Explicitly assigning
a blank or ineligible candidate is rejected; an omitted assignment is preserved.

## Write ownership and recovery

Only session commands and their atomic mutation workflow ordinarily write
`ideation_sessions` and `ideation_session_revisions`. Only Ideas commands and their
execution workflows write the idea, edit, reveal and publication tables. Creating a revision is part
of the session transaction, not a background side effect. Queries and entities
never write or acquire locks. Physical project deletion cascades its records;
archive only changes the session lifecycle and records a revision.

Recovery is the privileged reconstitution capability for the seventeen session/round/timer/idea/group/reference/decision
tables. Its closed inventory uses raw encrypted fields and owns the derived
`ideation_recovery_captures` cache. `execution/` coordinates capture/reconstitution;
`adapters/` handles bounded persistence and encryption; `contracts/` owns the
versioned record inventory. Ordinary commands cannot enter recovery internals.
Project capture/materialization/verification call only the sealed root ports,
inside the existing authorized Project transaction and exclusive lock.

Restoration retains distinct replaced generations and reuses identical ones via
stable record identities. Actors resolve through sealed Accounts ports; missing
authors' drafts stay closed. Session recovery is an ordinary authorized command
that restores an archived session without granting draft access. Only the owner
may explicitly purge a replaced session; live/archived sessions are protected.
Capture limits are typed failures, and restore checks the full retained inventory
before commit so it cannot strand future backups above those bounds. See [privacy and recovery](../../../docs/reference/brainstorming-recovery-contract.md),
[session behavior](../../../docs/reference/brainstorming-contract.md) and
[idea publication](../../../docs/reference/brainstorming-ideas-contract.md).

The canvas uses facilitator-controlled round privacy and direct editing. See
[canvas behavior](../../../docs/features/brainstorming-board.md) for interaction,
delete/discard semantics and the compatibility boundary of publication ports.

Optional rounds are Session-owned children. Their start/close operations share
the session lock with contributions and record session revisions atomically.
Ideas asks the Sessions contribution port to bind its immutable round provenance;
closing a round never publishes or freezes content. The round in progress can be
private: Sessions flips the flag under the contribution lock, and Ideas publishes
the round's consenting contributions when that mask ends, manually or at timer
expiry when the round asked for it. See the
[round contract](../../../docs/reference/brainstorming-rounds-contract.md).

Independent countdowns belong to Sessions. Its execution runtime wakes persisted
deadlines without idle polling; the owner-scoped worker provides durable delivery.
Expiry revalidates the original actor and policy before revealing the round in
progress, when it asked for that, and closing contributions when the timer asked,
in one transaction. Recovery pauses running timers and
fences their old deliveries. See the
[timer contract](../../../docs/reference/brainstorming-timer-contract.md).
