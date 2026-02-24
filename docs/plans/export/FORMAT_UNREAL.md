# Export Format: Unreal Engine

> **Parent document:** [PHASE_8_EXPORT.md](../PHASE_8_EXPORT.md) | [RESEARCH_SYNTHESIS.md](./RESEARCH_SYNTHESIS.md)
>
> **Priority:** Tier 2 — Engine-specific, covers AA/AAA market + growing indie adoption
>
> **Serializer module:** `Storyarn.Exports.Serializers.UnrealCSV`
>
> **Expression emitter:** `Storyarn.Exports.ExpressionTranspiler.Unreal`

---

## Unreal Market Context

| Metric                   | Value                                        |
|--------------------------|----------------------------------------------|
| Market position          | Dominant for AA/AAA, growing indie adoption  |
| Royalty                  | 3.5% after $1M (reduced from 5% in Jan 2025) |
| articy:draft v3 importer | Entering EOL — won't support UE beyond 5.5   |
| Top dialogue plugin      | Narrative by Reubs (2,000+ customers)        |
| Alternative              | DlgSystem (open-source, JSON import/export)  |
| Similar to Storyarn      | FlowGraph by MothCocoon                      |

**Key opportunity:** articy:draft's Unreal importer entering EOL creates a gap for Storyarn. articy's approach generates C++ classes (heavy compilation). Storyarn should use **runtime data** approach instead (JSON/CSV loaded at runtime, no recompilation needed).

---

## Export Strategy: Multi-File ZIP

Unreal doesn't have a single-file import format for structured narrative data. The standard approach is:

1. **DataTable CSVs** — Flat data importable as `UDataTable` assets
2. **Metadata JSON** — Graph structure, relationships, configuration
3. **StringTable CSVs** — Localization (native Unreal format)
4. **PO files** — Alternative localization via Unreal's gettext pipeline

### Output Structure

```
export/
├── DataTables/
│   ├── DT_DialogueLines.csv          # All dialogue text
│   ├── DT_Characters.csv             # Character data
│   ├── DT_Variables.csv              # Variable definitions
│   ├── DT_Conditions.csv             # Condition expressions
│   └── DT_Instructions.csv           # Assignment expressions
├── Metadata/
│   ├── Conversations.json            # Flow graph structure
│   ├── SceneData.json                # Scene/world data
│   └── ExportManifest.json           # File listing, version info
├── Localization/
│   ├── en/
│   │   └── Dialogue.csv              # StringTable format
│   ├── es/
│   │   └── Dialogue.csv
│   └── de/
│       └── Dialogue.csv
└── README.txt                         # Import instructions
```

---

## DataTable Formats

### DT_DialogueLines.csv

Maps to a `FTableRowBase` struct. Developers create a matching C++ struct or use Blueprint DataTables.

```csv
Name,ConversationId,NodeType,SpeakerId,Text,TextKey,MenuText,AudioCue,StageDirections,Sequence,NextLines,Conditions,UserScript
DLG_001,act1_tavern_intro,dialogue,mc_jaime,"Hello, traveler!",dlg_001,"",/Game/Audio/VO/DLG_001,"",0,"DLG_002|DLG_003","",""
DLG_002,act1_tavern_intro,response,,Hello!,dlg_002,"","","",0,"DLG_004","",""
DLG_003,act1_tavern_intro,response,,"Leave me alone.",dlg_003,"","","",0,"DLG_005","mc.jaime.health > 50",""
DLG_004,act1_tavern_intro,instruction,,,,,"","",0,"DLG_006","","flags.met_jaime = true"
DLG_005,act1_tavern_intro,dialogue,mc_jaime,"As you wish.",dlg_005,"","","",0,"","",""
DLG_006,act1_tavern_intro,dialogue,mc_jaime,"Welcome to the Copper Tankard!",dlg_006,"","","",0,"","",""
```

**Column definitions:**

| Column            | Type            | Description                                                                |
|-------------------|-----------------|----------------------------------------------------------------------------|
| `Name`            | FName           | Row name (unique identifier) — used as primary key                         |
| `ConversationId`  | FString         | Flow shortcut (dots → underscores)                                         |
| `NodeType`        | FString         | `dialogue`, `response`, `condition`, `instruction`, `hub`, `jump`, `scene` |
| `SpeakerId`       | FString         | Character shortcut (empty for non-dialogue)                                |
| `Text`            | FText           | Dialogue text (localizable)                                                |
| `TextKey`         | FString         | Localization key                                                           |
| `MenuText`        | FString         | Short response text (for dialogue wheel)                                   |
| `AudioCue`        | FSoftObjectPath | Path to audio asset                                                        |
| `StageDirections` | FString         | Stage direction text                                                       |
| `Sequence`        | int32           | Ordering within conversation                                               |
| `NextLines`       | FString         | Pipe-separated list of next row names                                      |
| `Conditions`      | FString         | Condition expression (Unreal-compatible)                                   |
| `UserScript`      | FString         | Assignment expression                                                      |

### DT_Characters.csv

```csv
Name,DisplayName,ShortcutId,IsPlayer,PortraitPath,Properties
CHAR_mc_jaime,Jaime,mc.jaime,false,/Game/Assets/Characters/Jaime/portrait,"{""health"":100,""class"":""warrior""}"
CHAR_player,Player,player,true,,,"{}"
```

### DT_Variables.csv

```csv
Name,VariableId,Type,DefaultValue,SheetShortcut,VariableName,Description
VAR_mc_jaime_health,mc.jaime.health,Number,100,mc.jaime,health,Character health
VAR_flags_met_jaime,flags.met_jaime,Boolean,false,flags,met_jaime,Met Jaime flag
```

---

## Expression Transpilation

### Unreal Expression Syntax

Unreal doesn't have a universal expression language like Lua or GDScript. Conditions are typically:
- Blueprint-compatible string expressions
- Dot notation for variable references (preserved from Storyarn)
- Standard operators

**Conditions:**

| Storyarn Operator       | Unreal Syntax              | Notes                     |
|-------------------------|----------------------------|---------------------------|
| `equals`                | `==`                       |                           |
| `not_equals`            | `!=`                       |                           |
| `greater_than`          | `>`                        |                           |
| `less_than`             | `<`                        |                           |
| `greater_than_or_equal` | `>=`                       |                           |
| `less_than_or_equal`    | `<=`                       |                           |
| `is_true`               | `== true`                  |                           |
| `is_false`              | `== false`                 |                           |
| `is_nil`                | `== None`                  |                           |
| `is_empty` (text/multi) | `== ""`                    |                           |
| `contains` (text)       | `Contains` (function call) |                           |
| `not_contains` (multi)  | `!Contains`                |                           |
| `starts_with` (text)    | Custom function            | Blueprint-compatible      |
| `ends_with` (text)      | Custom function            | Blueprint-compatible      |
| `before` (date)         | `<`                        | Dates compared as strings |
| `after` (date)          | `>`                        |                           |
| `all` (AND)             | `AND`                      | Uppercase                 |
| `any` (OR)              | `OR`                       | Uppercase                 |

> **Block-format conditions:** The transpiler must handle BOTH flat format (`{logic, rules}`) AND block format (`{logic, blocks}` with `type: "block"` and `type: "group"` nesting, max 1 level). See [STORYARN_JSON_FORMAT.md](./STORYARN_JSON_FORMAT.md#condition-formats).

**Assignments:**

| Storyarn Operator  | Unreal Syntax                           | Notes       |
|--------------------|-----------------------------------------|-------------|
| `set`              | `variable = value`                      |             |
| `add`              | `variable += value`                     |             |
| `subtract`         | `variable -= value`                     |             |
| `set_true`         | `variable = true`                       |             |
| `set_false`        | `variable = false`                      |             |
| `toggle`           | `variable = !variable`                  |             |
| `clear`            | `variable = ""`                         |             |
| `set_if_unset`     | `if variable == None: variable = value` | Conditional |

> **NO `multiply` operator.** Storyarn does not have a multiply operator. Source of truth: `lib/storyarn/flows/instruction.ex`
>
> **Variable-to-variable assignments:** When `value_type == "variable_ref"`, the value is another variable reference. Unreal: `variable = other_variable` (dot notation preserved).

### Variable References

Unreal preserves dot notation: `mc.jaime.health` stays as-is. The game's C++ or Blueprint code is responsible for resolving the reference.

---

## Metadata JSON

### Conversations.json

Stores the graph structure that CSV can't represent:

```json
{
  "format": "storyarn_unreal",
  "version": "1.0.0",
  "conversations": {
    "act1_tavern_intro": {
      "name": "Tavern Introduction",
      "shortcut": "act1.tavern-intro",
      "start_line": "DLG_001",
      "participants": ["mc_jaime", "player"],
      "tags": ["main_quest", "act1"],
      "graph": {
        "nodes": {
          "DLG_001": {"type": "dialogue", "outputs": ["DLG_002", "DLG_003"]},
          "DLG_002": {"type": "response", "outputs": ["DLG_004"]},
          "DLG_003": {"type": "response", "outputs": ["DLG_005"], "condition": "mc.jaime.health > 50"}
        },
        "hubs": {
          "after_greeting": {"entry_lines": ["DLG_002"], "exit_lines": ["DLG_006"]}
        },
        "jumps": {}
      }
    }
  },
  "characters": {
    "mc_jaime": {
      "display_name": "Jaime",
      "shortcut": "mc.jaime",
      "properties": {"health": 100, "class": "warrior"}
    }
  },
  "variables": {
    "mc.jaime.health": {"type": "number", "default": 100},
    "flags.met_jaime": {"type": "boolean", "default": false}
  }
}
```

---

## Localization

### StringTable CSV (Native Unreal)

```csv
Key,SourceString
dlg_001,"Hello, traveler!"
dlg_002,"Hello!"
dlg_003,"Leave me alone."
dlg_005,"As you wish."
dlg_006,"Welcome to the Copper Tankard!"
```

Per-language files follow Unreal's `{Culture}/` directory convention:
- `Localization/en/Dialogue.csv` — source
- `Localization/es/Dialogue.csv` — Spanish
- `Localization/de/Dialogue.csv` — German

### PO Files (Alternative)

For teams using Unreal's gettext-based localization pipeline:

```po
msgid "dlg_001"
msgstr "Hola, viajero!"

msgid "dlg_002"
msgstr "Hola!"
```

Export both formats and let users choose.

---

## Edge Cases

| Storyarn Feature         | Unreal Handling                                | Severity    |
|--------------------------|------------------------------------------------|-------------|
| Graph structure          | CSV is flat — store graph in metadata JSON     | Core design |
| `multi_select` variables | Comma-separated string in CSV                  | Low         |
| `table` variables        | Separate DataTable or metadata JSON            | Medium      |
| Rich text (HTML)         | Convert to Unreal's `<RichText>` tags or strip | Medium      |
| Audio asset references   | Map to `/Game/...` paths                       | Low         |
| Scene data               | Separate SceneData.json                        | Low         |
| Cross-flow jumps         | Cross-conversation references in metadata      | Medium      |
| Large datasets           | CSV row limits (unlikely to hit)               | Very low    |

---

## Integration Guide (included in export)

The README.txt included in the ZIP should document:

1. **How to import DataTables** — Create matching C++ struct or Blueprint DataTable, import CSV
2. **How to import StringTables** — Place in `Content/Localization/{Culture}/`
3. **How to read metadata JSON** — `FJsonObject` parsing in C++ or JsonUtilities
4. **Recommended plugins** — Narrative (Reubs), DlgSystem, or custom implementation
5. **Variable resolution** — How to wire `mc.jaime.health` to game state

---

## Testing Strategy

- [ ] CSV files import correctly as Unreal DataTables
- [ ] All column types match FTableRowBase expectations
- [ ] Pipe-separated `NextLines` correctly represent graph connections
- [ ] Condition expressions are valid Unreal-compatible syntax
- [ ] StringTable CSVs import in Unreal's localization system
- [ ] Metadata JSON is valid and contains complete graph structure
- [ ] ZIP file structure follows Unreal content conventions
- [ ] Asset paths use `/Game/...` convention
- [ ] Hub/Jump relationships correctly represented in metadata
- [ ] Cross-conversation references work
- [ ] Empty conversations produce valid minimal CSVs
