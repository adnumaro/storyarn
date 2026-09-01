# AI internal architecture

`Storyarn.AI` is one bounded context. The folders below are six cohesive
business capabilities inside that context, not six additional bounded contexts.
`Storyarn.AI` remains the public boundary used by `StoryarnWeb` and by other
Storyarn bounded contexts.

Each capability also has a smaller facade for collaboration inside AI:

| Capability       | Facade                     | Responsibility                                                                                                                                                   |
| ---------------- | -------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Context Building | `Storyarn.AI.Context`      | Deterministic, bounded context-package construction and freshness checks. The folder is `context_building/` so it cannot be confused with a DDD bounded context. |
| Governance       | `Storyarn.AI.Governance`   | Workspace and project access, egress policy, permitted lanes and execution/apply authorization.                                                                  |
| Integrations     | `Storyarn.AI.Integrations` | Personal provider connections, workspace assignments, consent, model preferences, key validation and the integration audit trail.                                |
| Routing          | `Storyarn.AI.Routing`      | Task contracts, model catalog, intents, opaque route options, preflight and provider-neutral route selection.                                                    |
| Operations       | `Storyarn.AI.Operations`   | Durable operations and results, provider-attempt lifecycle, inference execution, alerts, recovery and reconciliation.                                            |
| Managed Spend    | `Storyarn.AI.ManagedSpend` | Promotional allowance, grants, reservations, provider budgets, content-free usage accounting and exactly-once settlement.                                        |

Capabilities are implementation slices of AI. They can be reorganized without
changing the business boundary or requiring separate OTP applications.

## Responsibility folders

A capability uses only the folders that describe responsibilities it actually
has. Empty architectural layers are not required.

| Folder            | Responsibility                                                                                                          |
| ----------------- | ----------------------------------------------------------------------------------------------------------------------- |
| `commands/`       | State-changing use cases, transactions, locks and effect coordination.                                                  |
| `queries/`        | Read-only persistence operations and bounded projections.                                                               |
| `entities/`       | AI-owned mutable state, Ecto schemas and their changesets.                                                              |
| `contracts/`      | Stable value contracts and configurable SPIs consumed across a capability boundary.                                     |
| `rules/`          | Deterministic validation, normalization, hashing and policy decisions.                                                  |
| `execution/`      | Stateful or multi-step workflows whose security, transaction or exactly-once boundary must remain whole.                |
| `events/`         | Business facts and append-only audit records owned by the producing capability.                                         |
| `adapters/`       | Translation to providers, credentials, jobs, telemetry, feature flags, PostgreSQL locks or another technical mechanism. |
| `projections/`    | Passive, consumer-owned, read-only SQL mappings over shared tables.                                                     |
| `reference_data/` | Immutable shipped catalogs without database identity, lifecycle, or I/O.                                                |
| `tasks/`          | Registered AI task definitions; executable product contracts rather than passive data.                                  |
| `compatibility/`  | Temporary public compatibility facades; never provider adapters or new entry points.                                    |

The capability facade sits directly inside its capability folder. Private
commands, queries, rules, execution modules, events, adapters and projections
remain behind it.

## Projections and reference data

The two passive data roles remain explicit and separate from adapters.

### Consumer-local SQL projections

These are deliberately duplicated Ecto schemas over tables owned elsewhere.
They contain only the foreign facts one AI capability needs for its own
workflow. Examples include Governance's project and membership records,
Integrations' workspace assignment records, Routing's project identity,
Operations' workspace identity and Managed Spend's workspace and actor
identities.

Two capabilities may map the same SQL table with different fields and
associations. That duplication is intentional: changing a Governance access
projection must not silently alter Routing, Operations or Managed Spend.
Sharing PostgreSQL in this phase does not imply sharing schema modules.

A projection declares fields, associations and types. It does not call
`Repo`, coordinate a transaction or lock, emit an event, contact a provider or
decide business policy. Reads belong in `queries/`; writes and invariants belong
to the owning `commands/` or to an indivisible `execution/` workflow.

### Reference data

Reference data is immutable application data with no database lifecycle or
external I/O. Routing's shipped model defaults are the current example. The
managed diagnostic is a registered task definition and therefore lives in
`routing/tasks/`, not in reference data.

## Write ownership

AI owns ordinary writes to its policies, provider integrations and workspace
assignments, personal model preferences, routing options, operations, audit and
managed-spend records. The model catalog is shipped AI reference data and has
no database writer. Projects and Workspaces continue to own project/workspace
identity, membership and authorization records; AI maps the foreign fields it
needs with consumer-local projections and never gains write authority over
those tables.

There is intentionally no generic `persistence/` folder. `Repo` is technical
infrastructure shared by the application, while persistence behavior remains
named after the business operation performing it.

## Stable module identities

Several established modules keep their existing names even though their files
now live inside one capability. Migrations, Ecto associations, persisted Oban
arguments, runtime configuration, consumers or tests may depend on those names.

- Context contracts: `Storyarn.AI.Context.Contract`, `Context.Entity`,
  `Context.Package`, `Context.Policy`, `Context.SubjectRef` and
  `Context.PersistenceContract`.
- Governance state and decisions: `Storyarn.AI.WorkspacePolicy`,
  `WorkspacePolicyAudit` and `PolicyDecision`.
- Integration state and SPI: `Storyarn.AI.Integration`,
  `IntegrationWorkspaceAssignment`, `PersonalConsent`, `PersonalPreference`,
  `AuditEntry` and `Provider`.
- Routing contracts and state: `Storyarn.AI.CredentialRef`, `ExecutionIntent`,
  `ExecutionRoute`, `ModelCatalog.Entry`, `Task`, `TaskDefinition` and
  `RouteOption`.
- Operation state and SPI: `Storyarn.AI.Operation`, `Result`, `OperatorAlert`,
  `ResolvedCredential`, `CredentialResolver` and `InferenceProvider`.
- Managed-spend state and SPI: `Storyarn.AI.AllowanceAccount`,
  `AllowanceGrant`, `AllowanceReservation`, `AllowanceAllocation`,
  `AllowanceLedgerEntry`, `ProviderBudgetReservation`, `UsageEvent`,
  `SettlementAdapter`, `Settlement`, `Settlement.Managed` and
  `Settlement.Unavailable`.

Stable identity is a compatibility contract, not permission to call a
capability's private implementation. Compatibility modules such as
`Storyarn.AI.Execution`, `Allowance`, `ProviderBudget`, `Results`,
`RouteOptions` or `InferenceProviders` support incremental migration and
rolling deployments; new cross-capability code must use the owning facade.

## Cross-capability collaboration

- Code outside AI calls `Storyarn.AI`, never a private AI capability module.
- One AI capability calls another through its capability facade.
- Stable structs and value contracts may cross a seam when they are the
  explicit input or output of that facade.
- A capability never imports another capability's `commands/`, `queries/`,
  `rules/`, `execution/`, `events/`, `adapters/` or `projections/` modules.
- An orchestration may remain inside one database transaction when splitting it
  would weaken authorization, idempotency, no-overspend or exactly-once
  guarantees. The call still enters the other capability through its facade.

For example, Routing asks Governance for authorization; Operations consumes
Routing contracts and reauthorizes through Governance; Managed Spend records
operator alerts through Operations. Physical proximity inside `Storyarn.AI`
does not make those private modules shared utilities.

## Workers

AI background jobs live under `lib/storyarn/workers/ai/` and keep their stable
`Storyarn.Workers.*` module identities because Oban persists the worker name.
They are technical adapters and orchestrators, not a seventh AI capability or
a bounded context.

A worker may deserialize a job, choose a continuation and call `Storyarn.AI`.
It must not call a capability facade directly, own domain policy, duplicate a
transaction boundary, write through a private schema or call capability
internals. Provider queueing belongs behind an Operations job adapter; business
decisions remain in the owning capability. Worker tests stay under
`test/storyarn/ai/workers/` for the same reason.
