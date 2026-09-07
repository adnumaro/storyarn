# Ideation context

Ideation owns brainstorming sessions, responsibilities, configuration, ideas,
authored revisions and publication. External callers enter `Storyarn.Ideation`;
its root facade delegates through Sessions and Ideas without importing private
roles. Capabilities collaborate through their own facades.

## Sessions capability

| Role         | Responsibility                                                  |
| ------------ | --------------------------------------------------------------- |
| `commands/`  | Create, update, assign responsibilities, archive and reopen     |
| `queries/`   | Authorized, bounded reads of session data and revision history  |
| `entities/`  | Session, configuration and revision schemas; no persistence I/O |
| `execution/` | Locked, atomic session mutation and revision recording          |
| `adapters/`  | Project authorization and candidate eligibility for mutations   |

The capability facade is the only implementation file at `sessions/` root.
Schema module identities are stable even though their files live in `entities/`.
Queries cannot enter command, execution or mutation-adapter roles. Entities and
adapters cannot become application orchestrators. The architecture ratchet and
`ideation_internal_structure_test.exs` enforce these directions and locations.

## Ideas capability

Ideas owns `ideation_ideas`, immutable `ideation_idea_revisions`, idempotent
`ideation_idea_edits` (including private conflicting input), frozen
`ideation_reveal_operations` and `ideation_idea_publications`. Its `commands/`
implement creation/derivation, save, prepare and reveal; `execution/` retains
atomic transaction/revision/publication workflows. `queries/` selects authorized
revisions before decryption; `contracts/` builds safe views; `rules/` validates
content, policy and selection; `events/` sends content-free invalidations.

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

No Project snapshot/reconstitution writer for these tables is implemented or
authorized yet. This foundation has no user-facing entry point. Recovery and
private-content policy remain release gates before accepting real content through
the tool. See [the session contract](../../../docs/reference/brainstorming-contract.md).
Private draft and conflict handling is specified in
[the idea contract](../../../docs/reference/brainstorming-ideas-contract.md).
