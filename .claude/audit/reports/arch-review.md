# Architecture Audit Report - Storyarn

**Date:** 2026-02-23
**Auditor:** Claude Opus 4.6 (Automated Architecture Audit)
**Stack:** Elixir 1.15+ / Phoenix 1.8 / LiveView 1.1 / PostgreSQL

---

## Overall Score: 78 / 100

**Justification:** The codebase demonstrates excellent use of the facade pattern with 70+ `defdelegate` entries, consistent shared utility usage, and proper authorization throughout. However, significant facade violations exist in the Evaluator subsystem and Localization context, several LiveView files exceed size limits, and 11 dependency cycles were detected.

---

## 1. CRITICAL Issues

### C1. Evaluator Subsystem Bypasses Flows Facade Entirely

The `Storyarn.Flows.Evaluator.*` namespace (Engine, State, Helpers, ConditionEval, InstructionExec) is accessed directly from 14+ web layer files. The `Storyarn.Flows` facade has zero delegations for any Evaluator module. This is the single most significant facade violation.

**Affected files:** `player_engine.ex`, `player_live.ex`, `debug_execution_handlers.ex`, `debug_session_handlers.ex`, `debug_panel.ex`, `exploration_live.ex`, and multiple debug tab components.

**Recommendation:** Add Evaluator delegations to `Storyarn.Flows` facade, or create a dedicated `Storyarn.Flows.Evaluator` public API module.

---

### C2. Localization Context Submodules Accessed Directly from Web Layer

Multiple internal Localization modules (`Languages`, `ExportImport`, `Reports`, `ProviderConfig`, `Providers.DeepL`, `LocalizedText`) are accessed directly from 8+ web layer files instead of through the `Storyarn.Localization` facade.

**Recommendation:** Add missing delegations to `Storyarn.Localization` facade.

---

## 2. Warnings

### W1. Cross-Context Submodule Access Between Domain Contexts

- Flows directly accesses `Sheets.ReferenceTracker`, `Sheets.Block`, `Sheets.Constraints.*`
- Sheets/Maps directly access `Flows.VariableReferenceTracker`
- Flows directly accesses `Localization.TextExtractor`
- Web layer accesses `Flows.NodeCrud`, `Flows.Condition`, `Flows.Instruction` directly

**Recommendation:** Route all cross-context calls through facades.

---

### W2. Oversized LiveView Files

| File                            | Lines  | Over Limit                             |
|---------------------------------|--------|----------------------------------------|
| `flow_live/show.ex`             | 1,166  | 866 (though it IS a proper dispatcher) |
| `map_live/show.ex`              | 986    | 686                                    |
| `element_handlers.ex`           | 1,147  | 847 (genuinely needs splitting)        |
| `undo_redo_handlers.ex` (map)   | 997    | 697                                    |
| `undo_redo_handlers.ex` (sheet) | 839    | 539                                    |

**Recommendation:** Split `element_handlers.ex` by entity type (zone, pin, annotation, connection). Consider extracting undo/redo into separate modules per operation type.

---

### W3. 11 Dependency Cycles Detected

Largest is 114 modules spanning the web layer (Phoenix compile-time chain). Most others are standard Ecto schema `belongs_to`/`has_many` patterns. One business logic cycle: `block_crud.ex` <-> `property_inheritance.ex`.

**Recommendation:** Break the `block_crud.ex` <-> `property_inheritance.ex` cycle by extracting shared logic.

---

## 3. Minor Recommendations

### R1. Duplicated Search Sanitizer

`assets.ex` duplicates `SearchHelpers.sanitize_like_query/1` as a private `sanitize_like_term/1` (line 317).

### R2. TimeHelpers Not Used Consistently

Three files use `DateTime.utc_now()` for timestamps where `TimeHelpers.now/0` would be appropriate:
- `node_delete.ex:69`
- `node_update.ex:107`
- `trash.ex:153`

### R3. Non-Standard Facade Path

Localization facade lives at `localization/localization.ex` instead of standard `localization.ex`.

### R4. Testing Gap in Maps Context

Maps context has only 1 test file vs Screenplays' 17 — significant testing gap.

---

## 4. Strengths

- **Facade pattern**: Excellently implemented with 70+ `defdelegate` entries in Flows alone, all with `@doc`/`@spec`
- **Shared utilities**: Consistently used across all contexts (TreeOperations, SearchHelpers, ShortcutHelpers, NameNormalizer, Validations)
- **Authorization**: 23 modules use Authorize; every mutating `handle_event` is wrapped with `with_authorization`
- **Schema consistency**: All hierarchical entities consistently implement the same field set and changeset pattern
- **Router**: Clean, well-organized, proper CSP, RESTful nesting
- **JS organization**: Clean hook/domain/utils separation with 40 flat hooks
- **XSS prevention**: All `raw()` usage properly sanitized
- **Zero browser dialogs**: No `window.confirm`/`alert`/`prompt` anywhere

---

## 5. Recommendations Summary

| Priority   | Issue                                    | Fix Effort   |
|------------|------------------------------------------|--------------|
| CRITICAL   | C1. Evaluator bypasses Flows facade      | Medium       |
| CRITICAL   | C2. Localization submodule direct access | Medium       |
| WARNING    | W1. Cross-context submodule access       | Medium       |
| WARNING    | W2. Oversized LiveView files             | High         |
| WARNING    | W3. Dependency cycles                    | Medium       |
| MINOR      | R1. Duplicated search sanitizer          | Low          |
| MINOR      | R2. Inconsistent TimeHelpers usage       | Low          |
| MINOR      | R3. Non-standard facade path             | Low          |
| MINOR      | R4. Maps testing gap                     | Medium       |
