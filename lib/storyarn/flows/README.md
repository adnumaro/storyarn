# Flows internal organization

`Storyarn.Flows` is one bounded context. Its first level is organized by eight
business capabilities; these folders are implementation slices of Flows, not
additional bounded contexts:

| Capability | Responsibility |
| --- | --- |
| `editor/` | The authored Flow aggregate: flows, nodes, connections, sequences, hierarchy, editor catalogs, and atomic graph mutations. |
| `logic/` | Conditions, instructions, formulas, variable vocabulary, constraints, search, and namespace resolution. |
| `references/` | Entity and variable projections, target validation, trash/restore integrity, avatars, assets, and rich-text mentions. |
| `runtime/` | Evaluation, player sessions, dialogue preview, debugging, runtime graphs, navigation history, and ephemeral process state. |
| `health/` | Canonical structural analysis, health flags, statistics, findings, severity, and dashboard/export parity. |
| `localization/` | Flow-localizable content vocabulary, extraction projection, and player-facing word counts. |
| `ai/` | Flow context construction, neighborhood reads, source locking, and Flow-owned AI contracts. |
| `versioning/` | Flow version history, snapshot capture, validation, comparison, asset materialization, and restore. |

Flow, node, connection, and sequence authoring deliberately remain in the same
`editor/` capability. They form one transactional graph aggregate: splitting
them into independent capability folders would hide the invariants around
endpoints, pins, parents, positions, entry/exit nodes, references, and atomic
derived projections.

Cross-capability workflows enter another capability through its facade. Stable
Flow entities and contracts retain their established module identity, while
private commands, queries, projections, execution modules, events, and adapters
remain behind their owning capability.

## Responsibility folders

Each capability uses only the roles it actually needs:

| Folder | Responsibility |
| --- | --- |
| `commands/` | State-changing use cases, transactions, locks, and effect coordination. A command may also read when the read is inseparable from its invariant. |
| `queries/` | Read-only persistence operations and bounded projections. |
| `entities/` | Mutable business state owned by Flows, including Ecto schemas and changesets. |
| `contracts/` | Stable Flow value contracts owned by the capability and exposed through its facade or required by configuration. |
| `rules/` | Deterministic validation, normalization, formula, graph, and health decisions. |
| `data/` | Passive consumer-local SQL projections or immutable reference data; never persistence I/O. |
| `execution/` | Stateful or multi-step runtime orchestration such as evaluation, debugging, and snapshot materialization. |
| `events/` | Business facts owned by the capability that produced them. |
| `adapters/` | Technical translation to memory/OTP state, object storage, PostgreSQL locks, optimized raw SQL, or another provider. |

Commands and execution workflows still decide transaction boundaries, lock
namespaces and acquisition order. An adapter executes the provider-specific
operation; it must not open a nested transaction or silently change that order.

This is a pragmatic functional architecture. A large transaction is not split
merely to make a command file contain only writes, and a function does not need
a port merely to satisfy a diagram. The folder must still describe the
responsibility the module actually owns.

## `data/`

`data/` accepts exactly two categories.

### Consumer-local SQL projections

These are Ecto schemas over the shared database, shaped for one capability's
workflow. They deliberately duplicate code instead of importing another
capability's or bounded context's model:

- `Editor.Data.*` contains the foreign project, Scene, Sheet, avatar, gallery,
  and asset facts needed while authoring the Flow aggregate.
- `References.Data.*` contains the target and variable facts required to
  validate and rebuild Flow-owned reference indexes.
- `Runtime.Data.*` contains only the authored facts needed to execute a Flow;
  it does not use Editor's persistence model as its read model.
- `Health.Data.*` may map the same Flow tables independently when project-wide
  analysis needs a purpose-built projection.
- `AI.Data.*` is bounded to the evidence needed to build a Flow AI package.
- `Localization.Data.*` maps the localization inventory and active language
  facts needed by Flow extraction.
- `Versioning.Data.*` is independently shaped for capture, validation,
  materialization, and exact restore.

Two capabilities may map the same SQL table with different fields and
associations. That duplication is intentional: changing Runtime's executable
graph must not silently change Editor, Health, AI, or Versioning. Sharing
PostgreSQL during this phase does not imply sharing schema modules.

A projection declares fields, associations, types, and narrowly scoped
changesets required by its consumer. It does not call `Repo`, coordinate a
transaction or lock, emit an event, contact a provider, or decide business
policy. Reads live in `queries/`; writes and invariants live in `commands/` or
an indivisible `execution/` workflow.

### Reference data

Reference data is immutable application data with no database identity,
lifecycle, external I/O, or transaction semantics. Flows currently needs no
separate reference-data catalog; the category is reserved so `data/` cannot
drift into a generic persistence or utility folder.

There is intentionally no generic `persistence/` folder.

## Stable module identities

Files are grouped by capability without renaming established identities used by
Ecto associations, LiveVue encoders, runtime configuration, tests, or external
callers:

- `Storyarn.Flows.Flow`, `FlowNode`, `FlowConnection`, `SequenceConfig`,
  `SequenceTrack`, and `SequenceVisualLayer`
- `Storyarn.Flows.Condition`, `Instruction`, `VariableReference`, and
  `EntityTrashRef`
- `Storyarn.Flows.Evaluator.State`
- `Storyarn.Flows.AI.ContextContract`
- `Storyarn.Flows.Versioning.EntityVersionRecord`, `FlowSnapshot`,
  `RestorePolicy`, and `SourceContract`

Stable identity is a compatibility contract, not permission to call private
commands, queries, projections, execution modules, events, or adapters.

## Boundary rules

- `StoryarnWeb`, application coordinators, and workers call only
  `Storyarn.Flows`.
- The root facade composes only the eight capability facades.
- A capability consumes another capability through its facade, never through a
  sibling's private role folders or `data/` schemas.
- Events remain owned by the capability producing the fact. Platform decides
  which cross-cutting product reactions follow that fact.
- Technical state and provider translation live under `adapters/`; business
  policy remains in commands, rules, events, or execution workflows.
- `Repo` and SQL tables remain shared in this phase. Code ownership is isolated
  first so schema and database separation can happen independently later.
