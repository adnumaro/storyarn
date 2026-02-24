# Export Format: Unity

> **Parent document:** [PHASE_8_EXPORT.md](../PHASE_8_EXPORT.md) | [RESEARCH_SYNTHESIS.md](./RESEARCH_SYNTHESIS.md)
>
> **Priority:** Tier 2 — Engine-specific, targets the largest indie engine by market share
>
> **Serializer module:** `Storyarn.Exports.Serializers.UnityJSON`
>
> **Expression emitter:** `Storyarn.Exports.ExpressionTranspiler.Unity`

---

## Unity Market Context

| Metric                   | Value                                          |
|--------------------------|------------------------------------------------|
| Game jam share           | ~43% of GMTK 2024                              |
| Dominant dialogue plugin | Dialogue System for Unity (DSfU) — $75, 5-star |
| Ink runtime              | First-class (Inkle's own C# runtime)           |
| Yarn Spinner             | Official Unity integration, free alternative   |
| articy:draft             | Free tier caps at 700 objects                  |

**Note:** Ink (.ink) and Yarn (.yarn) exports also work on Unity — those are covered in their own format documents. This document covers the Unity-specific DSfU JSON format.

---

## Target: Dialogue System for Unity (DSfU)

DSfU by PixelCrushers is the most widely used paid dialogue plugin in Unity. Its JSON import format is well-documented and stable.

### Key Architecture

- **Actors** = Characters with custom fields
- **Conversations** = Flows with dialogue entries
- **DialogueEntry** = Individual node (dialogue, condition, group, etc.)
- **Links** = Connections between entries
- **Variables** = Typed globals with initial values
- **Localization** = Separate CSV per language

---

## Storyarn → DSfU Mapping

| Storyarn           | DSfU JSON                           | Notes                                      |
|--------------------|-------------------------------------|--------------------------------------------|
| Sheet (character)  | Actor with `fields[]`               | Block values → custom fields               |
| Flow               | Conversation                        | `title`, `actor_id`, `conversant_id`       |
| Entry node         | Root entry (`is_root: true`)        | First entry in conversation                |
| Exit node          | Entry with no `links_to`            | Terminal node                              |
| Dialogue node      | DialogueEntry                       | `actor_id`, `dialogue_text`, `sequence`    |
| Dialogue responses | Child entries with `isGroup: false` | Each response = separate entry             |
| Condition node     | `conditionsString` on links         | Lua expression (via transpiler)            |
| Instruction node   | `userScript` on entries             | Lua expression (via transpiler)            |
| Hub node           | Group entry (`isGroup: true`)       | Convergence point                          |
| Jump node          | Cross-conversation link             | `link_to` with `destinationConversationID` |
| Subflow node       | Cross-conversation reference        | Like jump, but marks return point          |
| Scene node         | Metadata entry                      | `sequence` field for cinematics/location   |
| Variables          | Global variables table              | Typed (`number`, `boolean`, `string`)      |

### Expression Transpilation (Lua)

**Conditions:**

| Storyarn Operator       | Lua (Unity)         | Notes                                      |
|-------------------------|---------------------|--------------------------------------------|
| `equals`                | `==`                |                                            |
| `not_equals`            | `~=`                | **Lua-specific** (not `!=`)                |
| `greater_than`          | `>`                 |                                            |
| `less_than`             | `<`                 |                                            |
| `greater_than_or_equal` | `>=`                |                                            |
| `less_than_or_equal`    | `<=`                |                                            |
| `is_true`               | `== true`           |                                            |
| `is_false`              | `== false`          |                                            |
| `is_nil`                | `== nil`            | Lua-specific (not `null`)                  |
| `is_empty` (text/multi) | `== ""`             |                                            |
| `contains` (text)       | Custom Lua function | `StringContains(Variable["x"], "val")`     |
| `not_contains` (multi)  | Custom Lua function | `not StringContains(Variable["x"], "val")` |
| `starts_with` (text)    | Custom Lua function | `StringStartsWith(Variable["x"], "val")`   |
| `ends_with` (text)      | Custom Lua function | `StringEndsWith(Variable["x"], "val")`     |
| `before` (date)         | `<`                 | Dates compared as strings                  |
| `after` (date)          | `>`                 |                                            |
| `all` (AND)             | `and`               |                                            |
| `any` (OR)              | `or`                |                                            |

**Variable access pattern:** `Variable["mc.jaime.health"]` (Lua table syntax, dots preserved in key)

**Critical Lua quirk:** `~=` for not-equal (not `!=`).

> **Block-format conditions:** The transpiler must handle BOTH flat format (`{logic, rules}`) AND block format (`{logic, blocks}` with `type: "block"` and `type: "group"` nesting, max 1 level). See [STORYARN_JSON_FORMAT.md](./STORYARN_JSON_FORMAT.md#condition-formats).

**Assignments:**

| Storyarn Operator   | Lua (Unity)                                              | Notes          |
|---------------------|----------------------------------------------------------|----------------|
| `set`               | `Variable["x"] = value`                                  |                |
| `add`               | `Variable["x"] = Variable["x"] + value`                  | No `+=` in Lua |
| `subtract`          | `Variable["x"] = Variable["x"] - value`                  | No `-=` in Lua |
| `set_true`          | `Variable["x"] = true`                                   |                |
| `set_false`         | `Variable["x"] = false`                                  |                |
| `toggle`            | `Variable["x"] = not Variable["x"]`                      |                |
| `clear`             | `Variable["x"] = ""`                                     |                |
| `set_if_unset`      | `if Variable["x"] == nil then Variable["x"] = value end` | Conditional    |

> **NO `multiply` operator.** Storyarn does not have a multiply operator. Source of truth: `lib/storyarn/flows/instruction.ex`
>
> **Variable-to-variable assignments:** When `value_type == "variable_ref"`, the value is another variable reference. Lua: `Variable["x"] = Variable["y"]`.
>
> Note: Lua has no compound assignment operators (`+=`, `-=`). Must expand to full expression.

---

## Output Format

### Complete DSfU JSON

```json
{
  "format": "unity_dialogue_system",
  "version": "1.0.0",
  "storyarn_version": "1.0.0",
  "database": {
    "actors": [
      {
        "id": 1,
        "name": "Jaime",
        "shortcut": "mc.jaime",
        "is_player": false,
        "portrait": "Assets/Characters/Jaime/portrait.png",
        "fields": [
          {"title": "health", "type": 1, "value": "100"},
          {"title": "class", "type": 0, "value": "warrior"},
          {"title": "is_alive", "type": 3, "value": "true"}
        ]
      }
    ],
    "conversations": [
      {
        "id": 1,
        "title": "Tavern Introduction",
        "shortcut": "act1.tavern-intro",
        "description": "",
        "actor_id": 1,
        "conversant_id": 0,
        "node_color": "",
        "entries": [
          {
            "id": 0,
            "is_root": true,
            "is_group": false,
            "node_color": "",
            "delay_sim_status": 0,
            "false_condition_action": "Block",
            "actor_id": 1,
            "conversant_id": 0,
            "dialogue_text": "Hello, traveler!",
            "menu_text": "",
            "sequence": "",
            "conditions": "",
            "user_script": "",
            "canvas_rect": {"x": 100, "y": 100, "width": 160, "height": 50},
            "links_to": [1, 2]
          },
          {
            "id": 1,
            "is_root": false,
            "is_group": false,
            "actor_id": 0,
            "dialogue_text": "Hello!",
            "conditions": "",
            "user_script": "Variable[\"flags.met_jaime\"] = true",
            "links_to": [3]
          },
          {
            "id": 2,
            "is_root": false,
            "is_group": false,
            "actor_id": 0,
            "dialogue_text": "Leave me alone.",
            "conditions": "Variable[\"mc.jaime.health\"] > 50",
            "user_script": "",
            "links_to": [4]
          }
        ]
      }
    ],
    "variables": [
      {"name": "mc.jaime.health", "type": 1, "initial_value": "100"},
      {"name": "mc.jaime.class", "type": 0, "initial_value": "warrior"},
      {"name": "flags.met_jaime", "type": 3, "initial_value": "false"}
    ]
  },
  "localization": {
    "default_language": "en",
    "languages": ["en", "es", "de"],
    "csv_data": {
      "en": "...",
      "es": "...",
      "de": "..."
    }
  }
}
```

### DSfU Variable Types

| Type           | Code   | Storyarn Equivalent           |
|----------------|--------|-------------------------------|
| String         | 0      | `text`, `select`              |
| Number         | 1      | `number`                      |
| Localized Text | 2      | `rich_text` with localization |
| Boolean        | 3      | `boolean`                     |

### DSfU Entry Field Types

| Field                    | Description                                              |
|--------------------------|----------------------------------------------------------|
| `dialogue_text`          | Main dialogue line                                       |
| `menu_text`              | Short text shown in response menu (Storyarn `menu_text`) |
| `sequence`               | Cinematic sequence commands (audio, camera, etc.)        |
| `conditions`             | Lua condition string (controls if entry is available)    |
| `user_script`            | Lua script executed when entry plays                     |
| `false_condition_action` | "Block" (hide) or "Passthrough" (skip to next)           |

### Localization CSV Format

DSfU uses per-language CSV files:

```csv
DialogueText,Translation
"Hello, traveler!","Hola, viajero!"
"Hello!","Hola!"
"Leave me alone.","Déjame en paz."
```

---

## ID Management

DSfU uses integer IDs (not UUIDs). Strategy:
1. Generate sequential integer IDs during export
2. Store UUID → integer mapping in metadata for re-export stability
3. Actor IDs start at 1, Entry IDs start at 0 per conversation
4. Cross-conversation links use `destinationConversationID` + `destinationEntryID`

---

## Output Structure

```
export/
├── project_name_dsfu.json         # Main DSfU database
├── localization/
│   ├── Dialogue_en.csv            # English localization
│   ├── Dialogue_es.csv            # Spanish
│   └── Dialogue_de.csv            # German
└── metadata.json                  # UUID→ID mapping, Storyarn metadata
```

---

## Edge Cases

| Storyarn Feature         | DSfU Handling                                               | Severity  |
|--------------------------|-------------------------------------------------------------|-----------|
| `multi_select` variables | Flatten to comma-separated string                           | Low       |
| `table` variables        | Export as metadata, not DSfU variables                      | Low       |
| Rich text (HTML)         | Convert to DSfU's `[em1]...[/em1]` tags                     | Medium    |
| Audio asset references   | Map to `sequence` field: `AudioWait(asset_path)`            | Low       |
| Scene node data          | Map to `sequence` field for camera/location                 | Low       |
| Stage directions         | Map to `sequence` field                                     | Low       |
| Deeply nested conditions | Flatten with Lua `and`/`or`                                 | None      |
| `contains` operator      | Custom Lua function: `StringContains(Variable["x"], "val")` | Medium    |

---

## Testing Strategy

- [ ] Generated JSON imports correctly in DSfU's Database Editor
- [ ] Actors have correct fields and types
- [ ] Conversations have correct entry structure
- [ ] `conditionsString` contains valid Lua (test with Lua parser)
- [ ] `userScript` contains valid Lua
- [ ] Cross-conversation links resolve correctly
- [ ] Variable types match DSfU type codes
- [ ] Localization CSVs import in DSfU's localization system
- [ ] Integer ID generation is deterministic (re-export produces same IDs)
- [ ] Hub nodes become group entries
- [ ] Jump nodes create cross-conversation links
- [ ] Empty conversations produce valid minimal structure
