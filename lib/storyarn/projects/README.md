# Projects internal organization

`Storyarn.Projects` is the bounded-context facade. Its first level is organized
by Project-owned business capabilities plus the closed `content/` model and the
closed `reconstitution/` entry boundary. The capability folders are
implementation slices inside one bounded context; none is an independently
named bounded context.

| Capability     | Responsibility                                                                                                                              |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `lifecycle/`   | Project identity, creation, Project-owned configuration, update, soft deletion and Workspace-owned hard-delete coordination.                |
| `access/`      | Project memberships, roles, authorization and invitations, including Project-owned invitation intent and copy.                              |
| `assets/`      | Project assets, upload and trash lifecycle, blob identity, storage compensation, image processing and Project-owned storage policy.         |
| `overview/`    | Project-wide dashboards, activity, statistics, health findings and structural analysis. It does not own the shared Project content records. |
| `trash/`       | Cross-tool Project trash, restore, hard deletion and retention workflows.                                                                   |
| `references/`  | Project-wide entity and variable reference indexes, integrity, repair and usage queries.                                                    |
| `interchange/` | Project import and export workflows, formats, parsers, serializers, validation and exact reconstitution writers.                            |
| `templates/`   | Project template publication, portable bundles, installation, audit and lifecycle.                                                          |
| `versioning/`  | Full-project snapshot capture, storage, restore, recovery, reconstitution, reconciliation and accounting.                                   |

Imports and exports are two directions of the same Project interchange
capability. Snapshot restore and project import remain separate workflows:
interchange imports authored external content, while versioning reconstitutes a
canonical Project snapshot with its durability and fencing guarantees.

## Closed Project content model

`content/` is not a tenth capability, a shared layer or another bounded
context. It is the closed Project-owned interpretation of Flow, Sheet, Scene
and Localization content needed by several Project capabilities.

Projects deliberately duplicates these contracts, records and rules. It
does not import the editor or runtime model from `Storyarn.Flows`,
`Storyarn.Sheets`, `Storyarn.Scenes` or `Storyarn.Localization`. This lets
Projects optimize whole-project capture, interchange, health, references and
trash independently while every context still reads the shared PostgreSQL
tables during this migration phase.

Admission to `content/` is narrow:

1. The concept is expressed in Project language and is needed by at least two
   Project capabilities.
2. It describes or interprets Project content; it does not own a user-facing
   workflow, external provider or generic utility.
3. It is not callable from `StoryarnWeb`, workers or another bounded context.
4. It has no facade. Project capabilities consume its stable contracts, rules
   and records directly until capability-local duplication becomes useful.

The Flow and Scene conditions, instructions and variable rules remain separate
even where they look similar. Their duplication is intentional and they must
not be merged merely to reduce line count.

## Closed Project reconstitution boundary

`reconstitution/` is not a tenth capability or another bounded context. It is a
closed routing boundary that makes every privileged whole-Project import,
template and snapshot materialization enter through one reviewed module. It is
deliberately absent from the public `Storyarn.Projects` facade.

The boundary owns no authorization, transaction, lock, compensation, delivery
or error policy. Those remain in the initiating Interchange, Templates or
Versioning lifecycle; the boundary forwards the exact arguments, callbacks,
options and return values to their existing engines. Its caller set and each
callable function are sealed by the privileged-entrypoint architecture guard.

The SQL models shared by several Project capabilities live under
`content/{flows,sheets,scenes,localization}/records/`. They are records rather
than projections because import, snapshot restore, trash and repair workflows
also use them for controlled writes. Their historical
`Storyarn.Projects.Persistence.*Record` identities remain stable because Ecto
associations and test/support contracts depend on them; physical ownership is
defined by this folder, not by that compatibility namespace.

## Responsibility folders

Each capability uses only the roles it needs:

| Folder            | Responsibility                                                                                                                                              |
| ----------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `commands/`       | State-changing use cases, transactions, locks and effect coordination.                                                                                      |
| `queries/`        | Read-only persistence operations and purpose-built projections.                                                                                             |
| `entities/`       | Mutable Project-owned business state, including Ecto schemas and changesets.                                                                                |
| `contracts/`      | Stable values and error/receipt contracts owned by the capability.                                                                                          |
| `rules/`          | Pure validation, normalization, policy and content interpretation. Persistence reads belong in `queries/`; randomness and allocation belong in `commands/`. |
| `projections/`    | Passive consumer-local SQL read models; never persistence I/O.                                                                                              |
| `reference_data/` | Immutable application catalogs with no database identity or lifecycle.                                                                                      |
| `records/`        | SQL records intentionally used by an owner for controlled writes or exact reconstitution as well as reads.                                                  |
| `execution/`      | Stateful or multi-step workflows whose transaction, lock or recovery order must remain intact.                                                              |
| `events/`         | Product facts owned by Projects.                                                                                                                            |
| `delivery/`       | Project-owned delivery decisions and content, before technical handoff.                                                                                     |
| `adapters/`       | Translation to Platform object storage, archives, images, PostgreSQL locks, Oban, email or another provider.                                                |

This is a pragmatic functional architecture. A transaction is not split merely
to make a file fit a diagram, and a pure function does not need a behaviour or
port unless there is a real replaceable seam.

## Effective project authorization

Project authorization has one effective-membership policy across reads and
writes. A direct Project membership always takes precedence. When no direct
membership exists, access is inherited from the containing Workspace:

| Workspace role | Effective Project role |
| -------------- | ---------------------- |
| `owner`        | `editor`               |
| `admin`        | `editor`               |
| `member`       | `editor`               |
| `viewer`       | `viewer`               |

Inherited access is intentionally synthetic: it has no Project membership row
and never grants Project ownership. Consequently, inherited editors may view,
edit content and use single-item AI actions, but cannot manage the Project,
manage its members or run owner-only bulk AI. An explicit Project membership can
upgrade or reduce this inherited access; for example, a direct `viewer` remains
a viewer even when the user is a Workspace admin. Soft-deleted Projects are
never authorizable.

This is the established product policy used by Project loading and the editor,
not a convenience fallback for individual callers. Changing to per-Project
opt-in access is a separate authorization redesign and must not be achieved by
bypassing effective membership in one code path.

## Ownership invariant and transfer

A Project has one canonical owner represented by `projects.owner_id` and
exactly one direct `project_memberships` row with `role = "owner"`. Inherited
Workspace access is never eligible for ownership transfer. Ordinary membership
creation and role changes cannot assign the owner role;
`Storyarn.Projects.transfer_owner/3` is the only ordinary public transition
that updates both owner facts.

The command locks the active Project, validates and locks its full direct
membership set, requires the receiver to be an existing direct member, and
commits both role changes plus `owner_id` atomically. The former owner becomes
an `editor`. The containing Workspace, its owner, subscriptions, assets and
Project content are unchanged.

Ownership transfer owns its transaction boundary. Calling the public command
from an already-open database transaction is rejected before any write; this
prevents a successful outer commit from bypassing the post-commit ownership
signal used to reauthorize connected settings surfaces.

Every owner-only writer reauthorizes the canonical owner after acquiring the
Project lock. This includes Project update/delete, membership and invitation
mutations, and snapshot request/cancel/delete paths. Consequently an operation
that authorized before a concurrent transfer cannot continue with stale owner
authority after that transfer commits. Missing or ambiguous owner facts fail
closed with `:ownership_invariant_violation`.

This fail-closed boundary is intentionally visible to active workflows: an
owner-only operation already in progress may stop or fail when ownership
changes. The former and new owner must review that operation and restart it
under the new authority when necessary; it never resumes with the former
owner's stale authorization.

The application transaction is the current enforcement boundary. A persistent
constraint tying `owner_id` to the unique owner membership requires its own
reviewed database decision and is deliberately outside ENG-108.

## Persistence-shaped folders

### Consumer-local SQL projections

These are Ecto schemas over the shared database, shaped for one Project
capability. They may map tables written by another capability or bounded
context, and two capabilities may deliberately map the same table differently.

A projection declares only the fields, associations and types needed by its
consumer. It does not expose write changesets, call `Repo`, open a transaction,
acquire a lock, emit an event, enqueue work or contact a provider. Reads belong
in `queries/`; writes and invariants belong in `commands/`, `records/` or an
indivisible `execution/` workflow.

Some projections and records retain historical module identities containing
`.Persistence.`. That namespace is a compatibility contract for associations
and existing callers; there is no physical `persistence/` layer.

### Reference data

Reference data is immutable application data with no database identity,
lifecycle, external I/O or transaction semantics. The Project-classification
catalog is the current Lifecycle example; the language catalog belongs to
Localization.

### Writable records

`records/` is reserved for models that participate in controlled Project-owned
writes. The closed content records are used by exact import/snapshot
reconstitution, trash, repair and Project-wide integrity workflows. They are not
presented as ordinary read projections.

References keeps its `FlowNodeRecord` as a read model for Project-wide
coordination and its writable `TableRowRecord` for the remaining Project-owned
repair workflow. Their historical
`Storyarn.Projects.References.Persistence.*` module identities remain stable;
`FlowNodeRecord` lives physically in `projections/`, while `TableRowRecord`
remains in `records/` because it participates in that controlled write path.

Localization records are the most sensitive case. Localization is the only
ordinary writer of `project_languages`. Projects may write its duplicated
`ProjectLanguageRecord` only during template materialization, exact Project
import/reconstitution (including replacement import), or full-project snapshot
restore/recovery. The exact writers are allowlisted in
`config/architecture_boundaries.exs`; no current Project repair writes that
table. Localization is also the sole ordinary writer of `localized_texts`;
Projects retains only the four classified closed-graph exceptions for import,
replacement, recovery and exact snapshot restore. Ordinary language,
extraction, translation, review, and provider workflows remain owned by
Localization.

There is intentionally no generic `data/`, `persistence/` or `shared/` folder.

## Stable facades over use cases

The large historical entry modules remain stable but are now routing surfaces:

- `ProjectCrud` delegates reads to `Lifecycle.Queries.ProjectQueries` and
  state-changing transactions to `Lifecycle.Commands.ProjectCommands`.
- `Assets` routes queries, ordinary commands, trash, uploads, blob verification
  and exact reconstitution through explicit use-case modules.
  `Storyarn.Projects.Assets.Queries.AssetUsageQueries` is the sole owner of the
  asset-usage read model; it and trash share the pure
  `Storyarn.Projects.Assets.AssetFamily` graph under `rules/` without coupling
  reads to execution. The shared lock, compensation and upload protocol remains
  an indivisible execution kernel so its order cannot drift between wrappers.
- `Imports` routes preparation, review, queue/cancellation and attempt lookup
  through role-specific modules. Its plan reservation and cleanup workflow stays
  together under `execution/` for the same transactional reason. The closed
  `FormatRegistry` is the composition root for parser selection, durable format
  identities and post-parse adapters. Generic input, telemetry, commands, rules
  and execution consume that contract; upload profiles, review semantics,
  parser errors, materialization rewrites and replacement copy remain owned by
  the registered source-format adapter. Persistence stores a bounded opaque
  identifier rather than duplicating the registry's allowlist. Unknown formats
  and parser/registration mismatches fail closed. Extensions are exclusive by
  design; a future pair of formats sharing one container extension requires an
  explicit product discriminator rather than content guessing.
- `References.EntityReferenceExtraction` owns the pure, strict decoding of
  embedded Sheet/Flow references used by Project writers and portable snapshot
  validation. Persistence-backed reference tracking remains under `commands/`;
  pure consumers never depend on that writer.
- `References.VariableReferenceExtraction` owns the pure Flow/Scene variable
  scanners. `VariableReferenceValidation` combines those specs with
  `VariableReferenceResolutionQueries`, while `VariableReferenceTracker`
  contains only projection writes and additive rebuilds. Usage and staleness
  stay on the independent read side.
- `References.PortableVariableSnapshot` owns pure planning and in-memory
  rewriting for snapshot portability. The lock-sensitive update of already
  materialized formula rows remains an explicit command in
  `MaterializedFormulaBindingRewriter`.
- `Versioning.SnapshotReferences` owns portable whole-Project reference
  validation and its consumer-local Sheet, Flow and Scene scanners. The large
  builders retain capture and materialization, but no longer mix this pure
  preflight rule into their stateful execution code.
- `ProjectReconstitution` is the single internal entry boundary for privileged
  whole-Project materialization. It forwards inputs, options and results
  unchanged; the initiating lifecycle keeps authorization, transactions, lock
  order, compensation and delivery ownership.

## Public and worker boundaries

- `StoryarnWeb`, application coordinators and other bounded contexts enter
  Project-owned behavior through `Storyarn.Projects`. The general Project
  settings surface deliberately composes `Storyarn.Localization` for
  source-language behavior through a reviewed root-facade contract.
- The root facade composes the nine capability facades. Stable entity and type
  aliases remain there only as compatibility contracts.
- Background jobs remain physically grouped under `workers/projects/`, retain
  their persisted `Storyarn.Workers.*` module identity and call only
  `Storyarn.Projects`. Their root-facade entry points are
  hidden from generated documentation but contract-tested.
- Project invitations use `Access.Adapters.Jobs.InvitationQueue` to encrypt and
  persist `DeliverProjectInvitationWorker` inside the invitation transaction.
  After commit, the same adapter wakes the owner queue best-effort so the
  non-transactional Oban notifier cannot add Stager latency. The worker
  re-enters only through `Storyarn.Projects`; Platform owns neither this job nor
  any Project invitation rule or retry effect.
- `content/`, capability role folders and technical adapters are private to
  Projects.
- Storage paths, archive formats, queues, worker arguments and Ecto module
  identities do not change because a file moved.

## Object storage ownership

Projects owns Project asset keys, blob identity, recoverable-blob retention,
multipart cleanup eligibility, compensation, snapshots, imports and exact
reconstitution. Provider selection, Local/R2 I/O, incremental hashing and the
generic key-lock engine live behind `Storyarn.Platform.ObjectStorage`.

Projects also owns the shared asset rows. Flow versioning and Sheet/Scene upload
or version workflows keep their storage transfer, quota and compensation logic,
but register the row or link a variant through sealed local adapters to the
public Projects facade.

Only the Project-owned adapters call that technical facade. Projects execution
code never receives a provider module, and other contexts cannot import the
Project storage policy merely because their objects currently share a bucket.

## Stable cross-context ownership decisions

AI owns its policies, provider integrations and assignments, personal model
preferences, routing state, operations, audit and managed-spend records.
Projects owns project identity, access and the `:use_ai` / `:run_bulk_ai`
permissions that AI consumes through its own projections; Projects does not
write AI-owned configuration records.

## Known transitional seams

- Capability-local code still has inherited direct dependencies on stable
  modules in sibling capabilities. The architecture ratchet blocks new private
  role dependencies without pretending all historical seams were removed in
  this physical migration.
- The localization records and inventory projectors still use the Lifecycle `Project` entity while
  locking and verifying project identity. A future local record can remove that
  inverse dependency without changing this folder migration.
- Project classification and validation are owned locally under Lifecycle;
  Platform keeps an independent analytics taxonomy and sanitization policy.
- The shared PostgreSQL schema remains intentional. Code ownership is isolated
  first so schema and database separation can happen independently later.
