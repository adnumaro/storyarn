# Phase 8B: Expression Transpiler

> **Parent document:** [PHASE_8_EXPORT.md](../PHASE_8_EXPORT.md)
>
> **Tasks:** 9-11 of 25

**Goal:** Build the expression transpiler that converts Storyarn's structured conditions and instructions into each game engine's scripting language.

**This is the hardest piece of the entire export system.** See [ARCHITECTURE.md](./ARCHITECTURE.md#expression-transpiler-critical-complexity) for full design rationale.

---

## Tasks

| Order  | Task                                                                 | Dependencies  | Testable Outcome                                  |
|--------|----------------------------------------------------------------------|---------------|---------------------------------------------------|
| 9      | Structured condition transpiler (builder-mode rules → target syntax) | None          | All operators transpile correctly for all engines |
| 10     | Structured assignment transpiler (builder-mode assignments → target) | None          | All assignment operators transpile correctly      |
| 11     | Code-mode parser (free-text `{var} op val` → AST) + emitters         | None          | Fallback path for code-mode expressions           |

---

## Task 9: Structured Condition Transpiler

Create `Storyarn.Exports.ExpressionTranspiler` behaviour with 3 callbacks:
- `transpile_condition/2`
- `transpile_instruction/2`
- `transpile_code_expression/2`

Implement the **structured fast-path** for conditions:
- Iterate `rules[]` with operator lookup table → target syntax
- No parsing needed — direct map traversal
- Handle `all` (AND) and `any` (OR) logic combinators
- Handle response-level conditions (dialogue node `responses[].condition`)

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

**Source of truth:** `lib/storyarn/flows/condition.ex` — 6 type-specific operator sets.

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

**Source of truth:** `lib/storyarn/flows/instruction.ex` — 5 type-specific operator sets. There is NO `multiply` operator.

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

## Task 11: Code-Mode Parser (Fallback)

Create `ExpressionTranspiler.Parser` for free-text expressions:
- Parse `{mc.jaime.health} > 50` → `{:comparison, {:var_ref, "mc.jaime.health"}, :gt, {:literal, 50}}`
- Handle variable references in `{curly.brace.notation}`
- Handle boolean operators (`and`, `or`, `not`)
- Handle arithmetic operators (`+`, `-`, `*`, `/`)
- Handle parenthesized sub-expressions

Then per-engine AST → string emitters.

**This is only needed for the <10% of conditions authored in code mode.** The structured fast-path (Tasks 9-10) handles the majority.

---

## Implementation Notes

- Include raw Storyarn structured data as metadata/comment alongside transpiled output
- Validation: report untranspilable expressions/operators as export warnings (not silent failures)
- Handle response-level conditions (dialogue node `responses[].condition`) — same structured format

## Testing Strategy

- All operator types per engine (`equals`, `greater_than`, `contains`, `is_nil`, etc.)
- All assignment operators per engine (`set`, `add`, `subtract`, etc.)
- Logic combinators: `all` (AND) and `any` (OR) rule groups, nested groups
- Response-level conditions: dialogue response conditions transpile correctly
- Code-mode parser: free-text `{var} op value` → AST (edge cases, malformed input)
- Expression transpiler integration: structured condition → Unity Lua → valid Lua syntax
