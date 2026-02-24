# Phase 8: Export — Game Engine Formats

> **Parent document:** [PHASE_8_EXPORT.md](../PHASE_8_EXPORT.md)

## Design Principles for Engine Exports

- **Target real plugins, not abstract formats.** Each engine has a dominant dialogue plugin. Export compatible with it and you cover 80%+ of users.
- **Expressions are the hard part.** The JSON/XML structure is mechanical; translating conditions and instructions to each engine's scripting language is where 80% of the complexity lives (see [ARCHITECTURE.md](./ARCHITECTURE.md#expression-transpiler-critical-complexity)).
- **Provide escape hatches.** Include raw Storyarn expressions as comments/metadata alongside transpiled versions, so users can debug mismatches.
- **Asset paths use engine conventions.** Unity: `Assets/...`, Godot: `res://...`, Unreal: `/Game/...`
- **Flow→Scene association.** Flows have an optional `scene_id` linking to a scene backdrop. Engine exports should include this as metadata (conversation→scene mapping) so game code can trigger scene changes.

---

## Unity Export (JSON)

**Target:** [Dialogue System for Unity](https://www.pixelcrushers.com/dialogue-system/) by PixelCrushers — the most widely used dialogue plugin in the Unity ecosystem. Its JSON import format is well-documented and stable.

**Key mappings:**
- Sheets → Actors (with custom fields from blocks)
- Flows → Conversations (with entries and links_to)
- Dialogue nodes → DialogueEntry with `actor_id`, `dialogue_text`, `sequence`; responses become child entries with `isGroup: false`
- Condition nodes → `conditionsString` field (structured rules → Lua syntax via transpiler)
- Instruction nodes → `userScript` field (structured assignments → Lua syntax via transpiler)
- Variables → Global variables table with typed initial values
- Hub nodes → Group entries (convergence points)
- Jump nodes → Cross-conversation links (link_to target hub entry)
- Subflow nodes → Cross-conversation references
- Scene nodes → Metadata entries (location info for screenplay integration)

```json
{
  "format": "unity_dialogue_system",
  "version": "1.0.0",
  "database": {
    "actors": [
      {
        "id": 1,
        "name": "Jaime",
        "shortcut": "mc.jaime",
        "fields": {
          "health": 100,
          "is_alive": true
        }
      }
    ],
    "conversations": [
      {
        "id": 1,
        "title": "Tavern Introduction",
        "shortcut": "act1.tavern-intro",
        "actor_id": 1,
        "conversant_id": 0,
        "entries": [
          {
            "id": 1,
            "is_root": true,
            "is_group": false,
            "actor_id": 1,
            "dialogue_text": "Hello, traveler!",
            "sequence": "",
            "conditions": "",
            "user_script": "",
            "links_to": [2, 3]
          }
        ]
      }
    ],
    "variables": [
      {
        "name": "mc.jaime.health",
        "type": "number",
        "initial_value": 100
        },
      {
        "name": "flags.met_jaime",
        "type": "boolean",
        "initial_value": false
      }
    ]
  },
  "localization": {
    "default_language": "en",
    "languages": ["en", "es", "de"],
    "strings": {
      "dialogue_1_text": {
        "en": "Hello, traveler!",
        "es": "Hola, viajero!",
        "de": "Hallo, Reisender!"
      }
    }
  }
}
```

---

## Godot Export (Resource/JSON)

**Target:** [Dialogic 2](https://github.com/dialogic-godot/dialogic) — the dominant dialogue addon for Godot 4. Alternative: generic JSON for custom parsers.

**Key mappings:**
- Sheets → Character resources with custom properties
- Flows → Timeline resources (Dialogic's core unit)
- Dialogue nodes → `[text]` events with character reference, responses become branching choices
- Condition nodes → `[if]`/`[elif]`/`[else]` events (structured rules → GDScript expressions via transpiler)
- Instruction nodes → `[code]` events (structured assignments → GDScript via transpiler)
- Hub/Jump nodes → Label/goto patterns within timelines
- Subflow nodes → Timeline references (Dialogic's `[call_node]`)
- Variables → Dialogic variable store or project autoload (dot notation → underscore: `mc.jaime.health` → `mc_jaime_health`)
- Asset paths → `res://` prefix convention

**Dual output:** Export both Dialogic-native `.dtl` timeline format AND generic JSON. Users choose which fits their project.

```json
{
  "format": "godot_dialogue",
  "version": "1.0.0",
  "characters": {
    "mc.jaime": {
      "name": "Jaime",
      "portrait": "res://assets/characters/jaime.png",
      "variables": {
        "health": 100,
        "is_alive": true
      }
    }
  },
  "dialogues": {
    "act1.tavern-intro": {
      "start": "entry_1",
      "nodes": {
        "entry_1": {
          "type": "dialogue",
          "character": "mc.jaime",
          "text": "Hello, traveler!",
          "responses": [
            {"text": "Hello!", "next": "node_3"},
            {"text": "Leave me alone.", "next": "node_4", "condition": "mc_player_mood == \"angry\""}
          ],
          "next": null
        },
        "node_3": {
          "type": "instruction",
          "code": "flags_met_jaime = true",
          "next": "node_5"
        },
        "node_4": {
          "type": "condition",
          "condition": "mc_jaime_health > 50",
          "true_next": "node_5",
          "false_next": "node_6"
        },
        "node_5": {
          "type": "hub",
          "hub_id": "after_greeting",
          "label": "",
          "next": "exit_1"
        }
      }
    }
  },
  "translations": {
    "en": {...},
    "es": {...}
  }
}
```

---

## Unreal Export (DataTable CSV + JSON)

**Target:** Unreal's native DataTable import. CSV files map directly to `UDataTable` assets, which is the standard way to feed data into Blueprints and C++.

**Key mappings:**
- Each node type generates rows in a typed CSV (DialogueLines, Conditions, Instructions)
- Flows → Conversation metadata JSON (graph structure, since CSV is flat)
- Sheets → Character DataTable + Variable DataTable
- Conditions → Blueprint-friendly string expressions (no Lua, no GDScript)
- Asset paths → `/Game/...` convention
- Localization → Unreal's StringTable CSV format (one per language)

**Multi-file output:** Unreal export produces a ZIP with multiple files, unlike Unity/Godot which are single JSON.

Unreal prefers DataTables (CSV) for dialogues and JSON for metadata.

**DialogueLines.csv:**
```csv
Name,Speaker,Text,TextKey,AudioCue,NextLine,Conditions
DLG_001,Jaime,"Hello, traveler!",dlg_001,/Game/Audio/VO/DLG_001,DLG_002,
DLG_002,Player,"Hello!",dlg_002,,DLG_003,
```

**DialogueMetadata.json:**
```json
{
  "conversations": {
    "act1.tavern-intro": {
      "start_line": "DLG_001",
      "participants": ["Jaime", "Player"],
      "tags": ["main_quest", "act1"]
    }
  },
  "characters": {...},
  "variables": {...}
}
```

---

## articy:draft Compatible Export

For teams migrating from or collaborating with articy:draft users. The mapping is natural since Storyarn's data model is inspired by articy:

**Key mappings:**
- Sheets → Entities (with TechnicalName = shortcut)
- Flows → FlowFragments
- Dialogue nodes → DialogueFragment (Speaker, Text, StageDirections); responses become child DialogueFragments
- Condition nodes → Condition pins on connections (structured rules → articy expression syntax)
- Instruction nodes → Instruction pins on connections (structured assignments → articy script syntax)
- Variables → GlobalVariables with Namespaces (sheet shortcut prefix = namespace)
- Connections → Connection elements with Source/Target GUIDs
- Hub nodes → articy Hubs (direct equivalent)
- Jump nodes → articy Jumps (direct equivalent)
- Subflow nodes → articy FlowFragment references
- Scene nodes → articy LocationSettings (int_ext, time_of_day)

**GUID strategy:** Generate deterministic GUIDs from Storyarn UUIDs so re-exports produce stable references.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<ArticyData>
  <Project Name="My RPG Project" Guid="...">
    <ExportSettings>
      <ExportVersion>1.0</ExportVersion>
      <StoryarnExportVersion>1.0.0</StoryarnExportVersion>
    </ExportSettings>

    <GlobalVariables>
      <Namespace Name="mc">
        <Variable Name="jaime.health" Type="int" Value="100"/>
        <Variable Name="jaime.is_alive" Type="bool" Value="true"/>
      </Namespace>
    </GlobalVariables>

    <Hierarchy>
      <Entity Type="Character" Id="..." TechnicalName="mc.jaime">
        <DisplayName>Jaime</DisplayName>
        <Properties>
          <Property Name="health" Type="int">100</Property>
        </Properties>
      </Entity>

      <FlowFragment Type="Dialogue" Id="..." TechnicalName="act1.tavern-intro">
        <DisplayName>Tavern Introduction</DisplayName>
        <Nodes>
          <DialogueFragment Id="..." Speaker="mc.jaime">
            <Text>Hello, traveler!</Text>
            <StageDirections/>
          </DialogueFragment>
        </Nodes>
        <Connections>
          <Connection Source="..." Target="..."/>
        </Connections>
      </FlowFragment>
    </Hierarchy>
  </Project>
</ArticyData>
```
