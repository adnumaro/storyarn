# Phase 8D: UI & UX

> **Parent document:** [PHASE_8_EXPORT.md](../PHASE_8_EXPORT.md)
>
> **Tasks:** 18-21 of 25
>
> **Dependencies:** Phase A (Tasks 4, 6, 7, 8)

**Goal:** Build the LiveView UI for export and import workflows.

---

## Tasks

| Order  | Task                     | Dependencies  | Testable Outcome                   |
|--------|--------------------------|---------------|------------------------------------|
| 18     | Export UI (modal)        | Tasks 4, 7    | Format selection, validation panel |
| 19     | Export download          | Task 18       | Browser file download works        |
| 20     | Import execution + UI    | Tasks 6, 8    | Full import flow with conflicts    |
| 21     | Import from articy:draft | None          | Can parse articy XML               |

---

## Task 18: Export Modal

**LiveView:** `ExportLive.Index`

```
+-----------------------------------------------------------------------------+
| EXPORT PROJECT                                                    [x Close] |
+-----------------------------------------------------------------------------+
|                                                                             |
| Format                                                                      |
| +-------------------------------------------------------------------------+ |
| | * Storyarn JSON (full backup, recommended)                              | |
| | o Ink (.ink) — 13+ engine runtimes                                      | |
| | o Yarn Spinner (.yarn) — Unity, Godot, GameMaker                       | |
| | o Unity (Dialogue System for Unity JSON)                                | |
| | o Godot (generic JSON + Dialogic .dtl)                                  | |
| | o Unreal (DataTable CSV)                                                | |
| | o articy:draft XML (interoperability)                                   | |
| +-------------------------------------------------------------------------+ |
|                                                                             |
| Content                                                                     |
| [x] Sheets (145 sheets, 423 blocks)                                        |
| [x] Flows (32 flows, 856 nodes)                                            |
| [x] Scenes (5 scenes, 89 pins)                                             |
| [x] Screenplays (8 screenplays, 320 elements)                              |
| [x] Localization (3 languages)                                             |
|                                                                             |
| Languages (for localization export)                                         |
| [x] English (source)    [x] Spanish (93%)    [x] German (84%)             |
|                                                                             |
| Assets                                                                      |
| * References only (URLs in JSON)                                            |
| o Embedded (Base64 in JSON - larger file)                                   |
| o Bundled (ZIP with assets folder)                                          |
|                                                                             |
| Options                                                                     |
| [x] Validate before export                                                 |
| [x] Pretty print JSON                                                      |
|                                                                             |
+-----------------------------------------------------------------------------+
| VALIDATION                                              [Run Validation]    |
| +-------------------------------------------------------------------------+ |
| | Passed with 3 warnings                                                  | |
| |                                                                         | |
| | ! 2 orphan sheets with no references                                    | |
| | ! 1 dialogue node without speaker                                       | |
| | ! 5 untranslated strings in German                                      | |
| |                                                                         | |
| | [View Details]                                                          | |
| +-------------------------------------------------------------------------+ |
|                                                                             |
|                                            [Cancel] [Export to JSON]        |
+-----------------------------------------------------------------------------+
```

Implementation:
- Format selector with descriptions
- Content checkboxes with counts
- Language selector (multi-select)
- Asset mode selector
- Validation panel with results
- Real-time progress bar (PubSub subscription for async exports)
- Cancel button for in-progress async exports

## Task 19: Export Download

- Download trigger (browser download for sync, download link for async)
- Content-Disposition header with meaningful filename
- File size display before download

## Task 20: Import Execution + UI

**LiveView:** Import modal within project settings or dedicated route.

```
+-----------------------------------------------------------------------------+
| IMPORT PROJECT                                                    [x Close] |
+-----------------------------------------------------------------------------+
|                                                                             |
| File                                                                        |
| +-------------------------------------------------------------------------+ |
| | my-project-backup.json                      [Choose Different File]     | |
| | Format: Storyarn JSON v1.0.0                                            | |
| | Exported: Feb 1, 2026 at 3:30 PM                                       | |
| +-------------------------------------------------------------------------+ |
|                                                                             |
| Preview                                                                     |
| +-------------------------------------------------------------------------+ |
| | Sheets: 145 (12 new, 133 existing)                                      | |
| | Flows: 32 (5 new, 27 existing)                                          | |
| | Scenes: 5 (0 new, 5 existing)                                           | |
| | Screenplays: 8 (1 new, 7 existing)                                      | |
| | Languages: 3 (0 new)                                                    | |
| | Assets: 89 (15 new, 74 existing)                                        | |
| +-------------------------------------------------------------------------+ |
|                                                                             |
| Conflict Resolution                                                         |
| When an entity already exists:                                              |
| o Skip (keep existing)                                                      |
| * Overwrite (replace with imported)                                         |
| o Merge (combine, keep newer timestamps)                                    |
|                                                                             |
| ! 27 flows will be overwritten                                              |
| ! 133 sheets will be overwritten                                            |
|                                                                             |
|                                            [Cancel] [Import 292 entities]   |
+-----------------------------------------------------------------------------+
```

Implementation:
- File upload and parsing
- Preview generation
- Conflict detection display
- Conflict resolution options (skip, overwrite, merge)
- Transaction wrapper for atomic import
- Import report generation
- Error handling for malformed files

## Task 21: Import from articy:draft

- Parser module: `Imports.Parsers.ArticyXML`
- Parse articy:draft XML format
- Map articy entities → Storyarn sheets
- Map articy FlowFragments → Storyarn flows
- Map articy GlobalVariables → Storyarn sheet blocks
- Handle GUID → UUID conversion

---

## Testing Strategy

### E2E Tests
- [ ] Export modal workflow (format selection, validation, download)
- [ ] Import with conflicts (skip, overwrite, merge)
- [ ] Download verification (file size, content type, filename)
