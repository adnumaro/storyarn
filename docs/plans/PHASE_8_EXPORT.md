# Phase 8: Export & Import System

> **Goal:** Enable full project export/import for game engine integration and backup/migration
>
> **Priority:** High - Core feature for game development workflow
>
> **Dependencies:** Phase 7.5 (Sheets/Flows enhancements, Localization, World Builder)
>
> **Last Updated:** February 24, 2026

## Overview

This phase implements comprehensive export and import capabilities:
- Export to Storyarn JSON format (full fidelity)
- Export to game engine formats (Unity, Unreal, Godot)
- Export to articy:draft compatible format (interoperability)
- Import from Storyarn JSON
- Import from articy:draft XML
- Pre-export validation and health checks
- Selective export (specific flows, sheets, scenes, locales)

**Design Philosophy:** Export should be lossless for Storyarn format and intelligently mapped for other formats. Validation catches issues before they become runtime bugs in the game.

---

## Documents

| Document | Contents |
|----------|----------|
| [ARCHITECTURE.md](./export/ARCHITECTURE.md) | Serializer behaviour, registry, data collector, expression transpiler, architectural decisions |
| [STORYARN_JSON_FORMAT.md](./export/STORYARN_JSON_FORMAT.md) | Native JSON format spec — sheets, flows, scenes, screenplays, localization, assets, metadata |
| [ENGINE_FORMATS.md](./export/ENGINE_FORMATS.md) | Unity (Dialogue System), Godot (Dialogic 2), Unreal (DataTable CSV), articy:draft XML |
| [PHASE_A_FOUNDATION.md](./export/PHASE_A_FOUNDATION.md) | Tasks 1-8: Export context, serializer behaviour, data collector, native round-trip, validation, import |
| [PHASE_B_EXPRESSION_TRANSPILER.md](./export/PHASE_B_EXPRESSION_TRANSPILER.md) | Tasks 9-11: Structured condition/assignment transpiler, code-mode parser |
| [PHASE_C_ENGINE_SERIALIZERS.md](./export/PHASE_C_ENGINE_SERIALIZERS.md) | Tasks 12-15: Unity, Godot, Unreal, articy serializer implementations |
| [PHASE_D_UI_UX.md](./export/PHASE_D_UI_UX.md) | Tasks 16-19: Export modal, download, import UI, articy import parser |
| [PHASE_E_SCALE_API.md](./export/PHASE_E_SCALE_API.md) | Tasks 20-23: Oban background processing, sync/async threshold, cleanup, REST API |

---

## Implementation Order (23 tasks across 5 phases)

**Principle:** Native JSON round-trip (export → import) must be lossless before touching any engine format. Async with Oban is a performance optimization, not a blocker — it goes last.

### Phase A: Foundation + Native Round-Trip (Tasks 1-8)

| # | Task | Testable Outcome |
|---|------|------------------|
| 1 | Export context + options schema | ExportOptions struct validates correctly |
| 2 | Serializer behaviour + registry | Registry resolves format → module |
| 3 | Data collector | Loads full project data in single pass |
| 4 | Storyarn JSON serializer (all sections) | Full project exports to JSON |
| 5 | Import parser (Storyarn JSON) | Can parse exported JSON back |
| 6 | Import round-trip test | **export → import = identical project data** |
| 7 | Pre-export validation | Catches broken refs, orphans, etc. |
| 8 | Import preview + conflict detection | Shows diff before executing import |

### Phase B: Expression Transpiler (Tasks 9-11)

| # | Task | Testable Outcome |
|---|------|------------------|
| 9 | Structured condition transpiler | All operators transpile correctly for all engines |
| 10 | Structured assignment transpiler | All assignment operators transpile correctly |
| 11 | Code-mode parser + emitters | Fallback path for code-mode expressions |

### Phase C: Engine Serializers (Tasks 12-15)

| # | Task | Testable Outcome |
|---|------|------------------|
| 12 | Unity serializer + Lua emitter | Dialogue System for Unity compatible JSON |
| 13 | Godot serializer + GDScript emitter | Dialogic 2 compatible JSON |
| 14 | Unreal serializer + CSV emitter | DataTable CSVs + metadata JSON |
| 15 | articy:draft XML serializer | Valid articy:draft XML |

### Phase D: UI + UX (Tasks 16-19)

| # | Task | Testable Outcome |
|---|------|------------------|
| 16 | Export UI (modal) | Format selection, validation panel |
| 17 | Export download | Browser file download works |
| 18 | Import execution + UI | Full import flow with conflicts |
| 19 | Import from articy:draft | Can parse articy XML |

### Phase E: Scale + API (Tasks 20-23)

| # | Task | Testable Outcome |
|---|------|------------------|
| 20 | Oban ExportWorker + queue config | Background export with progress broadcast |
| 21 | Sync/async threshold decision logic | Small projects sync, large projects async |
| 22 | Cleanup cron + retry with checkpoint | Old exports purged, crash recovery works |
| 23 | REST API endpoints | Programmatic export/import access |

---

## Success Criteria

- [ ] Export to Storyarn JSON preserves all data (lossless round-trip verified by test)
- [ ] Import from Storyarn JSON restores project exactly (diff = empty)
- [ ] Export to Unity produces files loadable by Dialogue System for Unity
- [ ] Export to Godot produces files loadable by Dialogic 2
- [ ] Export to Unreal produces valid DataTable CSVs importable as UDataTable
- [ ] Expression transpiler handles all condition/instruction patterns per engine
- [ ] Untranspilable expressions reported as warnings (not silent failures)
- [ ] Pre-export validation catches common issues with entity-level links
- [ ] Large projects (1000+ nodes) export without timeout via Oban
- [ ] Import handles conflicts gracefully (skip/overwrite/merge)
- [ ] articy:draft XML interoperability works (import and export)
- [ ] Adding a new engine format requires only 1 new module + 1 registry line

---

*This phase depends on 7.5 enhancements (Sheets, Flows, Localization, Scenes) being complete for full export coverage.*
