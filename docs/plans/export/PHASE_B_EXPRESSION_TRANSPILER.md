# Phase 8B: Expression Transpiler

> **Parent document:** [PHASE_8_EXPORT.md](../PHASE_8_EXPORT.md)
>
> **Tasks:** 9-11 of 25
>
> **Last verified:** 2026-02-24 (against `condition.ex`, `instruction.ex`, expression editor JS, exported JSON format)

**Goal:** Build the expression transpiler that converts Storyarn's structured conditions and instructions into each game engine's scripting language.

**This is the hardest piece of the entire export system.** See [ARCHITECTURE.md](./ARCHITECTURE.md#expression-transpiler-critical-complexity) for full design rationale.

---

## Data Reality (verified against codebase)

### Condition node data (actual DB format)

```json
{
  "condition": {"logic": "all", "rules": [...]},
  "switch_mode": false
}
```

> **IMPORTANT:** There is NO `expression` field and NO separate `cases` field on condition nodes. The document previously showed both — they don't exist.
>
> - **Code mode** is a UI-only feature: the JS expression editor (`assets/js/expression_editor/`) converts between a DSL text representation and structured data in the browser. What gets saved to the DB is **always structured data**.
> - **Switch mode outputs** are derived dynamically from condition block/rule IDs (not from a separate `cases` array).

### Where conditions appear (all structured)

| Location | Storage | Format |
|----------|---------|--------|
| Condition node `data["condition"]` | JSONB map | `{logic, rules}` or `{logic, blocks}` |
| Dialogue response `condition` | JSON string within JSONB | Same format as above, but as a JSON-encoded string. Must `Jason.decode/1` before transpiling. |
| Scene pin `condition` | Ecto `:map` field | `{logic, rules}` or `{logic, blocks}` |
| Scene zone `condition` | Ecto `:map` field | `{logic, rules}` or `{logic, blocks}` |

### Legacy edge case

`Condition.parse/1` handles a `:legacy` case for plain-text strings that aren't valid JSON (pre-builder conditions). The transpiler should emit these as warnings, not attempt to parse them.

### Block types → operator sets (complete)

**Source of truth:** `lib/storyarn/flows/condition.ex`

| Block Type | Operators | Notes |
|------------|-----------|-------|
| `text` | equals, not_equals, contains, starts_with, ends_with, is_empty | |
| `rich_text` | equals, not_equals, contains, starts_with, ends_with, is_empty | Same as `text` |
| `number` | equals, not_equals, greater_than, greater_than_or_equal, less_than, less_than_or_equal | |
| `boolean` | is_true, is_false, is_nil | |
| `select` | equals, not_equals, is_nil | |
| `multi_select` | contains, not_contains, is_empty | |
| `date` | equals, not_equals, before, after | |
| `reference` | equals, not_equals, is_nil | Same as `select` |

**Source of truth:** `lib/storyarn/flows/instruction.ex`

| Block Type | Operators | Notes |
|------------|-----------|-------|
| `number` | set, add, subtract, set_if_unset | |
| `boolean` | set_true, set_false, toggle, set_if_unset | |
| `text` / `rich_text` | set, clear, set_if_unset | |
| `select` / `multi_select` | set, set_if_unset | |
| `date` | set, set_if_unset | |
| `reference` | set, set_if_unset | Same as `select` |

---

## Tasks

| Order  | Task                                                                 | Dependencies  | Testable Outcome                                  |
|--------|----------------------------------------------------------------------|---------------|---------------------------------------------------|
| 9      | Structured condition transpiler (builder-mode rules → target syntax) | None          | All operators transpile correctly for all engines |
| 10     | Structured assignment transpiler (builder-mode assignments → target) | None          | All assignment operators transpile correctly      |
| 11     | Legacy condition handler + condition helpers                          | None          | Legacy strings emit warnings, JSON strings decoded |

---

## Task 9: Structured Condition Transpiler

Create `Storyarn.Exports.ExpressionTranspiler` behaviour with 2 callbacks:
- `transpile_condition/2`
- `transpile_instruction/2`

Implement the **structured fast-path** for conditions:
- Iterate `rules[]` with operator lookup table → target syntax
- No parsing needed — direct map traversal
- Handle `all` (AND) and `any` (OR) logic combinators
- Handle both flat format (`{logic, rules}`) and block format (`{logic, blocks}`)
- Handle response-level conditions (dialogue node `responses[].condition` — stored as JSON strings, must decode first)
- Handle scene pin/zone conditions (stored as Ecto maps)

### Engine-specific emitters (6 targets)

| Engine   | Module                        | Variable Reference                  | AND        | OR         |
|----------|-------------------------------|-------------------------------------|------------|------------|
| **Ink**  | `ExpressionTranspiler.Ink`    | `mc_jaime_health` (dot→underscore)  | `and`      | `or`       |
| **Yarn** | `ExpressionTranspiler.Yarn`   | `$mc_jaime_health` ($ + underscore) | `and`      | `or`       |
| Unity    | `ExpressionTranspiler.Unity`  | `Variable["mc.jaime.health"]`       | `and`      | `or`       |
| Godot    | `ExpressionTranspiler.Godot`  | `mc_jaime_health` (dot→underscore)  | `and`      | `or`       |
| Unreal   | `ExpressionTranspiler.Unreal` | `mc.jaime.health` (dot preserved)   | `AND`      | `OR`       |
| articy   | `ExpressionTranspiler.Articy` | `mc.jaime.health` (dot preserved)   | `&&`       | `\|\|`     |

### Operator mapping table (conditions)

All 16 operators verified against `condition.ex`:

| Storyarn operator       | Ink          | Yarn       | Lua (Unity)  | GDScript (Godot)  | Unreal      | articy     |
|-------------------------|--------------|------------|--------------|-------------------|-------------|------------|
| `equals`                | `==`         | `==`       | `==`         | `==`              | `==`        | `==`       |
| `not_equals`            | `!=`         | `!=`       | `~=`         | `!=`              | `!=`        | `!=`       |
| `greater_than`          | `>`          | `>`        | `>`          | `>`               | `>`         | `>`        |
| `less_than`             | `<`          | `<`        | `<`          | `<`               | `<`         | `<`        |
| `greater_than_or_equal` | `>=`         | `>=`       | `>=`         | `>=`              | `>=`        | `>=`       |
| `less_than_or_equal`    | `<=`         | `<=`       | `<=`         | `<=`              | `<=`        | `<=`       |
| `contains` (text)       | warning      | custom fn  | custom fn    | `in`              | `Contains`  | custom     |
| `not_contains` (multi)  | warning      | custom fn  | custom fn    | `not in`          | `!Contains` | custom     |
| `starts_with` (text)    | warning      | custom fn  | custom fn    | `.begins_with()`  | custom fn   | custom     |
| `ends_with` (text)      | warning      | custom fn  | custom fn    | `.ends_with()`    | custom fn   | custom     |
| `is_empty` (text/multi) | `== ""`      | `== ""`    | `== ""`      | `== ""`           | `== ""`     | `== ""`    |
| `is_nil`                | warning      | `== null`  | `== nil`     | `== null`         | `== None`   | `== null`  |
| `is_true`               | truthy check | `== true`  | `== true`    | `== true`         | `== true`   | `== true`  |
| `is_false`              | `not var`    | `== false` | `== false`   | `== false`        | `== false`  | `== false` |
| `before` (date)         | warning      | `<`        | `<`          | `<`               | `<`         | `<`        |
| `after` (date)          | warning      | `>`        | `>`          | `>`               | `>`         | `>`        |

> **Block-format conditions:** The transpiler must handle BOTH flat format (`{logic, rules}`) AND block format (`{logic, blocks}`) — see [STORYARN_JSON_FORMAT.md](./STORYARN_JSON_FORMAT.md#condition-formats). Block format introduces `type: "block"` and `type: "group"` nesting (max 1 level).

## Task 10: Structured Assignment Transpiler

Implement the **structured fast-path** for assignments:
- Iterate `assignments[]` with operator lookup table → target syntax
- No parsing needed — direct map traversal

### Operator mapping table (assignments)

All 8 operators verified against `instruction.ex`. There is NO `multiply` operator.

| Storyarn operator  | Ink                    | Yarn                                            | Lua (Unity)                                            | GDScript (Godot)        | Unreal                  | articy                   |
|--------------------|------------------------|-------------------------------------------------|--------------------------------------------------------|-------------------------|-------------------------|--------------------------|
| `set`              | `~ x = val`            | `<<set $x to val>>`                             | `Variable["x"] = val`                                  | `x = val`               | `x = val`               | `x = val`                |
| `add`              | `~ x += val`           | `<<set $x to $x + val>>`                        | `Variable["x"] = Variable["x"] + val`                  | `x += val`              | `x += val`              | `x += val`               |
| `subtract`         | `~ x -= val`           | `<<set $x to $x - val>>`                        | `Variable["x"] = Variable["x"] - val`                  | `x -= val`              | `x -= val`              | `x -= val`               |
| `set_true`         | `~ x = true`           | `<<set $x to true>>`                            | `Variable["x"] = true`                                 | `x = true`              | `x = true`              | `x = true`               |
| `set_false`        | `~ x = false`          | `<<set $x to false>>`                           | `Variable["x"] = false`                                | `x = false`             | `x = false`             | `x = false`              |
| `toggle`           | `~ x = not x`          | `<<set $x to !$x>>`                             | `Variable["x"] = not Variable["x"]`                    | `x = !x`                | `x = !x`                | `x = !x`                 |
| `clear`            | `~ x = ""`             | `<<set $x to "">>`                              | `Variable["x"] = ""`                                   | `x = ""`                | `x = ""`                | `x = ""`                 |
| `set_if_unset`     | `{x == "": ~ x = val}` | `<<if $x == null>> <<set $x to val>> <<endif>>` | `if Variable["x"] == nil then Variable["x"] = val end` | `if x == null: x = val` | `if x == None: x = val` | `if (x == null) x = val` |

**Variable-to-variable assignments:** When `value_type == "variable_ref"`, the value is another variable reference (not a literal). All emitters must handle this — e.g., Lua: `Variable["x"] = Variable["y"]`, Ink: `~ x = y`.

## Task 11: Legacy Condition Handler + Helpers

> **Previously:** This task was "Code-mode parser (free-text → AST) + emitters." That was based on the incorrect assumption that condition nodes store an `expression` field with free-text DSL. They don't — the DB always stores structured data. Code mode is a UI-only feature (JS parser/serializer).

**Revised scope:**

1. **Condition decoder helper** — Normalize conditions from all storage formats:
   - Map (condition node, scene pins/zones) → pass through
   - JSON string (dialogue response conditions) → `Jason.decode/1` → map
   - Legacy plain string → return `{:legacy, string}` for warning emission
   - `nil` → skip

2. **Warning collection** — Report untranspilable patterns:
   - Legacy plain-text conditions
   - Unsupported operators for target engine (e.g., `contains` for Ink)
   - Unknown/empty operators

3. **Shared helpers** extracted for reuse across all 6 emitters:
   - `format_var_ref/2` — converts `{sheet, variable}` to engine-specific reference
   - `format_literal/2` — formats value with proper quoting/typing per engine
   - `join_with_logic/3` — joins transpiled parts with engine-specific AND/OR

---

## Implementation Notes

- Include raw Storyarn structured data as metadata/comment alongside transpiled output
- Validation: report untranspilable expressions/operators as export warnings (not silent failures)
- Handle response-level conditions (dialogue node `responses[].condition` — stored as JSON strings, must decode first)
- Handle scene pin/zone conditions (stored as Ecto maps)

## Testing Strategy

- All 16 condition operator types per engine (`equals`, `greater_than`, `contains`, `is_nil`, etc.)
- All 8 assignment operators per engine (`set`, `add`, `subtract`, `toggle`, `clear`, etc.)
- Logic combinators: `all` (AND) and `any` (OR) rule groups
- Block-format conditions: nested blocks and groups (max 1 level)
- Response-level conditions: JSON string → decode → transpile
- Scene pin/zone conditions: map → transpile
- Legacy plain-text conditions: emit warning, don't crash
- Variable-to-variable assignments: `value_type == "variable_ref"`
- Empty/nil conditions: graceful handling
- Expression transpiler integration: structured condition → Unity Lua → valid Lua syntax
