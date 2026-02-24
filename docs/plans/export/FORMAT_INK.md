# Export Format: Ink (.ink)

> **Parent document:** [PHASE_8_EXPORT.md](../PHASE_8_EXPORT.md) | [RESEARCH_SYNTHESIS.md](./RESEARCH_SYNTHESIS.md)
>
> **Priority:** Highest ROI — 1 format reaches 13+ engine runtimes (~90% of game developers)
>
> **Serializer module:** `Storyarn.Exports.Serializers.Ink`
>
> **Expression emitter:** `Storyarn.Exports.ExpressionTranspiler.Ink`

---

## Why Ink First

| Metric                | Value                                                                                          |
|-----------------------|------------------------------------------------------------------------------------------------|
| GitHub stars          | 4,600+                                                                                         |
| Engine runtimes       | 13+ (C#, JS, C++, Rust, Lua, GDScript, Java, Kotlin, GameMaker, Swift, Haxe, Unreal C++, more) |
| Notable games         | 80 Days, Heaven's Vault, Sable, Citizen Sleeper, A Highland Song                               |
| Developer reach       | ~90% of active game developers have access to an Ink runtime                                   |
| Implementation effort | Medium (graph → linear conversion is the main challenge)                                       |

Ink is the closest thing to a **universal narrative interchange format** in the game industry. By exporting Ink, Storyarn projects become usable in virtually any game engine.

---

## Output

**Primary:** `.ink` text file (human-readable source)
**Secondary:** `.ink.json` compiled runtime format (optional, can be compiled client-side with inklecate)
**Localization:** Separate CSV/JSON string table per language (Ink has no built-in localization)

For MVP: Export `.ink` text only. Users compile with inklecate themselves. This is the standard workflow.

---

## Storyarn → Ink Mapping

### Structural Mapping

| Storyarn Concept   | Ink Equivalent                                  | Notes                                               |
|--------------------|-------------------------------------------------|-----------------------------------------------------|
| Flow               | Knot (`=== knot_name ===`)                      | Top-level flow = top-level knot                     |
| Entry node         | First line of knot                              | Implicit, no special syntax                         |
| Exit node          | `-> END` or `-> DONE`                           | END = story ends, DONE = thread ends                |
| Dialogue node      | Text line                                       | `Speaker: "Dialogue text"` (convention, not syntax) |
| Dialogue responses | Choices (`+ [Choice text]` / `* [Choice text]`) | `+` = sticky (reusable), `*` = once-only            |
| Condition node     | Conditional block                               | `{condition:}` or `{- condition: content}`          |
| Instruction node   | Variable assignment                             | `~ variable = value`                                |
| Hub node           | Label (stitch)                                  | `= label_name` within a knot                        |
| Jump node          | Divert                                          | `-> knot_name` or `-> knot_name.stitch_name`        |
| Subflow node       | Tunnel                                          | `-> subflow_knot ->` (returns after)                |
| Scene node         | Tag / metadata                                  | `# location: tavern` (Ink tags)                     |
| Sheet (character)  | No direct equivalent                            | Export as comments or companion metadata file       |
| Variables          | Global variables                                | `VAR name = value` at top of file                   |

### Variable Mapping

Ink does NOT allow dots in variable names. Storyarn's `sheet.variable` notation must be flattened:

| Storyarn | Ink |
|----------|-----|
| `mc.jaime.health` | `mc_jaime_health` |
| `flags.met_jaime` | `flags_met_jaime` |
| `inventory.gold` | `inventory_gold` |

```ink
VAR mc_jaime_health = 100
VAR flags_met_jaime = false
VAR inventory_gold = 0
```

### Expression Transpilation

**Conditions:**

| Storyarn Operator       | Ink Syntax                  | Notes                   |
|-------------------------|-----------------------------|-------------------------|
| `equals`                | `==`                        |                         |
| `not_equals`            | `!=`                        |                         |
| `greater_than`          | `>`                         |                         |
| `less_than`             | `<`                         |                         |
| `greater_than_or_equal` | `>=`                        |                         |
| `less_than_or_equal`    | `<=`                        |                         |
| `is_true`               | `variable` (truthy check)   |                         |
| `is_false`              | `not variable`              |                         |
| `is_nil`                | Export as warning           | Ink has no null concept |
| `is_empty` (text/multi) | `variable == ""`            |                         |
| `contains` (text)       | Export as warning           | No Ink equivalent       |
| `not_contains` (multi)  | Export as warning           | No Ink equivalent       |
| `starts_with` (text)    | Export as warning           | No Ink equivalent       |
| `ends_with` (text)      | Export as warning           | No Ink equivalent       |
| `before` (date)         | Export as warning           | No Ink date comparison  |
| `after` (date)          | Export as warning           | No Ink date comparison  |
| `all` (AND)             | `condition1 and condition2` |                         |
| `any` (OR)              | `condition1 or condition2`  |                         |

> **Block-format conditions:** The transpiler must handle BOTH flat format (`{logic, rules}`) AND block format (`{logic, blocks}` with `type: "block"` and `type: "group"` nesting, max 1 level). See [STORYARN_JSON_FORMAT.md](./STORYARN_JSON_FORMAT.md#condition-formats).

**Assignments:**

| Storyarn Operator  | Ink Syntax                             | Notes                  |
|--------------------|----------------------------------------|------------------------|
| `set`              | `~ variable = value`                   |                        |
| `add`              | `~ variable += value`                  | Ink supports `+=`      |
| `subtract`         | `~ variable -= value`                  |                        |
| `set_true`         | `~ variable = true`                    |                        |
| `set_false`        | `~ variable = false`                   |                        |
| `toggle`           | `~ variable = not variable`            |                        |
| `clear`            | `~ variable = ""`                      |                        |
| `set_if_unset`     | `{variable == "": ~ variable = value}` | Conditional assignment |

> **NO `multiply` operator.** Storyarn does not have a multiply operator. Source of truth: `lib/storyarn/flows/instruction.ex`
>
> **Variable-to-variable assignments:** When `value_type == "variable_ref"`, the value is another variable reference. Ink: `~ x = y` (both flattened to underscored names).

---

## Conversion Algorithm

### Phase 1: Graph Analysis

1. Topologically sort flow nodes (handle cycles via hub/jump labels)
2. Identify convergence points (hubs) → these become stitches/labels
3. Identify divergence points (conditions, dialogue responses) → these become choices or conditionals
4. Identify subflow references → these become tunnels

### Phase 2: Ink Generation

```
// Generated by Storyarn (https://storyarn.dev)
// Project: My RPG Project
// Flow: Tavern Introduction (act1.tavern-intro)
// Exported: 2026-02-24T15:30:00Z

// === Variables ===
VAR mc_jaime_health = 100
VAR flags_met_jaime = false
VAR inventory_gold = 0

// === Flow: Tavern Introduction ===
=== act1_tavern_intro ===

// [Speaker: Jaime]
Hello, traveler! #speaker:mc.jaime
    + [Hello!]
        -> after_greeting
    + {mc_jaime_health > 50} [I need healing]
        // [Speaker: Jaime]
        Let me help you. #speaker:mc.jaime
        ~ mc_jaime_health += 20
        -> after_greeting
    * [Leave me alone.]
        // [Speaker: Jaime]
        As you wish. #speaker:mc.jaime
        -> END

= after_greeting
~ flags_met_jaime = true
// [Speaker: Jaime]
Welcome to the Copper Tankard! #speaker:mc.jaime
-> END
```

### Phase 3: Metadata Sidecar

Since Ink has no built-in character/entity system, export a companion JSON:

```json
{
  "storyarn_ink_metadata": "1.0.0",
  "characters": {
    "mc.jaime": {
      "name": "Jaime",
      "ink_speaker_tag": "speaker:mc.jaime",
      "properties": {"health": 100, "class": "warrior"}
    }
  },
  "variable_mapping": {
    "mc.jaime.health": "mc_jaime_health",
    "flags.met_jaime": "flags_met_jaime"
  },
  "scenes": {
    "tavern": {"int_ext": "INT", "time_of_day": "NIGHT"}
  }
}
```

### Phase 4: Localization

Ink has no built-in localization. Export separate files:

```
export/
├── story.ink                    # Source language (default)
├── story_metadata.json          # Character/variable mapping
└── localization/
    ├── strings_en.csv           # English (source, for reference)
    ├── strings_es.csv           # Spanish
    └── strings_de.csv           # German
```

CSV format:
```csv
key,text
act1_tavern_intro_1,"Hello, traveler!"
act1_tavern_intro_2,"Let me help you."
act1_tavern_intro_3,"As you wish."
act1_tavern_intro_4,"Welcome to the Copper Tankard!"
```

---

## Edge Cases and Limitations

| Storyarn Feature                                       | Ink Handling                                   | Severity  |
|--------------------------------------------------------|------------------------------------------------|-----------|
| `contains`, `not_contains`, `starts_with`, `ends_with` | Export as warning — no Ink equivalents         | Medium    |
| `is_nil` operator                                      | Export as warning — Ink has no null            | Medium    |
| `before`, `after` (date)                               | Export as warning — Ink has no date comparison | Medium    |
| `multi_select` variables                               | Flatten to individual booleans                 | Low       |
| `table` variables                                      | Export as comments with raw data               | Low       |
| Rich text (HTML) in dialogue                           | Strip HTML tags, preserve plain text           | Low       |
| Audio asset references                                 | Export as Ink tags: `#audio:asset_id`          | Low       |
| Scene node location data                               | Export as Ink tags: `#location:scene_id`       | Low       |
| Stage directions                                       | Export as comments: `// [Stage: direction]`    | Low       |
| Menu text (short response)                             | Use as choice text (Ink's `[]` suppression)    | None      |
| Deeply nested conditions                               | Flatten with `and`/`or`                        | None      |

**Untranspilable expressions:** Always report as export warnings (never silent failures). Include raw Storyarn expression as comment above the problematic line.

---

## Implementation

### Serializer Module

```elixir
defmodule Storyarn.Exports.Serializers.Ink do
  @behaviour Storyarn.Exports.Serializer

  def content_type, do: "text/plain"
  def file_extension, do: "ink"
  def format_label, do: "Ink (.ink)"
  def supported_sections, do: [:flows, :sheets, :localization]

  def serialize(project_data, opts) do
    variables = collect_variables(project_data.sheets)
    flows = project_data.flows

    ink_source =
      [header(project_data, opts),
       variable_declarations(variables),
       Enum.map(flows, &flow_to_knot(&1, variables, opts))]
      |> List.flatten()
      |> Enum.join("\n")

    metadata = build_metadata_sidecar(project_data, variables)
    localization = build_localization_csvs(project_data, opts)

    {:ok, [{ink_filename(opts), ink_source},
           {"metadata.json", Jason.encode!(metadata, pretty: true)},
           localization]}
  end
end
```

### Expression Emitter

```elixir
defmodule Storyarn.Exports.ExpressionTranspiler.Ink do
  @behaviour Storyarn.Exports.ExpressionTranspiler

  @operators %{
    "equals" => "==", "not_equals" => "!=",
    "greater_than" => ">", "less_than" => "<",
    "greater_than_or_equal" => ">=", "less_than_or_equal" => "<=",
    "is_true" => :truthy, "is_false" => :not_truthy,
    "is_empty" => "=="  # compared against ""
  }

  @unsupported ~w(contains not_contains starts_with ends_with is_nil before after)

  def transpile_condition(%{"logic" => logic, "rules" => rules}, ctx) do
    {parts, warnings} = Enum.map_reduce(rules, [], &transpile_rule(&1, &2, ctx))
    joiner = if logic == "all", do: " and ", else: " or "
    {:ok, Enum.join(parts, joiner), warnings}
  end

  defp transpile_rule(%{"operator" => op}, warnings, _ctx) when op in @unsupported do
    {"true /* unsupported: #{op} */", [unsupported_operator_warning(op) | warnings]}
  end

  defp transpile_rule(%{"sheet" => s, "variable" => v, "operator" => "is_true"}, w, _ctx) do
    {ink_var(s, v), w}
  end

  defp transpile_rule(%{"sheet" => s, "variable" => v, "operator" => op, "value" => val}, w, _ctx) do
    {"#{ink_var(s, v)} #{@operators[op]} #{ink_literal(val)}", w}
  end

  defp ink_var(sheet, variable), do: "#{flatten_name(sheet)}_#{flatten_name(variable)}"
  defp flatten_name(name), do: String.replace(name, ".", "_")
end
```

---

## Testing Strategy

- [ ] All Storyarn node types produce valid Ink syntax
- [ ] Variables declared with correct types and initial values
- [ ] Conditions transpile all supported operators
- [ ] Unsupported operators produce warnings (not silent failures)
- [ ] Hub/Jump → label/divert round-trip
- [ ] Subflow → tunnel conversion
- [ ] Dialogue responses with conditions → conditional choices
- [ ] Graph cycles handled via labels (no infinite loops in output)
- [ ] Metadata sidecar contains all character/variable data
- [ ] Localization CSVs contain all translatable strings
- [ ] Output compiles with inklecate (integration test)
- [ ] Empty flows produce valid minimal Ink
- [ ] Flows with only entry/exit produce `-> END`
