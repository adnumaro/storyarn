# Phase 8A: Foundation + Native Round-Trip

> **Parent document:** [PHASE_8_EXPORT.md](../PHASE_8_EXPORT.md)
>
> **Tasks:** 1-8 of 25

**Goal:** Build the core export/import infrastructure and achieve lossless Storyarn JSON round-trip (export → import = identical project data).

---

## Tasks

| Order   | Task                                    | Dependencies  | Testable Outcome                             |
|---------|-----------------------------------------|---------------|----------------------------------------------|
| 1       | Export context + options schema         | None          | ExportOptions struct validates correctly     |
| 2       | Serializer behaviour + registry         | Task 1        | Registry resolves format → module            |
| 3       | Data collector                          | Task 1        | Loads full project data in single pass       |
| 4       | Storyarn JSON serializer (all sections) | Tasks 2-3     | Full project exports to JSON                 |
| 5       | Import parser (Storyarn JSON)           | None          | Can parse exported JSON back                 |
| 6       | Import round-trip test                  | Tasks 4-5     | **export → import = identical project data** |
| 7       | Pre-export validation                   | Task 4        | Catches broken refs, orphans, etc.           |
| 8       | Import preview + conflict detection     | Task 5        | Shows diff before executing import           |

---

## Task 1: Export Context + Options Schema

Create `Storyarn.Exports` context (facade pattern) with:
- `Exports.export_project/2` - Main export function (sync/async decision)
- `Exports.export_flows/2` - Export specific flows
- `Exports.export_sheets/2` - Export specific sheets
- `Exports.export_scenes/2` - Export specific scenes
- `Exports.get_export_options/1` - Get available options for UI

```elixir
%ExportOptions{
  format: :storyarn | :ink | :yarn | :unity | :godot | :godot_dialogic | :unreal | :articy,
  version: "1.0.0",
  include_sheets: true,
  include_flows: true,
  include_scenes: true,
  include_screenplays: true,
  include_localization: true,
  include_assets: :references | :embedded | :bundled,
  languages: ["en", "es"] | :all,
  flow_ids: [uuid] | :all,
  sheet_ids: [uuid] | :all,
  scene_ids: [uuid] | :all,
  validate_before_export: true,
  pretty_print: true
}
```

## Task 2: Serializer Behaviour + Registry

- Define `Storyarn.Exports.Serializer` behaviour (see [ARCHITECTURE.md](./ARCHITECTURE.md))
- Create `Storyarn.Exports.SerializerRegistry` module
- Serializer implementations (each implements the behaviour):
  - `Exports.Serializers.StoryarnJSON` - Native format (lossless round-trip)
  - `Exports.Serializers.Ink` - Ink .ink text + metadata JSON
  - `Exports.Serializers.Yarn` - Yarn Spinner .yarn text + string tables
  - `Exports.Serializers.UnityJSON` - Dialogue System for Unity JSON
  - `Exports.Serializers.GodotJSON` - Generic Godot JSON (no addon required)
  - `Exports.Serializers.GodotDialogic` - Dialogic 2 .dtl timeline format
  - `Exports.Serializers.UnrealCSV` - DataTable CSV + metadata JSON
  - `Exports.Serializers.ArticyXML` - articy:draft XML format

## Task 3: Data Collector (Dual Mode)

- Create `Storyarn.Exports.DataCollector` module
- `stream/2` - Streaming mode via `Repo.stream` (constant memory, for production exports)
- `collect/2` - In-memory mode (for validation, conflict detection, tests)
- Stream sections: sheets (with blocks, table columns/rows), flows (with nodes, connections), scenes (with layers, pins, zones, connections, annotations), screenplays (with elements, linked_flows), localization, assets
- Batched preloads (500 rows per batch) to avoid N+1 without loading everything
- Respect `ExportOptions` filters (selected flows, sheets, scenes, languages)
- Entity counting for progress calculation (`count_entities/2`)

## Task 4: Storyarn JSON Serializer

Implement all sections per [STORYARN_JSON_FORMAT.md](./STORYARN_JSON_FORMAT.md).

## Task 5: Import Parser (Storyarn JSON)

Create `Storyarn.Imports` context with:
- `Imports.parse_file/1` - Parse and detect format
- Parser module: `Imports.Parsers.StoryarnJSON`

## Task 6: Import Round-Trip Test

**This is the P0 test.** Export a project → import into a fresh project → compare all data. Diff must be empty.

## Task 7: Pre-Export Validation

Create `Exports.Validator` module:
- `Validator.validate_project/2` - Run all validations
- `Validator.validate_flows/2` - Flow-specific validations
- `Validator.validate_sheets/2` - Sheet-specific validations
- `Validator.validate_scenes/2` - Scene-specific validations
- `Validator.validate_screenplays/2` - Screenplay-specific validations
- `Validator.validate_localization/2` - Translation validations
- Return structured results with severity, message, entity references

### Validation Rules

| Rule                   | Severity   | Description                                 |
|------------------------|------------|---------------------------------------------|
| `orphan_nodes`         | Warning    | Nodes not connected to flow graph           |
| `broken_references`    | Error      | References to deleted sheets/flows/scenes   |
| `missing_entry`        | Error      | Flow without Entry node                     |
| `unreachable_nodes`    | Warning    | Nodes not reachable from Entry              |
| `missing_translations` | Warning    | Untranslated strings for selected languages |
| `circular_jumps`       | Warning    | Flow A → B → A cycles (may be intentional)  |
| `empty_dialogue`       | Warning    | Dialogue nodes with no text                 |
| `invalid_conditions`   | Error      | Unparseable condition expressions           |
| `invalid_instructions` | Error      | Unparseable instruction code                |
| `missing_speakers`     | Warning    | Dialogue without speaker                    |
| `orphan_sheets`        | Info       | Sheets with no references                   |

### Validation Results Schema

```elixir
%ValidationResult{
  status: :passed | :warnings | :errors,
  errors: [
    %{
      rule: :broken_reference,
      severity: :error,
      message: "Flow 'Tavern Intro' references deleted sheet 'Old NPC'",
      source_type: :flow_node,
      source_id: "uuid",
      target_type: :sheet,
      target_id: "uuid"
    }
  ],
  warnings: [...],
  info: [...],
  statistics: %{
    checked_flows: 32,
    checked_sheets: 145,
    checked_nodes: 856
  }
}
```

## Task 8: Import Preview + Conflict Detection

- `Imports.preview/2` - Generate import preview
- `Imports.detect_conflicts/2` - Find existing entities
- `Imports.execute/3` - Run import with options
- Transaction wrapper for atomic import
- Import report generation

---

## Database Changes

### Migration: Export Jobs (for async exports)

```elixir
create table(:export_jobs) do
  add :project_id, references(:projects, on_delete: :delete_all), null: false
  add :user_id, references(:users, on_delete: :nilify_all), null: false
  add :format, :string, null: false
  add :options, :map, default: %{}
  add :status, :string, default: "pending"  # pending, processing, completed, failed
  add :progress, :integer, default: 0       # 0-100
  add :file_key, :string                    # Storage key for result file
  add :file_size, :integer
  add :error_message, :text
  add :started_at, :utc_datetime
  add :completed_at, :utc_datetime

  timestamps()
end

create index(:export_jobs, [:project_id, :status])
create index(:export_jobs, [:user_id])
```
