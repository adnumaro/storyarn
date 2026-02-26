# Phase 8B: Expression Transpiler

> Feature: Expression transpiler — converts Storyarn structured conditions/instructions to 6 game engine syntaxes
> Spec: docs/plans/export/PHASE_B_EXPRESSION_TRANSPILER.md (verified 2026-02-24)

## Phase 1: Core Behaviour + Shared Helpers

- [x] [P1-T1] Create ExpressionTranspiler behaviour with `transpile_condition/2` and `transpile_instruction/2` callbacks, plus shared helpers module (`Helpers`) with `format_var_ref/3`, `format_literal/2`, `join_with_logic/3`, and `decode_condition/1` for normalizing all condition storage formats (map, JSON string, legacy string, nil)
- [x] [P1-T2] Create condition transpiler test scaffold — test module with shared test cases that exercise all 16 operators across all 6 engines using a data-driven approach (operator × engine matrix)
- [x] [P1-T3] Create assignment transpiler test scaffold — test module with shared test cases that exercise all 8 operators across all 6 engines, including variable-to-variable assignments

## Phase 2: Engine Emitters (Conditions)

- [x] [P2-T1] Implement Ink condition emitter — dot→underscore var refs, `and`/`or` logic, warnings for unsupported ops. Fixed guard clause issue (Map.keys not allowed in guards → classify_items pattern).
- [x] [P2-T2] Implement Yarn condition emitter — `$` prefix + underscore var refs, `and`/`or` logic, custom fn for string ops
- [x] [P2-T3] Implement Unity/Lua condition emitter — `Variable["dot.path"]` var refs, parenthesized `and`/`or`, `~=` for not_equals, Lua string ops
- [x] [P2-T4] Implement Godot/GDScript condition emitter — underscore var refs, `and`/`or`, `.begins_with()`/`.ends_with()`, `in`/`not in` for contains
- [x] [P2-T5] Implement Unreal condition emitter — dot-preserved var refs, `AND`/`OR`, `Contains`/`!Contains`/`StartsWith`/`EndsWith`, `None` for nil
- [x] [P2-T6] Implement articy condition emitter — dot-preserved var refs, `&&`/`||` logic, `contains`/`startsWith`/`endsWith` custom fns

## Phase 3: Engine Emitters (Assignments)

- [x] [P3-T1] All 6 emitters include `transpile_instruction/2` with all 8 operators + variable-to-variable refs. Implemented inline with each emitter during Phase 2.

## Phase 4: Block Format + Integration

- [x] [P4-T1] Block-format condition support — all 6 emitters handle `{logic, blocks}` via `Helpers.extract_condition_structure/1` with nested `type: "block"` and `type: "group"`. Added cross-engine block format tests.
- [x] [P4-T2] Integration helpers — `decode_condition/1` handles JSON strings, legacy plain-text (returns error tuple), nil. Registry `transpile_condition/3` routes by engine atom. All edge case tests pass.

## Verification

- [x] `mix compile --warnings-as-errors` — clean
- [x] `mix test test/storyarn/exports/expression_transpiler/` — 110 tests, 0 failures
- [x] `mix test` (full suite) — 2715 tests, 0 failures
