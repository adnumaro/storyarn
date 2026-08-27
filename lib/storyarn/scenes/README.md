# Scenes internal organization

`Storyarn.Scenes` is the bounded-context facade. Its first level is organized
by eight business capabilities. These are cohesive implementation slices of
Scenes, not additional bounded contexts:

| Capability     | Responsibility                                                                                     |
| -------------- | -------------------------------------------------------------------------------------------------- |
| `access/`      | Scene-specific project visibility and membership reads.                                            |
| `editor/`      | Scene hierarchy and the authored layers, zones, pins, connections, annotations, and ambient flows. |
| `assets/`      | Scene-owned asset catalog, uploads, background variants, zone images, and asset materialization.   |
| `expressions/` | Conditions, instructions, variable vocabulary, constraints, and namespace resolution.              |
| `references/`  | Validation and projection of entity and variable references authored by Scenes.                    |
| `exploration/` | Saved exploration sessions, consumer-local Flow and Sheet reads, and the in-memory play runtime.   |
| `health/`      | Canonical Scene health rules, snapshots, and project dashboard findings.                           |
| `versioning/`  | Scene version history, snapshot capture, conflict preview, materialization, and restore.           |

Cross-capability workflows enter another capability through its facade. Stable
Scene entities and value contracts may retain their established module identity,
but private commands, queries, projections, execution modules, events, and
adapters do not cross capability boundaries.

## Responsibility folders

Each capability uses only the roles it actually needs:

| Folder            | Responsibility                                                                                             |
| ----------------- | ---------------------------------------------------------------------------------------------------------- |
| `commands/`       | State-changing use cases, transactions, locks, and effect coordination.                                    |
| `queries/`        | Read-only persistence operations and bounded projections.                                                  |
| `entities/`       | Mutable business state owned by Scenes, including Ecto schemas and changesets.                             |
| `contracts/`      | Stable Scene value contracts shared across capabilities or required by framework configuration.            |
| `compatibility/`  | Deprecated public identities that delegate to the canonical capability without making contracts effectful. |
| `rules/`          | Pure validation, normalization, policy, and health decisions.                                              |
| `projections/`    | Passive consumer-local SQL projections; never changesets, policy, or persistence I/O.                      |
| `reference_data/` | Immutable compiled catalogs with no database identity or lifecycle.                                        |
| `execution/`      | Stateful or multi-step runtime orchestration such as exploration and snapshot materialization.             |
| `events/`         | Business facts owned by the capability that produced them.                                                 |
| `adapters/`       | Technical translation to object storage, image processing, PostgreSQL locks, or another provider.          |

This is a pragmatic functional architecture. A function does not need a port
merely to satisfy a diagram, and a capability does not need every role folder.
The folder does have to describe the responsibility the module actually owns.

## `projections/`

These are Ecto schemas over the shared database, shaped for one capability's
workflow. They deliberately duplicate code instead of importing another
capability's or bounded context's model:

- `Editor.Projections.FlowRecord` is the small Flow identity needed while authoring a
  pin or ambient-flow link.
- `Exploration.Projections.FlowRecord`, `FlowNodeRecord`, and
  `FlowConnectionRecord` form the executable graph needed by exploration.
- `Health.Projections.SheetRecord` and related block/table projections contain only
  the foreign facts needed to evaluate Scene health.
- `References.Projections.VariableReferenceRecord` is the projection used to maintain
  the reference index, while `Versioning.Projections.SheetRecord` is independently
  shaped for snapshot capture and restore.

Those modules may point at the same SQL tables and still differ in fields,
associations, indexes, and future storage strategy. Duplication is intentional:
changing Exploration's Flow model must not silently change Editor, Health, or
Versioning behavior.

A projection declares fields, associations, and types. It has no changesets.
Database reads live in `queries/` or the read portion of an owning application
workflow; ordinary writes and invariants stay with the capability that owns
them. A sibling capability never imports the projection directly.

## `reference_data/`

Reference data is a small immutable catalog compiled with the application. It
has no database identity, lifecycle, external I/O, or transaction semantics.
Scenes currently needs no such catalog, so no capability currently creates
this role.

`projections/` cannot call `Repo`, coordinate locks or transactions, emit events,
perform external I/O, or decide business policy.

## Stable module identities

Files are grouped by capability without renaming established contracts consumed
by Ecto associations, LiveVue, configuration, tests, or external callers:

- `Storyarn.Scenes.Scene`, `SceneLayer`, `SceneZone`, `ScenePin`,
  `SceneConnection`, `SceneAnnotation`, and `SceneAmbientFlow`
- `Storyarn.Scenes.Condition`, `Instruction`, and `RoutePoints`
- `Storyarn.Scenes.ExplorationSession` and `Storyarn.Scenes.FlowRuntime.State`
- `Storyarn.Scenes.Versioning.EntityVersionRecord`, `SceneSnapshot`,
  `RestorePolicy`, and `AssetCopyError`

Stable identity is a compatibility contract, not permission to call private
commands or queries.
`Storyarn.Scenes.Logic` remains a deprecated compatibility identity;
`Storyarn.Scenes.Expressions` is the canonical capability boundary.

## Boundary rules

- `StoryarnWeb` and external application coordinators call only
  `Storyarn.Scenes`.
- The root facade composes only the eight capability facades and stable
  entities/contracts.
- A capability may consume another capability's facade, never its private role
  folders or `projections/` schemas.
- Technical behavior lives under `adapters/`; business policy remains in the
  owning command, rule, event, or execution workflow.
- `Repo` and SQL tables remain shared in this phase. Code ownership is isolated
  now so schema and database separation can happen independently later.
