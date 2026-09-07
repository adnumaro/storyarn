# Ideation context

Ideation owns brainstorming sessions, responsibilities, independent configuration
and their revision history. External callers enter `Storyarn.Ideation`; its root
facade delegates to `Storyarn.Ideation.Sessions` without importing private roles.

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
`ideation_sessions` and `ideation_session_revisions`. Creating a revision is part
of the session transaction, not a background side effect. Queries and entities
never write or acquire locks. Physical project deletion cascades its records;
archive only changes the session lifecycle and records a revision.

No Project snapshot/reconstitution writer for these tables is implemented or
authorized yet. This foundation has no user-facing entry point. Recovery and
private-content policy remain release gates before accepting real content through
the tool. See [the session contract](../../../docs/reference/brainstorming-contract.md).
