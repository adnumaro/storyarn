# Localization internal organization

`Storyarn.Localization` is the bounded-context facade. Its first level is
organized by eight business capabilities. They are implementation slices of
Localization, not additional bounded contexts:

| Capability        | Responsibility                                                                                                |
| ----------------- | ------------------------------------------------------------------------------------------------------------- |
| `project_access/` | Localization's project visibility model and transactional validation of project-owned references.             |
| `languages/`      | Project languages, source-language changes, ordering, and the immutable language catalog.                     |
| `texts/`          | Localized-text lifecycle, runtime inventory, extraction, source reconciliation, and export-facing text reads. |
| `providers/`      | Translation-provider configuration and provider technical adapters.                                           |
| `glossary/`       | Glossary entries and synchronization of a language pair with the configured provider.                         |
| `translation/`    | Synchronous translation and durable asynchronous translation runs.                                            |
| `exchange/`       | Translator-facing CSV/XLSX import and export formats.                                                         |
| `reporting/`      | Read-only progress, word-count, voice-over, and source-type reports.                                          |

Cross-capability workflows consume another capability through its facade. For
example, Languages asks `Texts` to reset or reconcile inventory; Glossary asks
`Providers` for provider state; Translation consumes `Texts` and `Providers`.
Private command, query, data, execution, and adapter modules are not shared.

## Responsibility folders

Each capability uses only the folders it needs:

| Folder            | Responsibility                                                                                                           |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `commands/`       | State-changing use cases, transactions, locks, and effect coordination.                                                  |
| `queries/`        | Read-only persistence operations.                                                                                        |
| `entities/`       | Localization-owned mutable schemas and changesets.                                                                       |
| `contracts/`      | Stable Localization value/protocol contracts consumed by more than one capability or context.                            |
| `rules/`          | Pure validation, normalization, eligibility, and transformation rules.                                                   |
| `projections/`    | Passive, consumer-owned, read-only SQL mappings over shared tables.                                                      |
| `reference_data/` | Immutable catalogs without database identity, lifecycle, or I/O.                                                         |
| `execution/`      | Long-running application orchestration such as batch translation or glossary synchronization.                            |
| `adapters/`       | Technical translations to PostgreSQL-specific operations, HTTP providers, Oban, PubSub, notifications, or XLSX encoding. |

This is a pragmatic functional architecture. A capability does not need every
role folder, and technical behavior is not wrapped in a port merely to satisfy
a diagram. The folder name must, however, describe the responsibility it owns.

## Projections and reference data

The passive data roles are explicit siblings of `adapters/`.

### Consumer-local SQL projections

These are minimal Ecto schemas over shared tables. They let each capability
read the exact shape it needs without importing another capability's or bounded
context's code model. Duplication is intentional:

- `ProjectAccess.Projections.ProjectRecord`, `Languages.Projections.ProjectRecord`,
  `Providers.Projections.ProjectRecord`, `Glossary.Projections.ProjectRecord`,
  `Texts.Projections.ProjectRecord`, and `Translation.Projections.ProjectRecord` all describe
  different consumer needs over the same `projects` table.
- `Texts.Projections.FlowNodeRecord` and `Texts.Projections.BlockRecord` contain only the
  fields needed to build Localization's runtime inventory.
- `Reporting.Projections.LocalizedTextRecord` is an aggregation projection and does
  not reuse the write-side `LocalizedText` entity.

A data module declares fields, associations, and types only. Queries and
commands own database access. Ordinary writes remain with the owning capability
or bounded context.

### Reference data

Reference data is an immutable catalog compiled with the application. It has no
database identity, lifecycle, external I/O, or transaction semantics.
`Languages.ReferenceData.Catalog` is the current example.

Every projection documents why its consumer needs it. Neither role is a
synonym for persistence or a place for generic schemas.

## Source-language write ownership

Localization is the sole ordinary writer of the shared `project_languages`
table. Project settings reads, ensures, and changes the source language through
`Storyarn.Localization`; neither `Storyarn.Projects` nor its Lifecycle
capability republishes those commands.

The shared SQL schema does not make the Localization entity a cross-context
contract. Projects retains its duplicated `ProjectLanguageRecord` for
Project-owned reads and privileged closed-graph materialization. Its current
write exceptions are narrowly classified as:

- template materialization;
- exact Project import/reconstitution, including replacement import;
- full-project snapshot restore and recovery.

No current Project repair writes `project_languages`. A future repair must name
the exact source, lock/transaction contract, and reason in
`config/architecture_boundaries.exs` before it is permitted. Derived localized
text inventory repair is a different authority and does not grant permission to
change Project languages.

## Localized-text write ownership

Localization is the sole ordinary writer of `localized_texts`, including
runtime extraction and Flow/Sheet entity-version restoration. Flows and Sheets
keep their own snapshot formats, ID maps and transaction orchestration, but
enter the owner through sealed adapters that expose only the exact restore
commands. Their duplicated Ecto mappings are read-only projections.

Projects retains four privileged closed-graph writers: validated import,
replacement archive, Project recovery and exact full-project snapshot restore.
These exceptions are inventoried by exact function and do not authorize an
ordinary Project feature to update translations or extracted source text.

The advisory-only inventory lock is a separate, sealed coordination port. Flow
snapshot build already holds Project `FOR SHARE` and then Flow `FOR UPDATE`, so
relocking Project inside Localization would change the historical order. The
reviewed Flow -> Localization facade -> Texts -> Extract chain therefore takes
only the advisory lock after the caller-owned Project lock. Ordinary
Localization commands must use `lock_inventory!/1`, which acquires Project
`FOR UPDATE` first.

## Stable module identities

Files are grouped by capability without renaming contracts whose module identity
is already consumed by Ecto associations, LiveVue encoding, configuration,
workers, or other bounded contexts:

- `Storyarn.Localization.ProjectLanguage`
- `Storyarn.Localization.LocalizedText`
- `Storyarn.Localization.GlossaryEntry`
- `Storyarn.Localization.ProviderConfig`
- `Storyarn.Localization.TranslationRun`
- `Storyarn.Localization.LocaleCode`
- `Storyarn.Localization.SourceContract`
- `Storyarn.Localization.RuntimeKey`
- `Storyarn.Localization.TranslationProvider`
- `Storyarn.Localization.Providers.DeepL`
- `Storyarn.Localization.TranslationJobQueue`

`Storyarn.Workers.LocalizationBatchTranslationWorker` is also a durable Oban
identity. The worker remains outside the bounded context and enters it only
through `Storyarn.Localization`.

## Boundary rules

- `StoryarnWeb`, controllers, and workers call only `Storyarn.Localization`.
- The Project general-settings surface is a reviewed composition point: its
  source-language behavior calls this root facade directly, while Project-owned
  settings continue through `Storyarn.Projects`.
- Stable schemas and contracts may be named where framework configuration or
  serialization requires their compile-time identity; they do not expose
  commands or queries.
- Technical adapters live under `adapters/` and do not own Localization policy.
- `Repo` remains shared during this phase, but no capability imports another
  capability's Ecto projection.
