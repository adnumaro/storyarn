# Export Format: Godot

> **Parent document:** [PHASE_8_EXPORT.md](../PHASE_8_EXPORT.md) | [RESEARCH_SYNTHESIS.md](./RESEARCH_SYNTHESIS.md)
>
> **Priority:** Tier 2 — Engine-specific, targets the fastest-growing indie engine
>
> **Serializer modules:** `Storyarn.Exports.Serializers.GodotJSON` + `Storyarn.Exports.Serializers.GodotDialogic`
>
> **Expression emitter:** `Storyarn.Exports.ExpressionTranspiler.Godot`

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

**Key insight:** Godot is the fastest-growing engine. The articy:draft Godot plugin is immature. This is Storyarn's best opportunity for early adoption.

---

## Three Export Options

Godot gets three export options because the ecosystem is fragmented:

| Export               | Target Users                       | Format                           |
|----------------------|------------------------------------|----------------------------------|
| **Generic JSON**     | All Godot devs (no addon required) | `.json`                          |
| **Dialogic .dtl**    | Dialogic 2 users (~5.2k stars)     | `.dtl` text + `.json` characters |
| **CSV Localization** | All Godot devs (native import)     | `.csv` per language              |

Note: Ink (.ink) and Yarn (.yarn) exports also work on Godot via GodotInk/InkGD/Yarn Spinner — those are covered in their own format documents.

---

## Export 1: Generic JSON (All Godot Users)

**Why:** JSON is natively parseable in Godot via the `JSON` class. No addons required. This is the universal fallback.

**Module:** `Storyarn.Exports.Serializers.GodotJSON`

### Output Format

```json
{
  "format": "godot_dialogue",
  "version": "1.0.0",
  "storyarn_version": "1.0.0",
  "exported_at": "2026-02-24T15:30:00Z",
  "characters": {
    "mc.jaime": {
      "name": "Jaime",
      "portrait": "res://assets/characters/jaime.png",
      "properties": {
        "health": {"type": "number", "value": 100},
        "class": {"type": "select", "value": "warrior"},
        "is_alive": {"type": "boolean", "value": true}
      }
    }
  },
  "variables": {
    "mc_jaime_health": {"type": "number", "default": 100, "source": "mc.jaime.health"},
    "flags_met_jaime": {"type": "boolean", "default": false, "source": "flags.met_jaime"}
  },
  "flows": {
    "act1.tavern-intro": {
      "name": "Tavern Introduction",
      "start_node": "entry_1",
      "nodes": {
        "entry_1": {
          "type": "entry",
          "next": ["dialogue_1"]
        },
        "dialogue_1": {
          "type": "dialogue",
          "character": "mc.jaime",
          "text": "Hello, traveler!",
          "stage_directions": "",
          "audio": null,
          "responses": [
            {"id": "r1", "text": "Hello!", "next": "hub_1", "condition": null},
            {"id": "r2", "text": "Leave me alone.", "next": "exit_1", "condition": "mc_jaime_health > 50"}
          ]
        },
        "hub_1": {
          "type": "hub",
          "label": "after_greeting",
          "next": ["instruction_1"]
        },
        "instruction_1": {
          "type": "instruction",
          "code": "flags_met_jaime = true",
          "assignments": [
            {"variable": "flags_met_jaime", "operator": "set", "value": true}
          ],
          "next": ["exit_1"]
        },
        "exit_1": {
          "type": "exit",
          "technical_id": "tavern_complete"
        }
      }
    }
  },
  "scenes": {
    "overworld": {
      "name": "Overworld",
      "layers": [...],
      "pins": [...],
      "zones": [...],
      "connections": [...]
    }
  },
  "localization": {
    "source_language": "en",
    "languages": ["en", "es", "de"],
    "strings": {
      "dialogue_1_text": {"en": "Hello, traveler!", "es": "Hola, viajero!", "de": "Hallo, Reisender!"},
      "dialogue_1_r1": {"en": "Hello!", "es": "Hola!", "de": "Hallo!"}
    }
  }
}
```

### Design Decisions

- **Variable names use underscores** (`mc_jaime_health`) — Godot convention, GDScript-compatible
- **Asset paths use `res://` prefix** — Godot resource path convention
- **Both transpiled expressions AND raw structured data** — `"code"` field has GDScript expression, `"assignments"` has raw Storyarn data for custom parsers
- **Dual `next` format:** Arrays for nodes with multiple outputs, single string for linear connections
- **Scene data included** — Full scene export for world-builder integration

---

## Export 2: Dialogic .dtl (Dominant Addon)

**Why:** Dialogic 2 (~5.2k stars) is the most popular dialogue addon for Godot 4. Exporting `.dtl` timeline files gives users a plug-and-play workflow.

**Module:** `Storyarn.Exports.Serializers.GodotDialogic`

### Dialogic .dtl Syntax Reference

```
// Character dialogue
Emilio: Hello and welcome!
Emilio (excited): I'm so excited!
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
| Condition node     | `if {condition}:` / `elif:` / `else:`        |
| Instruction node   | `set {Folder.Variable} = value`              |
| Hub node           | `label HubName`                              |
| Jump node          | `jump TargetTimeline/LabelName`              |
| Subflow node       | Timeline reference (jump to another .dtl)    |
| Scene node         | Custom event (shortcode)                     |
| Entry node         | First line of timeline                       |
| Exit node          | End of timeline (implicit)                   |

### Variable Mapping

Dialogic organizes variables in folders. Map Storyarn's `sheet.variable` to Dialogic's `{Folder.Variable}`:

| Storyarn          | Dialogic            |
|-------------------|---------------------|
| `mc.jaime.health` | `{mc_jaime.health}` |
| `flags.met_jaime` | `{flags.met_jaime}` |

Strategy: Sheet shortcut (with dots → underscores) becomes the folder name, variable name stays as-is.

### Expression Transpilation (GDScript)

**Conditions:**

| Storyarn Operator       | GDScript         | Notes                     |
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

> **Block-format conditions:** The transpiler must handle BOTH flat format (`{logic, rules}`) AND block format (`{logic, blocks}` with `type: "block"` and `type: "group"` nesting, max 1 level). See [STORYARN_JSON_FORMAT.md](./STORYARN_JSON_FORMAT.md#condition-formats).

**Assignment operators:**

| Storyarn       | Dialogic .dtl                                            | Notes         |
|----------------|----------------------------------------------------------|---------------|
| `set`          | `set {Folder.Var} = value`                               |               |
| `add`          | `set {Folder.Var} += value`                              |               |
| `subtract`     | `set {Folder.Var} -= value`                              |               |
| `set_true`     | `set {Folder.Var} = true`                                |               |
| `set_false`    | `set {Folder.Var} = false`                               |               |
| `toggle`       | `set {Folder.Var} = !{Folder.Var}`                       | Manual negate |
| `clear`        | `set {Folder.Var} = ""`                                  |               |
| `set_if_unset` | `if {Folder.Var} == null:\n    set {Folder.Var} = value` | Conditional   |

> **NO `multiply` operator.** Storyarn does not have a multiply operator. Source of truth: `lib/storyarn/flows/instruction.ex`
>
> **Variable-to-variable assignments:** When `value_type == "variable_ref"`, the value is another variable reference. GDScript/Dialogic: `set {Folder.Var} = {Folder.OtherVar}`.

### Example Output

```
// Generated by Storyarn
// Flow: Tavern Introduction (act1.tavern-intro)

Jaime: Hello, traveler!
- Hello!
    jump after_greeting
- Leave me alone. | [if {mc_jaime.health} > 50]
    Jaime: As you wish.
    jump tavern_end

label after_greeting
set {flags.met_jaime} = true
Jaime: Welcome to the Copper Tankard!

label tavern_end
```

### What NOT to Generate

- **`.dch` character files** — These are Godot Resource files (binary/text format tied to Godot internals). Provide a JSON sidecar with character data instead, and document how users create `.dch` files in Dialogic.
- **`.tres` resources** — Same reason. Godot-internal format.
- **Dialogic save data** — Runtime concern, not export concern.

### Character Sidecar (JSON)

```json
{
  "storyarn_dialogic_metadata": "1.0.0",
  "characters": {
    "mc.jaime": {
      "display_name": "Jaime",
      "dialogic_name": "Jaime",
      "portrait_path": "res://assets/characters/jaime.png",
      "color": "#8b5cf6",
      "properties": {"health": 100, "class": "warrior"}
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

## Export 3: CSV Localization (Universal Godot)

Godot's native translation system imports CSV files directly. This is the highest-value localization export.

**Format:**
```csv
keys,en,es,de
dialogue_1_text,"Hello, traveler!","Hola, viajero!","Hallo, Reisender!"
dialogue_1_r1,"Hello!","Hola!","Hallo!"
dialogue_1_r2,"Leave me alone.","Déjame en paz.","Lass mich in Ruhe."
```

Godot auto-imports CSV files placed in the project as translation resources. Column headers are locale codes. This is the most frictionless way to get Storyarn localization into Godot.

---

## Output Structure

```
export/
├── json/
│   └── project_name.json          # Generic JSON (option 1)
├── dialogic/
│   ├── timelines/
│   │   ├── act1_tavern_intro.dtl  # Dialogic timeline
│   │   └── act2_castle_gates.dtl
│   ├── metadata.json              # Character/variable mapping
│   └── README.txt                 # Setup instructions for Dialogic
├── localization/
│   └── translations.csv           # Godot CSV translation import
└── scenes/
    └── scenes.json                # Scene/world data (generic JSON)
```

---

## Testing Strategy

### Generic JSON
- [ ] Valid JSON output parseable by Godot's JSON class
- [ ] All node types correctly represented
- [ ] Variable names use underscores (GDScript-compatible)
- [ ] Asset paths use `res://` prefix
- [ ] Localization strings keyed correctly

### Dialogic .dtl
- [ ] Generated .dtl files parse in Dialogic 2
- [ ] Character names match correctly
- [ ] Choices with conditions use correct `| [if {}]` syntax
- [ ] Labels and jumps navigate correctly
- [ ] Variable operations use correct Dialogic syntax
- [ ] TAB indentation is correct for scope
- [ ] Empty flows produce minimal valid timelines

### CSV Localization
- [ ] CSV imports correctly in Godot Project Settings > Localization
- [ ] All translatable strings included
- [ ] Column headers are valid locale codes
- [ ] Special characters (commas, quotes) properly escaped
