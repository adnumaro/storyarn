# Commercial bounded-context organization

`Storyarn.Commercial` is the public boundary for Storyarn's commercial model.
It owns the language and policy around plans, subscriptions, entitlements,
billable usage, limits, storage-capacity accounting and durable reservations.
It is an independent bounded context, not a capability of Platform.

Code outside this context calls `Storyarn.Commercial`. It must not call
`Storyarn.Commercial.Billing`, `Entitlements`,
`ProjectStorageReservations`, or a private role module directly. Those modules
are internal collaboration facets and implementation identities, not additional
bounded contexts or alternative public APIs.

## Ownership

| Commercial owns                                                                 | Consumers own                                                                                       |
| ------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| Shipped plan catalog and commercial limits                                      | The product operation being admitted and its domain invariants                                      |
| Workspace subscription state and plan resolution                                | Authorization to request the operation                                                              |
| Entitlement interpretation                                                      | How a quota answer is applied atomically to the consumer's write                                    |
| Consumer-local usage projections                                                | Source records and ordinary writes in Projects, Workspaces, Flows, Sheets and Scenes                |
| Billable storage usage and workspace-scoped capacity reservations               | Object keys, provider I/O, reachability, retention, cleanup execution and domain-specific lifecycle |
| Reservation fencing, leases, settlement and commercial accounting lock protocol | Provider-neutral byte operations, which remain in `Storyarn.Platform.ObjectStorage`                 |

A shared PostgreSQL table does not transfer ownership. Commercial can duplicate a
read mapping to measure usage without importing another context's Ecto schema and
without gaining write authority over that context's records.

## Responsibility folders

Commercial currently needs these roles:

| Folder            | Responsibility                                                                                                |
| ----------------- | ------------------------------------------------------------------------------------------------------------- |
| `commands/`       | Subscription writes and their transaction boundary.                                                           |
| `queries/`        | Subscription, entitlement and cleanup-handoff reads.                                                          |
| `entities/`       | Commercial-owned mutable subscription and storage-reservation state.                                          |
| `execution/`      | Limit evaluation and storage-accounting workflows whose locks, fencing and transaction order must stay whole. |
| `rules/`          | Deterministic storage protocol, cleanup-inventory and lease-policy interpretation.                            |
| `projections/`    | Read-only Commercial mappings over shared consumer tables used for usage and capacity decisions.              |
| `reference_data/` | Immutable shipped plan catalog.                                                                               |

These folders describe responsibility, not mandatory hexagonal layers. There is
no generic `persistence/` area. `Repo` is shared technical infrastructure;
persistence behavior stays named after the commercial operation performing it.

Commercial is a deliberate physical-layout exception to the usual
capability-first convention. ENG-112 promotes one cohesive commercial model out
of Platform without mechanically splitting its lock-sensitive storage workflow.
`Billing`, `Entitlements` and `ProjectStorageReservations` are collaboration
facets over that model; the top-level role folders do not turn them into three
independent capabilities. This exception is not precedent for organizing a new
context role-first. Revisit it only when the commercial model contains genuinely
independent capabilities with distinct language, invariants and workflows.

## Public and internal facades

`Storyarn.Commercial` is the only cross-context business facade. It exposes:

- entitlement and admission decisions;
- project/workspace usage summaries and plan lookup;
- subscription creation through a neutral receipt required by current product workflows;
- subscription to the Project-scoped snapshot export-lease invalidation;
- storage-accounting locks and published lease-policy values;
- transport-neutral reservation receipts and fenced reservation operations.

`Storyarn.Commercial.Billing` is an internal capability facet that composes the
current plan, subscription, limit and storage-accounting implementation.
`Storyarn.Commercial.Entitlements` resolves commercial limits without applying
them. `Storyarn.Commercial.ProjectStorageReservations` translates the internal
Ecto entity into the receipt contract returned across the context boundary.

External callers must not depend on a Commercial Ecto struct. The root facade's
subscription and reservation receipts are the current cross-context result
contracts.

Commercial publishes the best-effort invalidation
`{:commercial_snapshot_export_lease_state_invalidated, snapshot_id}` only after
the enclosing Commercial-owned workspace transaction has committed.
Consumers must refetch authoritative state. Delivery is non-durable and an
idempotent replay may repeat the invalidation without implying that another
database write occurred.
Presentation may subscribe through
`Storyarn.Commercial.subscribe_project_snapshot_export_leases/1` and compose the
result with Projects data. Commercial never publishes on a Projects-owned topic
or impersonates a Projects event.

## Projections and write authority

Files in `projections/` are deliberately duplicated, read-oriented mappings of
foreign tables. They contain only the fields Commercial needs to count usage,
resolve a plan or account for retained storage. Changes to a Project, Sheet,
Flow, Scene or Workspace schema therefore do not automatically change
Commercial's model.

The established module names for these mappings currently contain
`Storyarn.Commercial.Billing.Persistence.*`. That internal namespace does not
create a physical `persistence/` layer and does not authorize writes. Their
physical role and documented ownership are authoritative; renaming those
identities requires an explicit compatibility review.

Commercial's ordinary writes are limited to its subscription and storage
reservation/accounting state. A projection over a consumer-owned table never
authorizes `Repo.insert`, `Repo.update`, `Repo.delete`, bulk mutation or an
ordinary changeset for that foreign record.

## Storage accounting contract

Commercial accounts logical, billable ownership from database facts. It does
not inventory provider bytes and does not own object I/O. Temporary, duplicated,
orphaned and cleanup-pending provider bytes are operational concerns rather
than quota input unless the commercial policy is changed deliberately.

The storage workflow has correctness-sensitive behavior that must remain
together:

- synchronous writers hold the workspace accounting lock for their complete
  transaction;
- multi-step work reserves capacity, performs external work without holding a
  database row lock, then commits durable ownership with a lease token and
  generation fence;
- settlement and release preserve cleanup ownership evidence so freeing quota
  cannot silently orphan provider objects;
- snapshot lease TTLs, heartbeat windows and retention form one policy contract
  consumed through the root facade;
- Project snapshot protocol values are duplicated locally and verified rather
  than importing Projects internals.

Do not split this execution path merely to satisfy a layer diagram. Changes to
lock acquisition order, callback placement, fencing, transaction boundaries,
lease semantics or idempotency are behavior changes and require dedicated
concurrency and integration tests.

## Boundary rules

- Other contexts and `StoryarnWeb` call `Storyarn.Commercial` only.
- Commercial does not call another bounded context's private modules.
- Consumers retain their own writes, authorization and invariants after asking
  Commercial for an admission or entitlement decision.
- Commercial owns billable storage capacity; `Storyarn.Platform.ObjectStorage`
  owns provider-neutral byte operations; consumer contexts own object lifecycle.
- Shared SQL and atomic callbacks are current modular-monolith contracts, not
  permission to share Ecto schemas or business rules.
- This extraction changes code ownership and namespaces only. It does not
  require a PostgreSQL schema split or alter existing commercial behavior.
