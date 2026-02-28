# Export Format: Godot (Dialogic 2)

> **Parent document:** [PHASE_8_EXPORT.md](../PHASE_8_EXPORT.md) | [RESEARCH_SYNTHESIS.md](./RESEARCH_SYNTHESIS.md)
>
> **Priority:** Tier 2 — Engine-specific, targets the fastest-growing indie engine
>
> **Serializer module:** `Storyarn.Exports.Serializers.GodotDialogic`
>
> **Expression emitter:** `Storyarn.Exports.ExpressionTranspiler.Dialogic`

---

## Godot Market Context

| Metric              | Value                                   |
|---------------------|-----------------------------------------|
| Steam games (2024)  | 5% of all releases                      |
| YoY growth          | 69% increase in Godot games (2024→2025) |
| Game jam share      | 37% of GMTK 2024 (vs Unity's 43%)       |
| Top revenue game    | Brotato ($10.7M)                        |
| articy:draft plugin | Beta quality, not production-ready      |
| Ink runtimes        | GodotInk (C#), InkGD (pure GDScript)    |

**Key insight:** Godot is the fastest-growing engine. Dialogic 2 (~5.2k stars) is the dominant dialogue addon. Exporting `.dtl` gives users a plug-and-play workflow.

Note: Ink (.ink) and Yarn (.yarn) exports also work on Godot via GodotInk/InkGD/Yarn Spinner — those are covered in their own format documents. StoryarnJSON covers the "universal JSON" use case.

---

## Dialogic .dtl Export

### Dialogic .dtl Syntax Reference

```
// Character dialogue
Emilio: Hello and welcome!
This text has no character attached.

// Choices (branching)
- Yes
	Emilio: Great!
- No
	Emilio: Oh no...
- Maybe | [if {Stats.Charisma} > 10]
	Emilio: Interesting...

// Conditions
if {condition}:
	// indented events
elif {other_condition}:
	// alternative
else:
	// default

// Variables
set {variable_name} = 20
set {MyFolder.variable} += 2

// Navigation
label MyLabel
jump MyLabel
jump TimelineName/LabelIdentifier

// Events (shortcodes)
[background path="res://bg.png"]
[music path="res://music.ogg" fade="1"]
[wait time="2"]
```

### Storyarn → Dialogic Mapping

| Storyarn           | Dialogic .dtl                                |
|--------------------|----------------------------------------------|
| Dialogue node      | `Character: Text` line                       |
| Dialogue responses | `- Choice text` (TAB-indented content below) |
| Response condition | `- Text \| [if {condition}]`                 |
| Condition node     | `if {condition}:` / `else:`                  |
| Instruction node   | `set {Folder.Variable} = value`              |
| Hub node           | `label HubName`                              |
| Jump node          | `jump TargetLabel`                           |
| Subflow node       | `jump flow_shortcut/`                        |
| Scene node         | `# location: slug_line` comment              |
| Entry node         | First line of timeline                       |
| Exit node          | `[end_timeline]`                             |

### Variable Mapping

Dialogic organizes variables in folders. Map Storyarn's `sheet.variable` to Dialogic's `{Folder.Variable}`:

| Storyarn          | Dialogic            |
|-------------------|---------------------|
| `mc.jaime.health` | `{mc_jaime.health}` |
| `flags.met_jaime` | `{flags.met_jaime}` |

Strategy: Sheet shortcut (with dots → underscores) becomes the folder name, variable name stays as-is.

### Expression Transpilation

**Conditions** (GDScript operators, Dialogic curly-brace variable syntax):

| Storyarn Operator       | Dialogic output  | Notes                     |
|-------------------------|------------------|---------------------------|
| `equals`                | `==`             |                           |
| `not_equals`            | `!=`             |                           |
| `greater_than`          | `>`              |                           |
| `less_than`             | `<`              |                           |
| `greater_than_or_equal` | `>=`             |                           |
| `less_than_or_equal`    | `<=`             |                           |
| `is_true`               | `== true`        |                           |
| `is_false`              | `== false`       |                           |
| `is_nil`                | `== null`        |                           |
| `is_empty` (text/multi) | `== ""`          |                           |
| `contains` (text)       | `in`             | GDScript `in` operator    |
| `not_contains` (multi)  | `not in`         |                           |
| `starts_with` (text)    | `.begins_with()` | GDScript string method    |
| `ends_with` (text)      | `.ends_with()`   | GDScript string method    |
| `before` (date)         | `<`              | Dates compared as strings |
| `after` (date)          | `>`              |                           |
| `all` (AND)             | `and`            |                           |
| `any` (OR)              | `or`             |                           |

**Assignment operators:**

| Storyarn       | Dialogic .dtl                      | Notes                              |
|----------------|------------------------------------|------------------------------------|
| `set`          | `set {Folder.Var} = value`         |                                    |
| `add`          | `set {Folder.Var} += value`        |                                    |
| `subtract`     | `set {Folder.Var} -= value`        |                                    |
| `set_true`     | `set {Folder.Var} = true`          |                                    |
| `set_false`    | `set {Folder.Var} = false`         |                                    |
| `toggle`       | `set {Folder.Var} = !{Folder.Var}` | Manual negate                      |
| `clear`        | `set {Folder.Var} = ""`            |                                    |
| `set_if_unset` | `set {Folder.Var} = value`         | Semantic loss: emits unconditional |

> **Variable-to-variable assignments:** When `value_type == "variable_ref"`, the value is another variable reference: `set {Folder.Var} = {Folder.OtherVar}`.

### What NOT to Generate

- **`.dch` character files** — These are Godot Resource files (binary/text format tied to Godot internals). Provide a JSON sidecar with character data instead.
- **`.tres` resources** — Same reason. Godot-internal format.
- **Dialogic save data** — Runtime concern, not export concern.

### Character/Variable Sidecar (metadata.json)

```json
{
  "storyarn_dialogic_metadata": "1.0.0",
  "project": "Story Name",
  "characters": {
    "mc.jaime": {
      "display_name": "Jaime",
      "storyarn_shortcut": "mc.jaime",
      "properties": {
        "health": {"type": "number", "default": 100},
        "class": {"type": "string", "default": "warrior"}
      }
    }
  },
  "variable_folders": {
    "mc_jaime": {"health": 100, "class": "warrior"},
    "flags": {"met_jaime": false}
  },
  "timeline_mapping": {
    "act1.tavern-intro": "act1_tavern_intro.dtl"
  }
}
```

---

## Future: CSV Localization

Godot's native translation system imports CSV files directly. This is the highest-value localization export for Godot users.

**Format:**
```csv
keys,en,es,de
dialogue_1_text,"Hello, traveler!","Hola, viajero!","Hallo, Reisender!"
dialogue_1_r1,"Hello!","Hola!","Hallo!"
dialogue_1_r2,"Leave me alone.","Déjame en paz.","Lass mich in Ruhe."
```

This is deferred to a future phase.

---

## Testing

### Dialogic .dtl (45 tests — `godot_dialogic_test.exs`)
- [x] Behaviour callbacks (content_type, file_extension, format_label, supported_sections)
- [x] Empty project produces metadata only
- [x] Single flow produces .dtl + metadata
- [x] Dialogue with/without speaker
- [x] Stage directions as comments
- [x] HTML stripping
- [x] Choice rendering (plain and with conditions)
- [x] Condition if/else blocks
- [x] No explicit condition_end marker
- [x] Instruction set commands
- [x] Exit produces [end_timeline]
- [x] Hub produces label section
- [x] Jump navigation
- [x] Subflow with trailing slash
- [x] Scene location comments
- [x] Special character escaping (#, {, }, [, ], \)
- [x] Metadata characters, variable_folders, timeline_mapping
- [x] Multi-flow (one .dtl per flow)
- [x] Complex chains
- [x] Error paths (nil data, empty expressions, constants excluded)
