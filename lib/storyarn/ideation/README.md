# Ideation context

Ideation owns brainstorming sessions, responsibilities, configuration, ideas,
authored revisions and publication. External callers enter `Storyarn.Ideation`;
its root facade delegates through Sessions, Ideas and Recovery without importing private
roles. Capabilities collaborate through their own facades.

## Sessions capability

| Role         | Responsibility                                                         |
| ------------ | ---------------------------------------------------------------------- |
| `commands/`  | Session lifecycle, responsibilities and optional round lifecycle       |
| `queries/`   | Authorized, bounded reads of session data and revision history         |
| `entities/`  | Session, configuration, round and revision schemas; no persistence I/O |
| `execution/` | Locked, atomic session mutation and revision recording                 |
| `adapters/`  | Project authorization and candidate eligibility for mutations          |

The capability facade is the only implementation file at `sessions/` root.
Schema module identities are stable even though their files live in `entities/`.
Queries cannot enter command, execution or mutation-adapter roles. Entities and
adapters cannot become application orchestrators. The architecture ratchet and
`ideation_internal_structure_test.exs` enforce these directions and locations.

## Ideas capability

Ideas owns `ideation_ideas`, immutable `ideation_idea_revisions`, idempotent
`ideation_idea_edits` (including private conflicting input), frozen
`ideation_reveal_operations` and `ideation_idea_publications`. Its `commands/`
implement creation, save, delete, undo of a matching deletion, placement, connections and session-mode reveal; `execution/` retains
atomic transaction/revision/publication workflows. `queries/` selects authorized
revisions before decryption; `contracts/` builds safe views; `rules/` validates
content, policy and selection; `events/` sends content-free invalidations.

Content revisions and edit receipts are internal records for current heads,
pinned publications, concurrency, retries and compatible recovery capsules. They
are not a user-facing card history: historical-revision, conflict-list and receipt
queries have been removed. The immediate save-conflict response remains available.
There is no derivation command; older capsules retain their existing provenance.

`restore_idea/6` only reverses a particular deletion of the acting author's note,
guarded by its revision and deletion marker. It restores that identity with an
incremented revision, not arbitrary historical content. Browser undo/redo keeps
its own local, ephemeral operation stack and still enters authorized domain writes.

Sessions exposes a transaction-participating contribution port to Ideas. It locks
current Project access and the session lifecycle without granting managerial
draft access. Ideas owns the outer transaction and emits invalidations only after
commit. Other capabilities cannot import private implementation modules.

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

Recovery is the privileged reconstitution capability for the eight session/round/idea
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

The canvas uses facilitator-controlled session privacy and direct editing. See
[canvas behavior](../../../docs/features/brainstorming-board.md) for interaction,
delete/discard semantics and the compatibility boundary of publication ports.

Optional rounds are Session-owned children. Their start/close operations share
the session lock with contributions and record session revisions atomically.
Ideas asks the Sessions contribution port to bind its immutable round provenance;
closing a round never publishes or freezes content. See the
[round contract](../../../docs/reference/brainstorming-rounds-contract.md).
