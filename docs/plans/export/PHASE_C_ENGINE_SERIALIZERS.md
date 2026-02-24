# Phase 8C: Engine Serializers

> **Parent document:** [PHASE_8_EXPORT.md](../PHASE_8_EXPORT.md)
>
> **Tasks:** 12-17 of 25
>
> **Dependencies:** Phase A (Tasks 2-3) + Phase B (Tasks 9-10)

**Goal:** Implement serializers for each game engine format. Each serializer implements the `Serializer` behaviour and uses the expression transpiler from Phase B.

**Order: Middleware first (highest ROI), then engine-specific (indie-first), then interop.**

---

## Tasks

| Order  | Task                                             | Dependencies    | Testable Outcome                                   | Reach  |
|--------|--------------------------------------------------|-----------------|----------------------------------------------------|--------|
| 12     | **Ink serializer** (.ink text + metadata JSON)   | Tasks 2-3, 9-10 | Compiles with inklecate, loads in Ink runtimes     | ~90%   |
| 13     | **Yarn serializer** (.yarn text + string tables) | Tasks 2-3, 9-10 | Loads in Yarn Spinner for Unity/Godot              | ~40%   |
| 14     | Unity serializer + Lua emitter                   | Tasks 2-3, 9-10 | Produces Dialogue System for Unity compatible JSON | ~35%   |
| 15     | Godot serializer + GDScript emitter              | Tasks 2-3, 9-10 | Produces Dialogic 2 compatible JSON + generic JSON | ~15%   |
| 16     | Unreal serializer + CSV emitter                  | Tasks 2-3, 9-10 | Produces DataTable CSVs + metadata JSON            | ~15%   |
| 17     | articy:draft XML serializer                      | Tasks 2-3, 9-10 | Produces valid articy:draft XML                    | ~5%    |

---

## Task 12: Ink Serializer

**Module:** `Exports.Serializers.Ink`
**Target:** Ink runtime (13+ implementations)
**Output:** `.ink` text file + metadata JSON + localization CSVs

See [FORMAT_INK.md](./FORMAT_INK.md) for full format spec, conversion algorithm, and example output.

Key implementation points:
- Graph → linear conversion: topological sort + divert insertion for non-linear paths
- Variable name flattening: `mc.jaime.health` → `mc_jaime_health` (Ink forbids dots)
- Conditions → `{condition:}` inline or `{- condition: content}` for gathering choices
- Responses with conditions → `+ {condition} Choice text`
- Hub → stitch label (`= label_name`), Jump → divert (`-> knot_name`)
- Subflow → tunnel (`->->`)
- Metadata sidecar JSON for character/variable mapping
- Localization CSVs (Ink has no built-in localization)

## Task 13: Yarn Serializer

**Module:** `Exports.Serializers.Yarn`
**Target:** Yarn Spinner (Unity, Godot, GameMaker, GDevelop)
**Output:** `.yarn` text file(s) + string table CSVs + metadata JSON

See [FORMAT_YARN.md](./FORMAT_YARN.md) for full format spec, conversion algorithm, and example output.

Key implementation points:
- Each flow → one or more titled Yarn nodes (`title:` header + `---` body + `===` end)
- Hub nodes → separate Yarn nodes (jump targets)
- Line tags (`#line:id`) on all translatable strings for built-in localization
- Variables use `$` prefix: `<<declare $mc_jaime_health = 100>>`
- Conditions → `<<if>>` / `<<elseif>>` / `<<else>>` / `<<endif>>` blocks
- Instructions → `<<set $variable to value>>` commands
- Multi-file mode for projects with >5 flows, single-file otherwise
- String table CSVs per language (native Yarn localization)

## Task 14: Unity Serializer

**Module:** `Exports.Serializers.UnityJSON`
**Target:** Dialogue System for Unity
**Output:** Single JSON file

See [ENGINE_FORMATS.md](./ENGINE_FORMATS.md#unity-export-json) for full format spec and example output.

Key implementation points:
- Sheets → Actors with custom fields
- Flows → Conversations with entries
- Dialogue responses → child entries with `isGroup: false`
- Conditions → `conditionsString` (Lua via `ExpressionTranspiler.Unity`)
- Instructions → `userScript` (Lua via `ExpressionTranspiler.Unity`)
- Variables → Global variables table with typed initial values
- Hub/Jump/Subflow → Group entries, cross-conversation links

## Task 15: Godot Serializer

**Module:** `Exports.Serializers.GodotJSON`
**Target:** Dialogic 2
**Output:** JSON + optional `.dtl` timeline format

See [ENGINE_FORMATS.md](./ENGINE_FORMATS.md#godot-export-resourcejson) for full format spec and example output.

Key implementation points:
- Variable name conversion: `mc.jaime.health` → `mc_jaime_health`
- Asset paths: `res://` prefix
- Dual output: Dialogic-native `.dtl` AND generic JSON
- Conditions → GDScript expressions via `ExpressionTranspiler.Godot`
- Hub/Jump → Label/goto patterns within timelines

## Task 16: Unreal Serializer

**Module:** `Exports.Serializers.UnrealCSV`
**Target:** Unreal DataTable import
**Output:** ZIP with multiple CSV + JSON files

See [ENGINE_FORMATS.md](./ENGINE_FORMATS.md#unreal-export-datatable-csv--json) for full format spec and example output.

Key implementation points:
- Multi-file output (ZIP)
- DialogueLines.csv, Conditions.csv, Instructions.csv
- DialogueMetadata.json for graph structure
- Character DataTable + Variable DataTable
- Localization → Unreal StringTable CSV format
- Asset paths: `/Game/...` convention

## Task 17: articy:draft XML Serializer

**Module:** `Exports.Serializers.ArticyXML`
**Target:** articy:draft XML import
**Output:** Single XML file

See [ENGINE_FORMATS.md](./ENGINE_FORMATS.md#articydraft-compatible-export) for full format spec and example output.

Key implementation points:
- Deterministic GUID generation from Storyarn UUIDs (stable re-exports)
- Sheets → Entities with TechnicalName
- Flows → FlowFragments
- Variables → GlobalVariables with Namespaces
- Hub/Jump → articy Hubs/Jumps (direct equivalents)
- Conditions/Instructions → articy expression/script syntax

---

## Testing Strategy

For each serializer:
- [ ] Output format validation (JSON schema / XML schema)
- [ ] All 9 node types correctly mapped
- [ ] Expression transpilation integrated (conditions + instructions)
- [ ] Localization strings included per language
- [ ] Asset paths use engine conventions
- [ ] Round-trip: export → manual inspection of format correctness
- [ ] Edge cases: empty flows, flows with only entry/exit, deeply nested scenes
