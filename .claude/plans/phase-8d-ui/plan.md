# Phase 8D: Export/Import UI Enhancement

## Context

Phase A backend is complete (73 tests). Basic UI exists with storyarn-only export + full import flow.
All 7 serializers are implemented and registered. ExportOptions struct supports all fields.
The UI needs to expose the full feature set.

## Scope

**In scope (Tier 1 — core functionality):**
1. Format selection UI (radio buttons for all 7 formats)
2. Content section checkboxes with entity counts
3. Asset mode selector
4. Options (validate before export, pretty print)
5. Multi-format download controller (generalize ExportController)
6. Focus layout sidebar tool entry for export/import
7. Dynamic download link based on selected format

**Deferred (not in this plan):**
- Async export with progress bar (needs Inngest — Phase E)
- Articy XML import parser (separate task)
- Bundled ZIP export (complex, Phase E)
- Language selector (requires Localization context queries in mount)

## Tasks

### Task 1: Generalize ExportController for all formats
- [x] Replace single `storyarn/2` action with generic `export/2` that reads format from params
- [x] Handle single-file formats (binary output) and multi-file formats (list of `{filename, content}`)
- [x] For multi-file: concatenate with separator or return first file (main content)
- [x] Update router: single parameterized route `GET .../export/:format`

### Task 2: Add format selection to LiveView
- [x] Add `:selected_format` assign (default `:storyarn`)
- [x] Build format list from SerializerRegistry metadata (label, supported_sections)
- [x] Add `"set_format"` event handler
- [x] Dynamic download link that changes href based on selected format
- [x] Show supported sections per format (dimmed/disabled checkboxes for unsupported ones)

### Task 3: Add content section checkboxes
- [x] Load entity counts on mount via `Exports.count_entities/2`
- [x] Add `:include_*` assigns (sheets, flows, scenes, screenplays, localization)
- [x] Add `"toggle_section"` event handler
- [x] Render checkboxes with entity counts
- [x] Disable checkboxes for sections not supported by selected format

### Task 4: Add asset mode and options selectors
- [x] Add `:asset_mode` assign (`:references` default)
- [x] Add `:validate_before_export` and `:pretty_print` assigns
- [x] Add event handlers: `"set_asset_mode"`, `"toggle_option"`
- [x] Render radio buttons for asset mode, checkboxes for options

### Task 5: Wire options to export and validation
- [x] Build `ExportOptions` from assigns when validating
- [x] Pass options via query params in download link (format, sections, asset_mode, etc.)
- [x] Update ExportController to read options from query params

### Task 6: Add export/import to focus layout tool switcher
- [x] Add `%{key: :export_import, icon: "package", section: "export-import"}` to @tools
- [x] Add `tool_label(:export_import)` and `tool_path` clauses

### Task 7: Compile + verify
- [x] `mix compile --warnings-as-errors`
- [x] `mix test test/storyarn/exports/` — existing 73 tests still pass
- [x] Manual verification plan
