# Phase 8C: Engine Serializers

> **Feature:** Export serializers for 6 game engine formats
> **Spec:** `docs/plans/export/PHASE_C_ENGINE_SERIALIZERS.md`
> **Architecture:** `docs/plans/export/ARCHITECTURE.md`
> **Reference impl:** `lib/storyarn/exports/serializers/storyarn_json.ex`

## Context

Phase A (Foundation) and Phase B (Expression Transpiler) are complete. The transpiler
converts structured conditions/instructions to all 6 engine syntaxes. This phase adds
the serializers that produce complete engine-specific export files.

**Key insight:** Ink and Yarn are **linear text formats** requiring graph→text conversion.
Unity, Godot, Unreal, and articy preserve the **graph structure** in JSON/CSV/XML.

## Phase 1: Shared Serializer Infrastructure

- [x] [P1-T1][manual] Create `Exports.Serializers.Helpers` — shared utilities for all engine serializers
- [x] [P1-T2][manual] Create `Exports.Serializers.GraphTraversal` — linearizes flow graph for text formats
- [x] [P1-T3][manual] Update `SerializerRegistry` — add all 6 new engine formats

## Phase 2: Ink Serializer (Task 12)

- [x] [P2-T1][manual] Create `Exports.Serializers.Ink` — main Ink serializer
- [x] [P2-T2][manual] Create `test/storyarn/exports/serializers/ink_test.exs` — 28 tests

## Phase 3: Yarn Serializer (Task 13)

- [x] [P3-T1][manual] Create `Exports.Serializers.Yarn` — main Yarn serializer
- [x] [P3-T2][manual] Create `test/storyarn/exports/serializers/yarn_test.exs` — 22 tests

## Phase 4: Unity JSON Serializer (Task 14)

- [x] [P4-T1][manual] Create `Exports.Serializers.UnityJSON` — Dialogue System for Unity format
- [x] [P4-T2][manual] Create `test/storyarn/exports/serializers/unity_json_test.exs` — 23 tests

## Phase 5: Godot JSON Serializer (Task 15)

- [x] [P5-T1][manual] Create `Exports.Serializers.GodotJSON` — generic Godot JSON
- [x] [P5-T2][manual] Create `test/storyarn/exports/serializers/godot_json_test.exs` — 25 tests

## Phase 6: Unreal CSV Serializer (Task 16)

- [x] [P6-T1][manual] Create `Exports.Serializers.UnrealCSV` — Unreal DataTable export
- [x] [P6-T2][manual] Create `test/storyarn/exports/serializers/unreal_csv_test.exs` — 30 tests

## Phase 7: articy XML Serializer (Task 17)

- [x] [P7-T1][manual] Create `Exports.Serializers.ArticyXML` — articy:draft compatible XML
- [x] [P7-T2][manual] Create `test/storyarn/exports/serializers/articy_xml_test.exs` — 44 tests

## Phase 8: Integration Verification

- [x] [P8-T1][manual] Final verification — compile clean, 172 serializer tests pass, 424 export tests pass, 2956 full suite tests pass, 0 credo issues

## Key Design Decisions

1. **No Dialogic .dtl export** — Deferred. Too coupled to Godot-internal formats. Generic JSON covers Godot users.
2. **No localization CSVs in this phase** — Each serializer focuses on core structure. Localization export can be added per-format in a follow-up.
3. **No ZIP packaging** — Unreal returns `[{filename, content}]` tuple list like Ink/Yarn. ZIP packaging is a Phase D/E concern.
4. **HTML stripping in Helpers** — Simple regex approach (`Floki` parsing is overkill for stripping). Tags → text only.
5. **Graph traversal shared** — Ink and Yarn both need linear output. Unity/Godot/Unreal/articy keep graph structure.
6. **Sequential ID generation** — Unity and Unreal need integer/prefixed IDs. Generated during serialization, not stored.

## Scope Exclusions (Phase D/E)

- `serialize_to_file/4` streaming mode — all serializers return `{:error, :not_implemented}` (same as StoryarnJSON)
- Localization CSV/string table output per engine
- ZIP packaging for multi-file formats
- Progress callbacks
- Oban async export jobs

## File Summary

| File | Action | Purpose |
|------|--------|---------|
| `lib/storyarn/exports/serializers/helpers.ex` | CREATE | Shared utilities |
| `lib/storyarn/exports/serializers/graph_traversal.ex` | CREATE | Graph→linear conversion |
| `lib/storyarn/exports/serializers/ink.ex` | CREATE | Ink serializer |
| `lib/storyarn/exports/serializers/yarn.ex` | CREATE | Yarn serializer |
| `lib/storyarn/exports/serializers/unity_json.ex` | CREATE | Unity JSON serializer |
| `lib/storyarn/exports/serializers/godot_json.ex` | CREATE | Godot JSON serializer |
| `lib/storyarn/exports/serializers/unreal_csv.ex` | CREATE | Unreal CSV serializer |
| `lib/storyarn/exports/serializers/articy_xml.ex` | CREATE | articy XML serializer |
| `lib/storyarn/exports/serializer_registry.ex` | MODIFY | Add 6 formats |
| `test/storyarn/exports/serializers/ink_test.exs` | CREATE | Ink tests (28) |
| `test/storyarn/exports/serializers/yarn_test.exs` | CREATE | Yarn tests (22) |
| `test/storyarn/exports/serializers/unity_json_test.exs` | CREATE | Unity tests (23) |
| `test/storyarn/exports/serializers/godot_json_test.exs` | CREATE | Godot tests (25) |
| `test/storyarn/exports/serializers/unreal_csv_test.exs` | CREATE | Unreal tests (30) |
| `test/storyarn/exports/serializers/articy_xml_test.exs` | CREATE | articy tests (44) |
