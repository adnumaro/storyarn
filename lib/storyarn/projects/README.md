# Projects internal organization

`Storyarn.Projects` is the bounded-context facade. Its first level is organized
by Project-owned business capabilities. These folders are implementation slices
inside one bounded context; none is an independently named bounded context.

| Capability | Responsibility |
| --- | --- |
| `lifecycle/` | Project identity, creation, configuration, source language, update, soft deletion and Workspace-owned hard-delete coordination. |
| `access/` | Project memberships, roles, authorization and invitations, including Project-owned invitation intent and copy. |
| `assets/` | Project assets, upload and trash lifecycle, blob identity, storage compensation, image processing and storage adapters. |
| `overview/` | Project-wide dashboards, activity, statistics, tool read models, health findings and structural analysis. |
| `trash/` | Cross-tool Project trash, restore, hard deletion and retention workflows. |
| `references/` | Project-wide entity and variable reference indexes, integrity, repair and usage queries. |
| `interchange/` | Project import and export workflows, formats, parsers, serializers, validation and exact reconstitution writers. |
| `templates/` | Project template publication, portable bundles, installation, audit and lifecycle. |
| `versioning/` | Full-project snapshot capture, storage, restore, recovery, reconstitution, reconciliation and accounting. |

Imports and exports are two directions of the same Project interchange
capability. Snapshot restore and project import remain separate workflows:
interchange imports authored external content, while versioning reconstitutes a
canonical Project snapshot with its durability and fencing guarantees.

## Closed Project content model

`content/` is not a tenth capability, a shared layer or another bounded
context. It is the closed Project-owned interpretation of Flow, Sheet, Scene
and Localization content needed by several Project capabilities.

Projects deliberately duplicates these contracts, projections and rules. It
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
   and projections directly until capability-local duplication becomes useful.

The Flow and Scene conditions, instructions and variable rules remain separate
even where they look similar. Their duplication is intentional and they must
not be merged merely to reduce line count.

## Responsibility folders

Each capability uses only the roles it needs:

| Folder | Responsibility |
| --- | --- |
| `commands/` | State-changing use cases, transactions, locks and effect coordination. |
| `queries/` | Read-only persistence operations and purpose-built projections. |
| `entities/` | Mutable Project-owned business state, including Ecto schemas and changesets. |
| `contracts/` | Stable values and error/receipt contracts owned by the capability. |
| `rules/` | Validation, normalization, policy and content interpretation. A rule may retain a narrow persistence read when separating it would obscure the invariant, but it does not own a state-changing workflow. |
| `data/` | Passive consumer-local SQL projections or immutable reference data; never persistence I/O. |
| `execution/` | Stateful or multi-step workflows whose transaction, lock or recovery order must remain intact. |
| `events/` | Product facts owned by Projects. |
| `delivery/` | Project-owned delivery decisions and content, before technical handoff. |
| `adapters/` | Translation to storage, archives, images, PostgreSQL locks, Oban, email or another provider. |

This is a pragmatic functional architecture. A transaction is not split merely
to make a file fit a diagram, and a pure function does not need a behaviour or
port unless there is a real replaceable seam.

## `data/`

`data/` accepts exactly two categories.

### Consumer-local SQL projections

These are Ecto schemas over the shared database, shaped for one Project
capability. They may map tables written by another capability or bounded
context, and two capabilities may deliberately map the same table differently.

A projection declares fields, associations, types and narrowly scoped
changesets needed by its consumer. It does not call `Repo`, open a transaction,
acquire a lock, emit an event, enqueue work or contact a provider. Reads belong
in `queries/`; writes and invariants belong in `commands/` or an indivisible
`execution/` workflow. A projection may call deterministic normalization or
changeset rules owned by the same capability; those rules do not turn `data/`
into an I/O layer.

Some projections retain historical module identities containing
`.Persistence.`. That namespace is a compatibility contract for associations
and existing callers; there is no physical `persistence/` layer.

### Reference data

Reference data is immutable application data with no database identity,
lifecycle, external I/O or transaction semantics. The lifecycle source-language
catalog is the current example.

There is intentionally no generic `persistence/` or `shared/` folder.

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
- The localization projections still use the Lifecycle `Project` entity while
  locking and verifying project identity. A future local record can remove that
  inverse dependency without changing this folder migration.
- `Project` still consumes Platform's product-metric project taxonomy, and
  Projects remains the current writer of AI configuration records. Those are
  explicit ownership decisions to revisit, not permission to use Platform or AI
  as generic shared layers.
- The shared PostgreSQL schema remains intentional. Code ownership is isolated
  first so schema and database separation can happen independently later.
