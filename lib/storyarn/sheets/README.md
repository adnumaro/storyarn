# Sheets internal organization

`Storyarn.Sheets` is one bounded context. Its first level is organized by nine
business capabilities; these folders are implementation slices of Sheets, not
additional bounded contexts:

| Capability | Responsibility |
| --- | --- |
| `access/` | Sheet-specific project visibility and membership reads. |
| `ai/` | Sheet context construction, source locking, and Sheet-owned AI contracts. |
| `assets/` | Asset catalog, uploads, image processing, storage compensation, and asset events used by Sheets. |
| `editor/` | Sheet hierarchy, blocks, tables, galleries, avatars, inheritance, and dialogue-audio authoring. |
| `logic/` | Variables, formulas, constraints, binding rewrites, and namespace resolution. |
| `localization/` | Sheet-localizable content vocabulary, word counts, and extraction projection. |
| `references/` | Entity and variable reference projection, backlinks, integrity, and foreign appearances. |
| `health/` | Canonical Sheet health rules, snapshots, and project dashboard findings. |
| `versioning/` | Sheet version history, snapshot capture, conflict preview, materialization, and restore. |

Cross-capability workflows enter another capability through its facade. Stable
Sheet entities and contracts retain their established module identity, while
private commands, queries, projections, execution modules, events, and adapters
remain behind their owning capability.

## Responsibility folders

Each capability uses only the roles it actually needs:

| Folder | Responsibility |
| --- | --- |
| `commands/` | State-changing use cases, transactions, locks, and effect coordination. |
| `queries/` | Read-only persistence operations and bounded projections. |
| `entities/` | Mutable business state owned by Sheets, including Ecto schemas and changesets. |
| `contracts/` | Stable Sheet value contracts shared across capabilities or required by configuration. |
| `rules/` | Pure validation, normalization, policy, formula, and health decisions. |
| `data/` | Passive consumer-local SQL projections or immutable reference data; never persistence I/O. |
| `execution/` | Stateful or multi-step runtime orchestration such as AI context and snapshot materialization. |
| `events/` | Business facts owned by the capability that produced them. |
| `adapters/` | Technical translation to object storage, image processing, PostgreSQL locks, or another provider. |

This is a pragmatic functional architecture. A function does not need a port
only to satisfy a diagram, and a capability does not need every role folder.
The folder must describe the responsibility the module actually owns.

## `data/`

`data/` accepts exactly two categories.

### Consumer-local SQL projections

These are Ecto schemas over the shared database, shaped for one capability's
workflow. They deliberately duplicate code instead of importing another
capability's or bounded context's model:

- `Editor.Data.FlowRecord` and `FlowNodeRecord` contain the Flow facts required
  by the Sheet-owned dialogue-audio workspace.
- `Health.Data.*` contains only the authored facts needed to evaluate Sheet
  health without importing editor internals.
- `References.Data.EntityReferenceRecord` is the reference index maintained by
  the reference capability.
- `Versioning.Data.SheetRecord` is independently shaped for snapshot
  materialization and repairs; it does not reuse the editor entity merely
  because both currently map to `sheets`.
- `Assets.Data.ProjectRecord` and `Access.Data.ProjectRecord` map the same SQL
  table but serve different workflows and may evolve independently.

A projection declares fields, associations, types, and narrowly scoped
changesets required by its consumer. Database reads live in `queries/` or the
read portion of an owning workflow. `data/` never calls `Repo`, coordinates
locks or transactions, emits events, performs external I/O, or decides policy.

### Reference data

Reference data is a small immutable catalog compiled with the application. It
has no database identity, lifecycle, external I/O, or transaction semantics.
Sheets currently needs no separate catalog of this kind; the category is
reserved so `data/` cannot drift into a generic persistence or utility folder.

## Stable module identities

Files are grouped by capability without renaming established contracts consumed
by Ecto associations, LiveVue, configuration, tests, or external callers:

- `Storyarn.Sheets.Sheet`, `Block`, `BlockGalleryImage`, `SheetAvatar`,
  `TableColumn`, and `TableRow`
- `Storyarn.Sheets.FormulaEngine`
- `Storyarn.Sheets.AI.ContextContract`, `AI.SheetContext`, and `AI.SourceLocks`
- `Storyarn.Sheets.Versioning.EntityVersionRecord`, `SheetSnapshot`,
  `RestorePolicy`, and `AssetCopyError`

Stable identity is a compatibility contract, not permission to call private
commands, queries, projections, or adapters.

## Boundary rules

- `StoryarnWeb` and external application coordinators call only
  `Storyarn.Sheets`.
- The root facade composes only the nine capability facades and stable entities
  or contracts.
- A capability consumes another capability through its facade, never through a
  sibling's private role folders or `data/` schemas.
- Technical behavior lives under `adapters/`; business policy remains in the
  owning command, rule, event, or execution workflow.
- `Repo` and SQL tables remain shared in this phase. Code ownership is isolated
  first so schema and database separation can happen independently later.
- Localization extraction still writes the shared localization inventory during
  this code-only phase. Its write ownership is deliberately deferred to the
  later read/write-separation decision instead of being changed implicitly here.
