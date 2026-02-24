# Phase 8: Export & Import System

> **Goal:** Enable full project export/import for game engine integration and backup/migration
>
> **Priority:** High - Core feature for game development workflow
>
> **Dependencies:** Phase 7.5 (Sheets/Flows enhancements, Localization, World Builder)
>
> **Last Updated:** February 24, 2026
>
> **Strategy:** Indie-first. Middleware formats (Ink, Yarn) before engine-specific formats for maximum reach with minimum effort.

## Overview

This phase implements comprehensive export and import capabilities:
- Export to Storyarn JSON format (full fidelity, lossless round-trip)
- Export to narrative middleware formats (Ink, Yarn Spinner) — **highest ROI, reaches ~90% of devs**
- Export to game engine formats (Unity DSfU, Godot Dialogic, Godot JSON, Unreal DataTable)
- Export/Import articy:draft XML (competitor interoperability)
- Import from Storyarn JSON
- Pre-export validation and health checks
- Selective export (specific flows, sheets, scenes, locales)

**Design Philosophy:** Export should be lossless for Storyarn format and intelligently mapped for other formats. Middleware formats (Ink, Yarn) provide the best coverage-per-effort ratio. Validation catches issues before they become runtime bugs in the game.

---

## Documents

### Architecture & Formats

| Document                                                    | Contents                                                                                       |
|-------------------------------------------------------------|------------------------------------------------------------------------------------------------|
| [ARCHITECTURE.md](./export/ARCHITECTURE.md)                 | Serializer behaviour, registry, data collector, expression transpiler, architectural decisions |
| [STORYARN_JSON_FORMAT.md](./export/STORYARN_JSON_FORMAT.md) | Native JSON format spec — sheets, flows, scenes, screenplays, localization, assets, metadata   |
| [ENGINE_FORMATS.md](./export/ENGINE_FORMATS.md)             | Overview of all engine format mappings (summary)                                               |
| [RESEARCH_SYNTHESIS.md](./export/RESEARCH_SYNTHESIS.md)     | Market research — engine landscape, competitive analysis, priority rationale                   |

### Per-Format Plans

| Document                                      | Target                                                   | Priority   | Reach  |
|-----------------------------------------------|----------------------------------------------------------|------------|--------|
| [FORMAT_INK.md](./export/FORMAT_INK.md)       | Ink (.ink) — 13+ engine runtimes                         | **Tier 1** | ~90%   |
| [FORMAT_YARN.md](./export/FORMAT_YARN.md)     | Yarn Spinner (.yarn) — Unity, Godot, GameMaker, GDevelop | **Tier 1** | ~40%   |
| [FORMAT_UNITY.md](./export/FORMAT_UNITY.md)   | Unity Dialogue System for Unity (JSON)                   | Tier 2     | ~35%   |
| [FORMAT_GODOT.md](./export/FORMAT_GODOT.md)   | Godot (JSON + Dialogic .dtl + CSV localization)          | Tier 2     | ~15%   |
| [FORMAT_UNREAL.md](./export/FORMAT_UNREAL.md) | Unreal (DataTable CSV + JSON + StringTable)              | Tier 2     | ~15%   |
| [FORMAT_ARTICY.md](./export/FORMAT_ARTICY.md) | articy:draft XML (export + import)                       | Tier 3     | ~5%    |

### Implementation Phases

| Document                                                                      | Contents                                                                                               |
|-------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------|
| [PHASE_A_FOUNDATION.md](./export/PHASE_A_FOUNDATION.md)                       | Tasks 1-8: Export context, serializer behaviour, data collector, native round-trip, validation, import |
| [PHASE_B_EXPRESSION_TRANSPILER.md](./export/PHASE_B_EXPRESSION_TRANSPILER.md) | Tasks 9-11: Structured condition/assignment transpiler, code-mode parser                               |
| [PHASE_C_ENGINE_SERIALIZERS.md](./export/PHASE_C_ENGINE_SERIALIZERS.md)       | Tasks 12-17: Ink, Yarn, Unity, Godot, Unreal, articy serializers                                       |
| [PHASE_D_UI_UX.md](./export/PHASE_D_UI_UX.md)                                 | Tasks 18-21: Export modal, download, import UI, articy import parser                                   |
| [PHASE_E_SCALE_API.md](./export/PHASE_E_SCALE_API.md)                         | Tasks 22-25: Oban background processing, sync/async threshold, cleanup, REST API                       |

---

## Implementation Order (25 tasks across 5 phases)

**Principle:** Native JSON round-trip (export → import) must be lossless before touching any engine format. Middleware formats (Ink, Yarn) come before engine-specific because they reach more developers with less effort. Async with Oban is a performance optimization, not a blocker — it goes last.

### Phase A: Foundation + Native Round-Trip (Tasks 1-8)

| # | Task                                    | Testable Outcome                             |
|---|-----------------------------------------|----------------------------------------------|
| 1 | Export context + options schema         | ExportOptions struct validates correctly     |
| 2 | Serializer behaviour + registry         | Registry resolves format → module            |
| 3 | Data collector                          | Loads full project data in single pass       |
| 4 | Storyarn JSON serializer (all sections) | Full project exports to JSON                 |
| 5 | Import parser (Storyarn JSON)           | Can parse exported JSON back                 |
| 6 | Import round-trip test                  | **export → import = identical project data** |
| 7 | Pre-export validation                   | Catches broken refs, orphans, etc.           |
| 8 | Import preview + conflict detection     | Shows diff before executing import           |

### Phase B: Expression Transpiler (Tasks 9-11)

| #   | Task                                                                                   | Testable Outcome                                  |
|-----|----------------------------------------------------------------------------------------|---------------------------------------------------|
| 9   | Structured condition transpiler (6 emitters: Ink, Yarn, Lua, GDScript, Unreal, articy) | All operators transpile correctly for all targets |
| 10  | Structured assignment transpiler (6 emitters)                                          | All assignment operators transpile correctly      |
| 11  | Code-mode parser + emitters                                                            | Fallback path for code-mode expressions           |

### Phase C: Format Serializers (Tasks 12-17)

**Order: Middleware first (highest ROI), then engine-specific (indie-first), then interop.**

| #   | Task                                                               | Testable Outcome                               | Reach  |
|-----|--------------------------------------------------------------------|------------------------------------------------|--------|
| 12  | **Ink serializer** (.ink text + metadata JSON)                     | Compiles with inklecate, loads in Ink runtimes | ~90%   |
| 13  | **Yarn serializer** (.yarn text + string tables)                   | Loads in Yarn Spinner for Unity/Godot          | ~40%   |
| 14  | Unity serializer (DSfU JSON + Lua emitter)                         | Imports in Dialogue System for Unity           | ~35%   |
| 15  | Godot serializer (generic JSON + Dialogic .dtl + GDScript emitter) | Parseable in Godot, loads in Dialogic 2        | ~15%   |
| 16  | Unreal serializer (DataTable CSV + metadata JSON)                  | Importable as UDataTable                       | ~15%   |
| 17  | articy:draft XML serializer                                        | Valid articy:draft XML                         | ~5%    |

### Phase D: UI + UX (Tasks 18-21)

| #   | Task                                                   | Testable Outcome                         |
|-----|--------------------------------------------------------|------------------------------------------|
| 18  | Export UI (modal) — format selection, validation panel | All formats selectable, validation works |
| 19  | Export download                                        | Browser file download for all formats    |
| 20  | Import execution + UI                                  | Full import flow with conflicts          |
| 21  | Import from articy:draft                               | Can parse articy XML into Storyarn       |

### Phase E: Scale + API (Tasks 22-25)

| #   | Task                                 | Testable Outcome                          |
|-----|--------------------------------------|-------------------------------------------|
| 22  | Oban ExportWorker + queue config     | Background export with progress broadcast |
| 23  | Sync/async threshold decision logic  | Small projects sync, large projects async |
| 24  | Cleanup cron + retry with checkpoint | Old exports purged, crash recovery works  |
| 25  | REST API endpoints                   | Programmatic export/import access         |

---

## Effort-to-Reach Matrix

| Format                  | Effort         | Reach         | Ratio           | Phase   |
|-------------------------|----------------|---------------|-----------------|---------|
| Storyarn JSON           | Medium         | 100% (backup) | Prerequisite    | A       |
| **Ink (.ink)**          | **Medium**     | **~90%**      | **Best**        | **C**   |
| **Yarn (.yarn)**        | **Low-Medium** | **~40%**      | **Excellent**   | **C**   |
| Unity DSfU              | Medium         | ~35%          | Good            | C       |
| Godot (JSON + Dialogic) | Medium         | ~15%          | Good            | C       |
| Unreal DataTable        | Medium-High    | ~15%          | Fair            | C       |
| articy XML              | High           | ~5%           | Low (strategic) | C       |

**Key insight from research:** A single Ink export reaches 13+ engine runtimes (~90% of game developers), while three engine-specific exports (Unity + Godot + Unreal) reach ~84%. Ink has **3x better effort-to-reach ratio**.

---

## Dead Ends (Do NOT Support)

Research confirmed these engines are not worth targeting:

| Engine                     | Reason                              |
|----------------------------|-------------------------------------|
| REDengine (CD Projekt RED) | Abandoned — CDPR moving to UE5      |
| CryEngine                  | Negligible user base                |
| Infinity Engine            | Legacy (20+ years old)              |
| Frostbite (EA)             | Proprietary, studios fleeing to UE5 |
| Divinity Engine (Larian)   | Internal only                       |
| Source 2 (Valve)           | Not used for narrative games        |

**Supporting Unreal Engine covers the entire AAA market.** No other AAA engine is worth targeting.

---

## Success Criteria

- [ ] Export to Storyarn JSON preserves all data (lossless round-trip verified by test)
- [ ] Import from Storyarn JSON restores project exactly (diff = empty)
- [ ] Export to Ink produces files that compile with inklecate
- [ ] Export to Yarn produces files loadable by Yarn Spinner
- [ ] Export to Unity produces files loadable by Dialogue System for Unity
- [ ] Export to Godot produces files loadable by Dialogic 2
- [ ] Export to Godot JSON parseable by Godot's JSON class (no addon required)
- [ ] Export to Unreal produces valid DataTable CSVs importable as UDataTable
- [ ] Expression transpiler handles all condition/instruction patterns per target
- [ ] Untranspilable expressions reported as warnings (not silent failures)
- [ ] Pre-export validation catches common issues with entity-level links
- [ ] Large projects (1000+ nodes) export without timeout via Oban
- [ ] Import handles conflicts gracefully (skip/overwrite/merge)
- [ ] articy:draft XML interoperability works (import and export)
- [ ] Adding a new engine format requires only 1 new module + 1 registry line
- [ ] Localization export works for all formats (CSV, string tables, line tags)

---

*This phase depends on 7.5 enhancements (Sheets, Flows, Localization, Scenes) being complete for full export coverage.*
