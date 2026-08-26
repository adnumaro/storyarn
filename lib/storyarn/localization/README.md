# Localization internal organization

`Storyarn.Localization` is the bounded-context facade. Its first level is
organized by eight business capabilities. They are implementation slices of
Localization, not additional bounded contexts:

| Capability | Responsibility |
| --- | --- |
| `access/` | Localization's project visibility model and transactional validation of project-owned references. |
| `languages/` | Project languages, source-language changes, ordering, and the immutable language catalog. |
| `texts/` | Localized-text lifecycle, runtime inventory, extraction, source reconciliation, and export-facing text reads. |
| `providers/` | Translation-provider configuration and provider technical adapters. |
| `glossary/` | Glossary entries and synchronization of a language pair with the configured provider. |
| `translation/` | Synchronous translation and durable asynchronous translation runs. |
| `exchange/` | Translator-facing CSV/XLSX import and export formats. |
| `reporting/` | Read-only progress, word-count, voice-over, and source-type reports. |

Cross-capability workflows consume another capability through its facade. For
example, Languages asks `Texts` to reset or reconcile inventory; Glossary asks
`Providers` for provider state; Translation consumes `Texts` and `Providers`.
Private command, query, data, execution, and adapter modules are not shared.

## Responsibility folders

Each capability uses only the folders it needs:

| Folder | Responsibility |
| --- | --- |
| `commands/` | State-changing use cases, transactions, locks, and effect coordination. |
| `queries/` | Read-only persistence operations. |
| `entities/` | Localization-owned mutable schemas and changesets. |
| `contracts/` | Stable Localization value/protocol contracts consumed by more than one capability or context. |
| `rules/` | Pure validation, normalization, eligibility, and transformation rules. |
| `data/` | Passive consumer-local SQL projections or immutable reference data; never persistence I/O. |
| `execution/` | Long-running application orchestration such as batch translation or glossary synchronization. |
| `adapters/` | Technical translations to PostgreSQL-specific operations, HTTP providers, Oban, PubSub, notifications, or XLSX encoding. |

This is a pragmatic functional architecture. A capability does not need every
role folder, and technical behavior is not wrapped in a port merely to satisfy
a diagram. The folder name must, however, describe the responsibility it owns.

## `data/`

`data/` accepts exactly two categories.

### Consumer-local SQL projections

These are minimal Ecto schemas over shared tables. They let each capability
read the exact shape it needs without importing another capability's or bounded
context's code model. Duplication is intentional:

- `Access.Data.ProjectRecord`, `Languages.Data.ProjectRecord`,
  `Providers.Data.ProjectRecord`, `Glossary.Data.ProjectRecord`,
  `Texts.Data.ProjectRecord`, and `Translation.Data.ProjectRecord` all describe
  different consumer needs over the same `projects` table.
- `Texts.Data.FlowNodeRecord` and `Texts.Data.BlockRecord` contain only the
  fields needed to build Localization's runtime inventory.
- `Reporting.Data.LocalizedTextRecord` is an aggregation projection and does
  not reuse the write-side `LocalizedText` entity.

A data module declares fields, associations, and types only. Queries and
commands own database access. Ordinary writes remain with the owning capability
or bounded context.

### Reference data

Reference data is an immutable catalog compiled with the application. It has no
database identity, lifecycle, external I/O, or transaction semantics.
`Languages.Data.Catalog` is the current example.

Every data module documents which category it belongs to and why the consumer
needs it. `data/` is not a synonym for persistence and must not become a generic
schema folder.

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
- Stable schemas and contracts may be named where framework configuration or
  serialization requires their compile-time identity; they do not expose
  commands or queries.
- Technical adapters live under `adapters/` and do not own Localization policy.
- `Repo` remains shared during this phase, but no capability imports another
  capability's Ecto projection.
