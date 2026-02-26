# Audit Fix Plan — Export/Import System

## Context

Phase 8C Engine Serializers is complete (172 tests, all passing). A 5-agent audit scored the system B+ (81/100). This plan addresses all findings, critical issues first.

## Phase 1: Critical Security Fixes

- [ ] [P1-T1][manual] Fix CSV formula injection in `escape_csv_field/1`
  - File: `lib/storyarn/exports/serializers/helpers.ex:169-187`
  - Add formula prefix detection: if value starts with `=`, `+`, `-`, `@`, `\t`, `\r` → prepend `'`
  - Must happen BEFORE the comma/quote check
  - Add test in new `test/storyarn/exports/serializers/helpers_test.exs`

- [ ] [P1-T2][manual] Add explicit role check in export controller
  - File: `lib/storyarn_web/controllers/export_controller.ex:14`
  - Change `_membership` → `membership`, add check: any member can export (viewing is enough)
  - Pattern: `true <- ProjectMembership.can?(membership.role, :view_content)`
  - Return 403 on failure

- [ ] [P1-T3][manual] Guard `set_strategy` LiveView event
  - File: `lib/storyarn_web/live/export_import_live/index.ex:370`
  - Add guard: `when strategy in ~w(skip overwrite rename)`
  - Prevents `ArgumentError` crash from invalid atom conversion

## Phase 2: Validation Fix

- [ ] [P2-T1][manual] Remove phantom `:godot_dialogic` from valid formats
  - File: `lib/storyarn/exports/export_options.ex:44`
  - Remove `godot_dialogic` from `@valid_formats` list
  - No serializer exists for it — it would cause runtime errors

## Phase 3: Deduplication — Serializer Helpers

- [ ] [P3-T1][manual] Extract `transpile_or_default/4` into `Serializers.Helpers`
  - File: `lib/storyarn/exports/serializers/helpers.ex`
  - Add two public functions:
    ```elixir
    def transpile_or_empty(data, engine, type)  # returns "" on nil/empty/error
    def transpile_or_nil(data, engine, type)    # returns nil on nil/empty/error
    ```
  - Both delegate to `ExpressionTranspiler.transpile_condition/2` or `transpile_instruction/2`

- [ ] [P3-T2][manual] Remove private `transpile_or_*` from 4 serializers
  - `lib/storyarn/exports/serializers/unity_json.ex` — remove `transpile_or_empty` (lines 235-250), call `Helpers.transpile_or_empty/3`
  - `lib/storyarn/exports/serializers/godot_json.ex` — remove `transpile_or_nil` (lines 193-208), call `Helpers.transpile_or_nil/3`
  - `lib/storyarn/exports/serializers/unreal_csv.ex` — remove `transpile_or_empty` (lines 366-381), call `Helpers.transpile_or_empty/3`
  - `lib/storyarn/exports/serializers/articy_xml.ex` — remove both (lines 370-394), call `Helpers.transpile_or_nil/3` and `Helpers.transpile_or_empty/3`

- [ ] [P3-T3][manual] Replace Validator's `strip_html` with Helpers version
  - File: `lib/storyarn/exports/validator.ex:562-566`
  - Remove private `strip_html/1`, alias `Serializers.Helpers` and call `Helpers.strip_html/1`

## Phase 4: Deduplication — Transpiler Emitters

- [ ] [P4-T1][manual] Add default `condition_op/1` to `ExpressionTranspiler.Base`
  - File: `lib/storyarn/exports/expression_transpiler/base.ex`
  - Add inside `quote do` block (after the instruction section):
    ```elixir
    defp condition_op("equals"), do: "=="
    defp condition_op("not_equals"), do: "!="
    defp condition_op("greater_than"), do: ">"
    defp condition_op("less_than"), do: "<"
    defp condition_op("greater_than_or_equal"), do: ">="
    defp condition_op("less_than_or_equal"), do: "<="
    defp condition_op(op), do: op

    defoverridable condition_op: 1
    ```

- [ ] [P4-T2][manual] Remove `condition_op/1` from 5 emitters that use standard mapping
  - Remove from: `ink.ex`, `yarn.ex`, `godot.ex`, `unreal.ex`, `articy.ex`
  - Keep in `unity.ex` (overrides `not_equals` → `"~="`)

- [ ] [P4-T3][manual] Add default `emit_assignment/3` to `ExpressionTranspiler.Base`
  - File: `lib/storyarn/exports/expression_transpiler/base.ex`
  - Add standard assignment pattern (shared by godot/unreal/articy):
    ```elixir
    defp emit_assignment(ref, "set", a), do: "#{ref} = #{format_value(ref, a)}"
    defp emit_assignment(ref, "add", a), do: "#{ref} += #{format_value(ref, a)}"
    defp emit_assignment(ref, "subtract", a), do: "#{ref} -= #{format_value(ref, a)}"
    defp emit_assignment(ref, "set_true", _), do: "#{ref} = true"
    defp emit_assignment(ref, "set_false", _), do: "#{ref} = false"
    defp emit_assignment(ref, "toggle", _), do: "#{ref} = !#{ref}"
    defp emit_assignment(ref, "clear", _), do: ~s(#{ref} = "")
    defp emit_assignment(ref, _op, a), do: "#{ref} = #{format_value(ref, a)}"

    defoverridable emit_assignment: 3
    ```
  - Note: `set_if_unset` differs per engine (null keyword + syntax), so emitters that need it override `emit_assignment/3`

- [ ] [P4-T4][manual] Simplify 3 emitters to only override `set_if_unset`
  - `godot.ex`: Remove all `emit_assignment` clauses except `set_if_unset` (uses `if ref == null: ref = val`)
  - `unreal.ex`: Same, keeps `set_if_unset` (uses `if ref == None: ref = val`)
  - `articy.ex`: Same, keeps `set_if_unset` (uses `if (ref == null) ref = val`)
  - Ink, Yarn, Unity already have fully custom `emit_assignment` — leave as-is

## Phase 5: Verification

- [ ] [P5-T1][manual] Full verification
  - `mix compile --warnings-as-errors`
  - `mix format --check-formatted`
  - `mix credo --strict`
  - `mix test test/storyarn/exports/` — all 424+ export tests pass
  - `mix test` — full suite, no regressions

## File Summary

| File | Action | Phase |
|------|--------|-------|
| `lib/storyarn/exports/serializers/helpers.ex` | MODIFY — add formula sanitization + transpile helpers | P1, P3 |
| `lib/storyarn_web/controllers/export_controller.ex` | MODIFY — add role check | P1 |
| `lib/storyarn_web/live/export_import_live/index.ex` | MODIFY — add guard | P1 |
| `lib/storyarn/exports/export_options.ex` | MODIFY — remove godot_dialogic | P2 |
| `lib/storyarn/exports/serializers/unity_json.ex` | MODIFY — remove private transpile | P3 |
| `lib/storyarn/exports/serializers/godot_json.ex` | MODIFY — remove private transpile | P3 |
| `lib/storyarn/exports/serializers/unreal_csv.ex` | MODIFY — remove private transpile | P3 |
| `lib/storyarn/exports/serializers/articy_xml.ex` | MODIFY — remove private transpile | P3 |
| `lib/storyarn/exports/validator.ex` | MODIFY — use Helpers.strip_html | P3 |
| `lib/storyarn/exports/expression_transpiler/base.ex` | MODIFY — add defaults | P4 |
| `lib/storyarn/exports/expression_transpiler/emitters/ink.ex` | MODIFY — remove condition_op | P4 |
| `lib/storyarn/exports/expression_transpiler/emitters/yarn.ex` | MODIFY — remove condition_op | P4 |
| `lib/storyarn/exports/expression_transpiler/emitters/godot.ex` | MODIFY — remove condition_op + simplify emit_assignment | P4 |
| `lib/storyarn/exports/expression_transpiler/emitters/unreal.ex` | MODIFY — remove condition_op + simplify emit_assignment | P4 |
| `lib/storyarn/exports/expression_transpiler/emitters/articy.ex` | MODIFY — remove condition_op + simplify emit_assignment | P4 |
| `test/storyarn/exports/serializers/helpers_test.exs` | CREATE — formula injection + strip_html tests | P1 |
