# Projects internal organization

`Storyarn.Projects` is the bounded-context facade. Its first level is organized
by Project-owned business capabilities. These folders are implementation slices
inside one bounded context; none is an independently named bounded context.

| Capability     | Responsibility                                                                                                                              |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `lifecycle/`   | Project identity, creation, configuration, source language, update, soft deletion and Workspace-owned hard-delete coordination.             |
| `access/`      | Project memberships, roles, authorization and invitations, including Project-owned invitation intent and copy.                              |
| `assets/`      | Project assets, upload and trash lifecycle, blob identity, storage compensation, image processing and storage adapters.                     |
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
| `adapters/`       | Translation to storage, archives, images, PostgreSQL locks, Oban, email or another provider.                                                                |

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
lifecycle, external I/O or transaction semantics. The lifecycle source-language
catalog is the current example.

### Writable records

`records/` is reserved for models that participate in controlled Project-owned
writes. The closed content records are used by exact import/snapshot
reconstitution, trash, repair and Project-wide integrity workflows. They are not
presented as ordinary read projections.

References also keeps its `FlowNodeRecord` and `TableRowRecord` here because
Project-owned repair commands update those rows. Their historical
`Storyarn.Projects.References.Persistence.*` module identities remain stable;
the physical `records/` location states their actual write authority.

Localization records are the most sensitive case. Projects may write them only
while maintaining derived localization inventory after Project content changes,
or while exactly reconstituting a Project import/snapshot. Ordinary translation,
review and provider workflows remain owned by Localization.

There is intentionally no generic `data/`, `persistence/` or `shared/` folder.

## Stable facades over use cases

The large historical entry modules remain stable but are now routing surfaces:

- `ProjectCrud` delegates reads to `Lifecycle.Queries.ProjectQueries` and
  state-changing transactions to `Lifecycle.Commands.ProjectCommands`.
- `Assets` routes queries, ordinary commands, trash, uploads, blob verification
  and exact reconstitution through explicit use-case modules. The shared lock,
  compensation and upload protocol remains an indivisible execution kernel so
  its order cannot drift between wrappers.
- `Imports` routes preparation, review, queue/cancellation and attempt lookup
  through role-specific modules. Its plan reservation and cleanup workflow stays
  together under `execution/` for the same transactional reason.

## Public and worker boundaries

- `StoryarnWeb`, application coordinators and other bounded contexts enter
  through `Storyarn.Projects`.
- The root facade composes the nine capability facades. Stable entity and type
  aliases remain there only as compatibility contracts.
- Background jobs remain physically grouped under `workers/projects/`, retain
  their persisted `Storyarn.Workers.*` module identity and call only
  `Storyarn.Projects`. Their root-facade entry points are
  hidden from generated documentation but contract-tested.
- `content/`, capability role folders and technical adapters are private to
  Projects.
- Storage paths, archive formats, queues, worker arguments and Ecto module
  identities do not change because a file moved.

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
  Projects remains the current writer of AI configuration records. That is an
  explicit ownership decision to revisit, not permission to use AI as a generic
  shared layer.
- The object-store provider, hashing and locking mechanism is still mixed with
  Project-specific blob and cleanup policy under `assets/adapters/storage/`.
  Existing external callers are exact ENG-107 migration exceptions; new callers
  are forbidden until the neutral technical mechanism is extracted.
- The shared PostgreSQL schema remains intentional. Code ownership is isolated
  first so schema and database separation can happen independently later.
