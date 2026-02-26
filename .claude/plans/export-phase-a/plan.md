# Phase 8A: Export Foundation — Implementation Plan

> **Created:** 2026-02-24
> **Source:** `docs/plans/PHASE_8_EXPORT.md` → `docs/plans/export/PHASE_A_FOUNDATION.md`
> **Verified against:** Actual codebase schemas, facades, and seed data

## Pre-Implementation: Document Fixes

Before implementing, the plan documents have discrepancies that must be corrected.

### Discrepancies Found During Verification

- [x] **D1: Fix ARCHITECTURE.md DataCollector preload path** — changed `[nodes: :connections]` → `[:nodes, :connections]`
  - Doc says `preload: [nodes: :connections]`
  - Reality: `Flow` has `has_many :connections, FlowConnection`. `FlowNode` has `outgoing_connections` / `incoming_connections`.
  - Fix: Change to `preload: [:nodes, :connections]` (connections belong to Flow, not Node)

- [x] **D2: Fix STORYARN_JSON_FORMAT.md Asset section** — replaced `checksum` with `metadata` map
  - Doc shows `"checksum": "sha256:abc123..."` — this field does NOT exist in the DB
  - Asset has `metadata: :map` (with width/height/thumbnail_key/duration) — not in doc
  - Fix: Remove `checksum`, add `metadata` field to the asset export spec

- [x] **D3: Fix STORYARN_JSON_FORMAT.md Screenplay section** — added draft_label, draft_status, draft_of_id
  - Missing fields: `draft_label`, `draft_status`, `draft_of_id` (exist in DB, not in export spec)
  - These are "included from day one but not yet implemented" per schema docs
  - Fix: Add these fields for round-trip fidelity

- [x] **D4: Fix STORYARN_JSON_FORMAT.md Project section** — added settings field
  - Missing `settings` field (`:map, default: %{}` in DB)
  - Fix: Add `settings` to project export

---

## Phase 1: Exports Context + ExportOptions (Task 1)

- [x] **1.1: Create `lib/storyarn/exports.ex` facade** — facade with export_project/2, validate_project/2, count_entities/2, list_formats/0
- [x] **1.2: Create `lib/storyarn/exports/export_options.ex`** — struct with new/1 validation, handles atom+string keys
- [x] **1.3: Verify** — `mix compile --warnings-as-errors` ✓

## Phase 2: Serializer Behaviour + Registry (Task 2)

- [x] **2.1: Create `lib/storyarn/exports/serializer.ex` behaviour** — 6 callbacks, output type
- [x] **2.2: Create `lib/storyarn/exports/serializer_registry.ex`** — :storyarn registered, get/1, list/0, formats/0
- [x] **2.3: Verify** — `mix compile --warnings-as-errors` ✓

## Phase 3: Data Collector (Task 3)

- [x] **3.1: Create `lib/storyarn/exports/data_collector.ex`** — collect/2 + count_entities/2
- [x] **3.2: Implement sheet collection** — with blocks→table_columns/table_rows preload
- [x] **3.3: Implement flow collection** — [:nodes, :connections] preload, deleted_at filter on both
- [x] **3.4: Implement scene collection** — all sub-entities preloaded
- [x] **3.5: Implement screenplay collection** — with elements preload
- [x] **3.6: Implement localization collection** — languages + texts + glossary, respects language filter
- [x] **3.7: Implement asset collection** — includes metadata field
- [x] **3.8: Verify** — `mix compile --warnings-as-errors` ✓

## Phase 4: Storyarn JSON Serializer (Task 4)

- [x] **4.1: Create `lib/storyarn/exports/serializers/storyarn_json.ex`** — implements all 6 Serializer callbacks
- [x] **4.2: Implement project section serialization** — id, name, slug, description, settings
- [x] **4.3: Implement sheets section serialization** — sheet + blocks + table_data
- [x] **4.4: Implement flows section serialization** — flow + nodes + connections, dialogue instruction parsing
- [x] **4.5: Implement scenes section serialization** — all sub-entity fields serialized
- [x] **4.6: Implement screenplays section serialization** — with draft fields, elements with linked_node_id
- [x] **4.7: Implement localization section serialization** — grouped strings + aggregated glossary
- [x] **4.8: Implement assets section serialization** — references mode with metadata
- [x] **4.9: Implement metadata section** — statistics counts
- [x] **4.10: Implement top-level envelope** — storyarn_version, export_version, exported_at, Jason.encode
- [x] **4.11: Write tests for serializer** — 43 tests covering all sections, IDs, flags, selective export, pretty print, facade integration
- [x] **4.12: Verify** — `mix compile --warnings-as-errors` ✓ + 43 tests pass

## Phase 5: Import Parser (Task 5)

- [x] **5.1: Create `lib/storyarn/imports.ex` facade** — parse_file/1, preview/2, execute/3
- [x] **5.2: Create `lib/storyarn/imports/parsers/storyarn_json.ex`** — JSON parsing + structure validation
- [x] **5.3: Implement section parsers** — all sections via direct Repo.insert with changesets
- [x] **5.4: Implement ID mapping system** — {type, old_id} → new_id map, two-pass for parent_id, cross-ref remapping
- [x] **5.5: Implement import execution** — transaction wrapped, order: assets→sheets→flows→scenes→screenplays→localization
- [x] **5.6: Verify** — `mix compile --warnings-as-errors` ✓

## Phase 6: Round-Trip Test (Task 6)

- [x] **6.1: Create `test/storyarn/exports/round_trip_test.exs`** — 6 tests: structural comparison, entity counts, parse validation, preview. Used real node IDs for localization source_id.
- [x] **6.2: Build comparison helpers** — assert_sections_match + assert_entities_match, sorted by name
- [x] **6.3: Verify** — 49 tests pass (43 serializer + 6 round-trip) ✓

## Phase 7: Pre-Export Validation (Task 7)

- [x] **7.1: Create `lib/storyarn/exports/validator.ex`** — full implementation with 9 check functions, BFS reachability, cycle detection
- [x] **7.2: Implement validation rules** — 9 rules: missing_entry (error), orphan_nodes (warning), unreachable_nodes (warning), empty_dialogue (warning), missing_speakers (warning), circular_subflows (warning), broken_references (error: jump→hub, subflow→flow, scene→scene), missing_translations (warning), orphan_sheets (info). Skipped invalid_conditions/instructions as these are stored as structured data, not parseable expressions.
- [x] **7.3: Write validator tests** — 18 tests covering all rules + clean project + result structure
- [x] **7.4: Verify** — `mix compile --warnings-as-errors` ✓ + 18 tests pass ✓

## Phase 8: Import Preview + Conflict Detection (Task 8)

- [x] **8.1: Implement `Imports.preview/2`** — entity counts + conflict detection, already implemented in Phase 5
- [x] **8.2: Implement conflict detection** — shortcut-based comparison across Sheet, Flow, Scene, Screenplay
- [x] **8.3: Implement conflict resolution strategies** — :skip (don't create), :overwrite (soft-delete existing), :rename (append random suffix)
- [x] **8.4: Write import preview tests** — 12 tests: preview counts, conflicts, skip/rename/overwrite strategies, entity preservation
- [x] **8.5: Verify** — `mix compile --warnings-as-errors` ✓ + 79 total tests pass ✓

---

## Migration

- [x] **M1: Create export_jobs migration** — deferred to Phase E. Phase A is sync-only. No migration needed.

---

## File Structure (what will be created)

```
lib/storyarn/
├── exports.ex                              # Facade
├── exports/
│   ├── export_options.ex                   # Options struct + validation
│   ├── serializer.ex                       # Behaviour definition
│   ├── serializer_registry.ex              # Format → module map
│   ├── data_collector.ex                   # Dual-mode data loading
│   ├── validator.ex                        # Pre-export validation
│   └── serializers/
│       └── storyarn_json.ex                # Native JSON serializer
├── imports.ex                              # Facade
└── imports/
    └── parsers/
        └── storyarn_json.ex                # JSON parser + importer

test/storyarn/
├── exports/
│   ├── export_options_test.exs
│   ├── data_collector_test.exs
│   ├── serializers/
│   │   └── storyarn_json_test.exs
│   ├── validator_test.exs
│   └── round_trip_test.exs
└── imports/
    └── parsers/
        └── storyarn_json_test.exs
```

---

## Verification Checkpoints

After each phase: `mix compile --warnings-as-errors`
After phases with tests: `mix test test/storyarn/exports/ test/storyarn/imports/`
Final: `mix precommit` (format + credo + test)
