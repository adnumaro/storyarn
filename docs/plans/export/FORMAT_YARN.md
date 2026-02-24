# Export Format: Yarn Spinner (.yarn)

> **Parent document:** [PHASE_8_EXPORT.md](../PHASE_8_EXPORT.md) | [RESEARCH_SYNTHESIS.md](./RESEARCH_SYNTHESIS.md)
>
> **Priority:** Second highest ROI — covers Unity, Godot, GameMaker, GDevelop
>
> **Serializer module:** `Storyarn.Exports.Serializers.Yarn`
>
> **Expression emitter:** `Storyarn.Exports.ExpressionTranspiler.Yarn`

---

## Why Yarn Second

| Metric                | Value                                                   |
|-----------------------|---------------------------------------------------------|
| GitHub stars          | 2,700+                                                  |
| Official runtimes     | Unity (stable), Godot (beta), upcoming Unreal           |
| Community runtimes    | GameMaker (Chatterbox), GDevelop (bondage.js), web (JS) |
| Notable games         | Night in the Woods, A Short Hike, Dredge                |
| Developer reach       | ~40% of active game developers                          |
| Implementation effort | Low-Medium (format is simpler than Ink)                 |

Yarn Spinner is the **second most widely adopted** narrative scripting format. It has a strong position in Unity and is growing in Godot. Combined with Ink, these two formats cover ~95% of the market.

**Key advantage over Ink:** Built-in localization support via line tags.

---

## Output

**Primary:** `.yarn` text file(s)
**Localization:** `.csv` string table (Yarn's native localization format)
**Metadata:** Optional companion JSON for character/entity data

### File Organization

Two options:
1. **Single file:** All flows in one `.yarn` file (simpler, good for small projects)
2. **Multi-file:** One `.yarn` file per flow (better for large projects, version control)

Default to multi-file for projects with >5 flows, single file otherwise.

---

## Storyarn → Yarn Mapping

### Structural Mapping

| Storyarn Concept   | Yarn Equivalent                                    | Notes                                      |
|--------------------|----------------------------------------------------|--------------------------------------------|
| Flow               | Yarn node(s)                                       | Each flow becomes one or more titled nodes |
| Entry node         | First content in node                              | Implicit start                             |
| Exit node          | `===` (node end)                                   | Yarn nodes end with `===`                  |
| Dialogue node      | `Character: Dialogue text`                         | Convention using character names           |
| Dialogue responses | `-> Option text`                                   | Options with `->` prefix                   |
| Condition node     | `<<if>>` / `<<elseif>>` / `<<else>>` / `<<endif>>` | Block-scoped conditionals                  |
| Instruction node   | `<<set $variable to value>>`                       | Variable operations                        |
| Hub node           | Node title (jump target)                           | `title: hub_name` in header                |
| Jump node          | `<<jump NodeTitle>>`                               | Explicit jump command                      |
| Subflow node       | `<<jump SubflowNode>>`                             | No tunnel/return in Yarn v2                |
| Scene node         | `<<command scene_info>>`                           | Custom command for game engine             |
| Variables          | `$variable` declarations                           | `<<declare $variable = value>>`            |

### Variable Mapping

Yarn uses `$` prefix for variables. Dots are allowed in Yarn variable names, so Storyarn's notation maps more directly than Ink:

| Storyarn          | Yarn               |
|-------------------|--------------------|
| `mc.jaime.health` | `$mc_jaime_health` |
| `flags.met_jaime` | `$flags_met_jaime` |
| `inventory.gold`  | `$inventory_gold`  |

Note: While Yarn technically allows dots, underscores are the community convention and avoid potential issues with some runtimes.

### Expression Transpilation

**Conditions:**

| Storyarn Operator       | Yarn Syntax                 | Notes                                |
|-------------------------|-----------------------------|--------------------------------------|
| `equals`                | `==`                        |                                      |
| `not_equals`            | `!=`                        |                                      |
| `greater_than`          | `>`                         |                                      |
| `less_than`             | `<`                         |                                      |
| `greater_than_or_equal` | `>=`                        |                                      |
| `less_than_or_equal`    | `<=`                        |                                      |
| `is_true`               | `$variable == true`         |                                      |
| `is_false`              | `$variable == false`        |                                      |
| `is_nil`                | `$variable == null`         | Yarn v2.5+ supports null             |
| `is_empty` (text/multi) | `$variable == ""`           |                                      |
| `contains` (text)       | Custom function call        | `<<if contains($var, "val")>>`       |
| `not_contains` (multi)  | Custom function call        | `<<if !contains($var, "val")>>`      |
| `starts_with` (text)    | Custom function call        | `<<if starts_with($var, "val")>>`    |
| `ends_with` (text)      | Custom function call        | `<<if ends_with($var, "val")>>`      |
| `before` (date)         | `<`                         | Dates compared as strings/timestamps |
| `after` (date)          | `>`                         | Dates compared as strings/timestamps |
| `all` (AND)             | `condition1 and condition2` |                                      |
| `any` (OR)              | `condition1 or condition2`  |                                      |

> **Block-format conditions:** The transpiler must handle BOTH flat format (`{logic, rules}`) AND block format (`{logic, blocks}` with `type: "block"` and `type: "group"` nesting, max 1 level). See [STORYARN_JSON_FORMAT.md](./STORYARN_JSON_FORMAT.md#condition-formats).

**Assignments:**

| Storyarn Operator   | Yarn Syntax                                                     | Notes       |
|---------------------|-----------------------------------------------------------------|-------------|
| `set`               | `<<set $variable to value>>`                                    |             |
| `add`               | `<<set $variable to $variable + value>>`                        |             |
| `subtract`          | `<<set $variable to $variable - value>>`                        |             |
| `set_true`          | `<<set $variable to true>>`                                     |             |
| `set_false`         | `<<set $variable to false>>`                                    |             |
| `toggle`            | `<<set $variable to !$variable>>`                               | Yarn v2.5+  |
| `clear`             | `<<set $variable to "">>`                                       |             |
| `set_if_unset`      | `<<if $variable == null>> <<set $variable to value>> <<endif>>` | Conditional |

> **NO `multiply` operator.** Storyarn does not have a multiply operator. Source of truth: `lib/storyarn/flows/instruction.ex`
>
> **Variable-to-variable assignments:** When `value_type == "variable_ref"`, the value is another variable reference. Yarn: `<<set $x to $y>>`.

---

## Yarn File Format

### Single Node Example

```yarn
title: act1_tavern_intro
tags: main_quest act1
position: 0,0
---
// Generated by Storyarn — Flow: Tavern Introduction
<<declare $mc_jaime_health = 100>>
<<declare $flags_met_jaime = false>>

Jaime: Hello, traveler! #line:act1_001
-> Hello! #line:act1_002
    <<jump after_greeting>>
-> I need healing #line:act1_003 <<if $mc_jaime_health > 50>>
    Jaime: Let me help you. #line:act1_004
    <<set $mc_jaime_health to $mc_jaime_health + 20>>
    <<jump after_greeting>>
-> Leave me alone. #line:act1_005
    Jaime: As you wish. #line:act1_006
===

title: after_greeting
tags:
position: 0,200
---
<<set $flags_met_jaime to true>>
Jaime: Welcome to the Copper Tankard! #line:act1_007
===
```

### Key Format Rules

- **Header section:** `title:`, `tags:`, optional `position:` (for visual editors), separated by `---`
- **Body:** Content between `---` and `===`
- **Line tags:** `#line:id` at end of dialogue lines — used for localization string extraction
- **Options:** `->` prefix, indented content below
- **Conditional options:** `<<if condition>>` at end of option line
- **Commands:** `<<command>>` for game-engine-specific actions
- **Variables:** `$` prefix, declared with `<<declare>>`
- **Comments:** `//` for single-line comments

---

## Conversion Algorithm

### Phase 1: Flow to Yarn Nodes

1. Each Storyarn flow becomes one or more Yarn nodes
2. Hub nodes become separate Yarn nodes (jump targets)
3. Assign `title:` from flow shortcut (dots → underscores)
4. Assign `tags:` from flow metadata
5. Generate `position:` from Storyarn node coordinates (for Yarn visual editors)

### Phase 2: Node Traversal

1. Start from Entry node
2. Walk connections depth-first
3. Dialogue nodes → character lines with `#line:` tags
4. Condition nodes → `<<if>>` blocks
5. Instruction nodes → `<<set>>` commands
6. Hub references → `<<jump>>` commands
7. Exit nodes → `===` (end of Yarn node)

### Phase 3: Localization

Yarn's **built-in line tags** (`#line:id`) are the primary localization mechanism. This maps cleanly to Storyarn's localization system.

**String table CSV format:**
```csv
id,text,file,node,lineNumber,lock,comment
act1_001,"Hello, traveler!",act1_tavern_intro.yarn,act1_tavern_intro,5,,
act1_002,"Hello!",act1_tavern_intro.yarn,act1_tavern_intro,6,,
act1_003,"I need healing",act1_tavern_intro.yarn,act1_tavern_intro,8,,
```

**Per-language CSV:**
```csv
id,text
act1_001,"Hola, viajero!"
act1_002,"Hola!"
act1_003,"Necesito curación"
```

### Phase 4: Metadata Sidecar

```json
{
  "storyarn_yarn_metadata": "1.0.0",
  "characters": {
    "mc.jaime": {
      "name": "Jaime",
      "yarn_name": "Jaime",
      "properties": {"health": 100, "class": "warrior"}
    }
  },
  "variable_mapping": {
    "mc.jaime.health": "$mc_jaime_health",
    "flags.met_jaime": "$flags_met_jaime"
  },
  "flow_mapping": {
    "act1.tavern-intro": "act1_tavern_intro"
  }
}
```

---

## Output Structure

```
export/
├── dialogue/
│   ├── act1_tavern_intro.yarn
│   ├── act1_market_scene.yarn
│   └── act2_castle_gates.yarn
├── localization/
│   ├── en.csv                    # Source language string table
│   ├── es.csv                    # Spanish
│   └── de.csv                    # German
└── metadata.json                 # Character/variable/flow mapping
```

Or single-file mode:
```
export/
├── project_name.yarn             # All flows in one file
├── localization/
│   ├── en.csv
│   └── es.csv
└── metadata.json
```

---

## Edge Cases and Limitations

| Storyarn Feature             | Yarn Handling                                               | Severity   |
|------------------------------|-------------------------------------------------------------|------------|
| `contains` operator          | Export as custom function: `<<if contains($var, "val")>>`   | Medium     |
| `multi_select` variables     | Flatten to individual booleans                              | Low        |
| `table` variables            | Export as metadata JSON (no Yarn equivalent)                | Low        |
| Rich text (HTML) in dialogue | Strip HTML, use Yarn markup `[b]bold[/b]` where possible    | Low        |
| Audio asset references       | `<<audio asset_id>>` custom command                         | Low        |
| Scene node data              | `<<scene scene_id int_ext time>>` custom command            | Low        |
| Stage directions             | `// [Stage: direction]` as comment                          | Low        |
| Subflow with return          | Yarn v2 has no tunnel/return — becomes `<<jump>>` (one-way) | Medium     |
| Deeply nested conditions     | Flatten into sequential `<<if>>`/`<<elseif>>` blocks        | None       |
| Response-level instructions  | `<<set>>` inside option content block                       | None       |

**Subflow limitation:** Yarn v2 does not have Ink-style tunnels (call → return). Subflows become one-way jumps. Document this in export warnings when subflow nodes are detected.

---

## Implementation

### Serializer Module

```elixir
defmodule Storyarn.Exports.Serializers.Yarn do
  @behaviour Storyarn.Exports.Serializer

  def content_type, do: "text/plain"
  def file_extension, do: "yarn"
  def format_label, do: "Yarn Spinner (.yarn)"
  def supported_sections, do: [:flows, :sheets, :localization]

  def serialize(project_data, opts) do
    variables = collect_variables(project_data.sheets)
    mode = if length(project_data.flows) > 5, do: :multi_file, else: :single_file

    yarn_files = case mode do
      :single_file ->
        content = flows_to_yarn(project_data.flows, variables, opts)
        [{"#{project_name(project_data)}.yarn", content}]
      :multi_file ->
        Enum.map(project_data.flows, fn flow ->
          {yarn_filename(flow), flow_to_yarn(flow, variables, opts)}
        end)
    end

    metadata = build_metadata(project_data, variables)
    localization = build_string_tables(project_data, opts)

    {:ok, yarn_files ++ [{"metadata.json", Jason.encode!(metadata, pretty: true)} | localization]}
  end
end
```

### Expression Emitter

```elixir
defmodule Storyarn.Exports.ExpressionTranspiler.Yarn do
  @behaviour Storyarn.Exports.ExpressionTranspiler

  @operators %{
    "equals" => "==", "not_equals" => "!=",
    "greater_than" => ">", "less_than" => "<",
    "greater_than_or_equal" => ">=", "less_than_or_equal" => "<=",
    "is_true" => "== true", "is_false" => "== false",
    "is_nil" => "== null", "is_empty" => "== \"\"",
    "before" => "<", "after" => ">"
  }

  @custom_fn_operators ~w(contains not_contains starts_with ends_with)

  def transpile_condition(%{"logic" => logic, "rules" => rules}, ctx) do
    parts = Enum.map(rules, &transpile_rule(&1, ctx))
    joiner = if logic == "all", do: " and ", else: " or "
    {:ok, Enum.join(parts, joiner)}
  end

  def transpile_instruction(assignments, _ctx) do
    lines = Enum.map(assignments, &transpile_assignment/1)
    {:ok, Enum.join(lines, "\n")}
  end

  defp transpile_assignment(%{"sheet" => s, "variable" => v, "operator" => "set", "value" => val}) do
    "<<set $#{yarn_var(s, v)} to #{yarn_literal(val)}>>"
  end

  defp transpile_assignment(%{"sheet" => s, "variable" => v, "operator" => "add", "value" => val}) do
    var = yarn_var(s, v)
    "<<set $#{var} to $#{var} + #{val}>>"
  end

  defp yarn_var(sheet, variable), do: "#{flatten(sheet)}_#{flatten(variable)}"
  defp flatten(name), do: String.replace(name, ".", "_")
end
```

---

## Comparison: Ink vs Yarn for Storyarn Users

| Aspect                | Ink Export                                 | Yarn Export                      |
|-----------------------|--------------------------------------------|----------------------------------|
| Engine coverage       | ~90% (13+ runtimes)                        | ~40% (Unity, Godot, GM, GDev)    |
| Built-in localization | No (separate CSVs)                         | Yes (line tags + string tables)  |
| Variable restrictions | No dots allowed                            | Convention: no dots              |
| Subflow support       | Tunnels (call → return)                    | One-way jumps only               |
| Conditional choices   | Native (`+ {condition}`)                   | Native (`<<if>>` on option)      |
| Format complexity     | Higher (knots, stitches, tunnels, threads) | Lower (nodes, options, commands) |
| Compilation step      | Required (inklecate → .ink.json)           | Not required (.yarn is runtime)  |

**Recommendation to Storyarn users:** Use Ink for maximum portability, Yarn for localization-heavy projects or when targeting Unity/Godot specifically.

---

## Testing Strategy

- [ ] All Storyarn node types produce valid Yarn syntax
- [ ] Variable declarations with correct types and defaults
- [ ] Line tags generated for all translatable strings
- [ ] Conditions transpile all supported operators
- [ ] Unsupported features produce warnings
- [ ] Hub/Jump → Yarn node/`<<jump>>` mapping
- [ ] Multi-file output generates correct file structure
- [ ] Single-file output concatenates all nodes correctly
- [ ] String table CSVs match line tag IDs
- [ ] Per-language CSVs contain all translated strings
- [ ] Empty flows produce valid minimal Yarn nodes
- [ ] Responses with conditions use correct `<<if>>` syntax
- [ ] Custom commands (`<<scene>>`, `<<audio>>`) for engine-specific data
