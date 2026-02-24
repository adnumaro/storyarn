# Phase 8: Export & Import System

> **Goal:** Enable full project export/import for game engine integration and backup/migration
>
> **Priority:** High - Core feature for game development workflow
>
> **Dependencies:** Phase 7.5 (Pages/Flows enhancements, Localization, World Builder)
>
> **Last Updated:** February 24, 2026

## Overview

This phase implements comprehensive export and import capabilities:
- Export to Storyarn JSON format (full fidelity)
- Export to game engine formats (Unity, Unreal, Godot)
- Export to articy:draft compatible format (interoperability)
- Import from Storyarn JSON
- Import from articy:draft XML
- Pre-export validation and health checks
- Selective export (specific flows, pages, locales)

**Design Philosophy:** Export should be lossless for Storyarn format and intelligently mapped for other formats. Validation catches issues before they become runtime bugs in the game.

---

## Architecture

### Serializer Behaviour (Plugin Pattern)

All export formats implement a common behaviour. Engine formats are **plugin-style** — each module self-registers, so adding a new engine never touches the core export logic.

```elixir
defmodule Storyarn.Exports.Serializer do
  @doc """
  Serialize project data to the target format. Receives streamed data from
  DataCollector and writes output to a file path. Returns :ok or error.
  """
  @callback serialize_to_file(
              data :: DataCollector.stream_data(),
              file_path :: Path.t(),
              options :: ExportOptions.t()
            ) :: :ok | {:error, term()}

  @doc """
  Serialize to in-memory binary. Used for small projects (sync export) and tests.
  """
  @callback serialize(project_data :: map(), options :: ExportOptions.t()) ::
              {:ok, output()} | {:error, term()}

  @doc "MIME content type for the exported file"
  @callback content_type() :: String.t()

  @doc "File extension (without dot)"
  @callback file_extension() :: String.t()

  @doc "Human-readable format name for UI"
  @callback format_label() :: String.t()

  @doc "Which content sections this format supports"
  @callback supported_sections() :: [:sheets | :flows | :scenes | :localization | :assets]

  @type output :: binary() | [{filename :: String.t(), content :: binary()}]
end
```

**Two modes:** `serialize/2` for tests and small sync exports, `serialize_to_file/3` for production streaming. Serializers write JSON/XML/CSV incrementally to a temp file, never accumulating the full output in memory.

### Serializer Registry

```elixir
defmodule Storyarn.Exports.SerializerRegistry do
  @serializers %{
    storyarn: Storyarn.Exports.Serializers.StoryarnJSON,
    unity:    Storyarn.Exports.Serializers.UnityJSON,
    godot:    Storyarn.Exports.Serializers.GodotJSON,
    unreal:   Storyarn.Exports.Serializers.UnrealCSV,
    articy:   Storyarn.Exports.Serializers.ArticyXML
  }

  def get(format), do: Map.fetch(@serializers, format)
  def list, do: @serializers
  def formats, do: Map.keys(@serializers)
end
```

**Adding a new engine:** Create a module implementing the `Serializer` behaviour, add one line to the registry. No other file changes needed.

### Data Collection Layer (Streaming)

The collector uses **`Repo.stream`** to read from the database in batched chunks instead of loading the entire project into memory. This means a 50k-node project uses the same ~20MB of memory as a 500-node project.

```elixir
defmodule Storyarn.Exports.DataCollector do
  @doc """
  Stream project data for export. Each section is a lazy Stream that reads
  from Postgres in batches of 500 rows. Serializers consume chunks and write
  to file incrementally — nothing accumulates in memory.
  """
  def stream(project_id, %ExportOptions{} = opts) do
    %{
      project: load_project(project_id),
      sheets: maybe_stream(:sheets, project_id, opts),
      flows: maybe_stream(:flows, project_id, opts),
      scenes: maybe_stream(:scenes, project_id, opts),
      localization: maybe_stream(:localization, project_id, opts),
      assets: maybe_stream(:assets, project_id, opts)
    }
  end

  defp maybe_stream(:flows, project_id, opts) do
    query = from(f in Flow,
      where: f.project_id == ^project_id and is_nil(f.deleted_at),
      preload: [nodes: :connections],
      order_by: [asc: f.position]
    )
    query = maybe_filter_ids(query, opts.flow_ids)
    fn -> Repo.stream(query, max_rows: 500) end
  end

  @doc """
  For small projects or operations that need random access (validation,
  conflict detection), load everything into memory. The caller decides.
  """
  def collect(project_id, %ExportOptions{} = opts) do
    %{
      project: load_project(project_id),
      sheets: maybe_load(:sheets, project_id, opts),
      flows: maybe_load(:flows, project_id, opts),
      scenes: maybe_load(:scenes, project_id, opts),
      localization: maybe_load(:localization, project_id, opts),
      assets: maybe_load(:assets, project_id, opts)
    }
  end
end
```

**Dual API:** `stream/2` for exports (constant memory), `collect/2` for validation and conflict detection (needs random access). The serializer behaviour supports both — see Serializer Behaviour above.

**Why this matters:** A project with 50k flow nodes, 10k sheets, and 20 languages would be ~200MB in memory. With streaming, the process stays at ~20MB regardless of project size. The BEAM scheduler preempts the process every ~4000 reductions, so even a 30-second export doesn't block other LiveView sessions.

### Expression Transpiler (Critical Complexity)

This is the **hardest piece** of the entire export system. Storyarn conditions and instructions use their own syntax (`{mc.jaime.health} > 50`, `{flags.met_jaime} = true`). Each game engine expects a different expression language.

```elixir
defmodule Storyarn.Exports.ExpressionTranspiler do
  @doc "Transpile a Storyarn expression to target engine syntax"
  @callback transpile_condition(expression :: String.t(), context :: map()) ::
              {:ok, String.t()} | {:error, term()}

  @callback transpile_instruction(code :: String.t(), context :: map()) ::
              {:ok, String.t()} | {:error, term()}
end
```

#### Transpilation targets

| Storyarn Expression                 | Unity (Lua)                                       | Godot (GDScript-like)                     | Unreal (Blueprint-friendly)               | articy:draft                               |
|-------------------------------------|---------------------------------------------------|-------------------------------------------|-------------------------------------------|--------------------------------------------|
| `{mc.jaime.health} > 50`           | `Variable["mc.jaime.health"] > 50`                | `mc_jaime_health > 50`                    | `mc.jaime.health > 50`                    | `mc.jaime.health > 50`                     |
| `{mc.jaime.class} == "warrior"`    | `Variable["mc.jaime.class"] == "warrior"`         | `mc_jaime_class == "warrior"`             | `mc.jaime.class == "warrior"`             | `mc.jaime.class == "warrior"`              |
| `{flags.met_jaime} = true`         | `Variable["flags.met_jaime"] = true`              | `flags_met_jaime = true`                  | `flags.met_jaime = true`                  | `flags.met_jaime = true`                   |
| `{mc.jaime.health} -= 10`          | `Variable["mc.jaime.health"] = Variable["mc.jaime.health"] - 10` | `mc_jaime_health -= 10`  | `mc.jaime.health -= 10`                  | `mc.jaime.health -= 10`                    |

#### Implementation approach

1. **Parse** Storyarn expressions into an AST (variable refs, operators, literals)
2. **Transform** the AST per target using engine-specific emitters
3. **Emit** target-language string from the transformed AST

```elixir
defmodule Storyarn.Exports.ExpressionTranspiler.Parser do
  @doc "Parse Storyarn expression into AST"
  def parse(expression) do
    # "{mc.jaime.health} > 50" →
    # {:comparison, {:var_ref, "mc.jaime.health"}, :gt, {:literal, 50}}
  end
end

defmodule Storyarn.Exports.ExpressionTranspiler.Unity do
  @behaviour Storyarn.Exports.ExpressionTranspiler

  def transpile_condition(expr, ctx) do
    with {:ok, ast} <- Parser.parse(expr) do
      {:ok, emit_lua(ast, ctx)}
    end
  end

  defp emit_lua({:comparison, {:var_ref, name}, op, {:literal, val}}, _ctx) do
    ~s(Variable["#{name}"] #{lua_op(op)} #{lua_literal(val)})
  end
end
```

The **condition builder** already stores structured data (`rules` with `sheet`, `variable`, `operator`, `value`), so for builder-mode conditions we can skip parsing and go straight from structured data → target syntax. The parser is only needed for **code-mode** free-text expressions.

---

## Export Formats

### 8.1 Storyarn JSON Format (Native)

Full-fidelity export that preserves all Storyarn data for backup, migration, or external processing.

#### Top-Level Structure

```json
{
  "storyarn_version": "1.0.0",
  "export_version": "1.0.0",
  "exported_at": "2026-02-02T15:30:00Z",
  "project": {
    "id": "uuid",
    "name": "My RPG Project",
    "slug": "my-rpg-project",
    "description": "An epic adventure..."
  },
  "pages": [...],
  "flows": [...],
  "maps": [...],
  "localization": {...},
  "assets": {...},
  "metadata": {...}
}
```

#### Pages Section

```json
{
  "pages": [
    {
      "id": "uuid",
      "shortcut": "mc.jaime",
      "name": "Jaime",
      "path": "Characters/Main Characters/Jaime",
      "parent_id": "uuid-or-null",
      "position": 0,
      "avatar_asset_id": "uuid-or-null",
      "banner_asset_id": "uuid-or-null",
      "blocks": [
        {
          "id": "uuid",
          "type": "text",
          "position": 0,
          "config": {
            "label": "Name"
          },
          "value": {
            "content": "Jaime the Brave"
          },
          "is_variable": true,
          "variable_name": "name"
        },
        {
          "id": "uuid",
          "type": "number",
          "position": 1,
          "config": {
            "label": "Health",
            "min": 0,
            "max": 100
          },
          "value": {
            "content": 100
          },
          "is_variable": true,
          "variable_name": "health"
        },
        {
          "id": "uuid",
          "type": "boolean",
          "position": 2,
          "config": {
            "label": "Is Alive",
            "mode": "two_state"
          },
          "value": {
            "content": true
          },
          "is_variable": true,
          "variable_name": "is_alive"
        },
        {
          "id": "uuid",
          "type": "reference",
          "position": 3,
          "config": {
            "label": "Current Location"
          },
          "value": {
            "target_type": "page",
            "target_id": "uuid",
            "target_shortcut": "loc.tavern"
          },
          "is_variable": false
        }
      ]
    }
  ]
}
```

#### Flows Section

```json
{
  "flows": [
    {
      "id": "uuid",
      "shortcut": "act1.tavern-intro",
      "name": "Tavern Introduction",
      "path": "Act 1/Tavern/Introduction",
      "parent_id": "uuid-or-null",
      "position": 0,
      "is_folder": false,
      "entry_node_id": "uuid",
      "exit_node_ids": ["uuid", "uuid"],
      "nodes": [
        {
          "id": "uuid",
          "type": "entry",
          "position_x": 100,
          "position_y": 300,
          "data": {}
        },
        {
          "id": "uuid",
          "type": "dialogue",
          "position_x": 300,
          "position_y": 300,
          "data": {
            "speaker_type": "page",
            "speaker_id": "uuid",
            "speaker_shortcut": "mc.jaime",
            "text": "Hello, traveler!",
            "text_key": "dlg_001"
          }
        },
        {
          "id": "uuid",
          "type": "choice",
          "position_x": 500,
          "position_y": 300,
          "data": {
            "prompt": "How do you respond?",
            "prompt_key": "choice_001",
            "options": [
              {
                "id": "opt_1",
                "text": "Hello!",
                "text_key": "choice_001_opt_1",
                "condition": null
              },
              {
                "id": "opt_2",
                "text": "Leave me alone.",
                "text_key": "choice_001_opt_2",
                "condition": "#mc.player.mood == 'angry'"
              }
            ]
          }
        },
        {
          "id": "uuid",
          "type": "condition",
          "position_x": 700,
          "position_y": 200,
          "data": {
            "expression": "#mc.jaime.health > 50"
          }
        },
        {
          "id": "uuid",
          "type": "instruction",
          "position_x": 700,
          "position_y": 400,
          "data": {
            "code": "#mc.jaime.health -= 10;\n#flags.met_jaime = true;"
          }
        },
        {
          "id": "uuid",
          "type": "flow_jump",
          "position_x": 900,
          "position_y": 300,
          "data": {
            "target_flow_id": "uuid",
            "target_flow_shortcut": "act1.tavern-fight"
          }
        },
        {
          "id": "uuid",
          "type": "event",
          "position_x": 500,
          "position_y": 500,
          "data": {
            "event_id": "tavern_music_starts",
            "description": "Background music changes to tavern theme",
            "delay_type": "immediate",
            "tags": ["audio", "ambient"]
          }
        },
        {
          "id": "uuid",
          "type": "hub",
          "position_x": 1100,
          "position_y": 300,
          "data": {
            "hub_id": "after_greeting",
            "color": "blue"
          }
        },
        {
          "id": "uuid",
          "type": "exit",
          "position_x": 1300,
          "position_y": 300,
          "data": {
            "label": "success"
          }
        }
      ],
      "connections": [
        {
          "id": "uuid",
          "source_node_id": "uuid",
          "source_handle": "output",
          "target_node_id": "uuid",
          "target_handle": "input",
          "label": null,
          "condition": null
        }
      ]
    }
  ]
}
```

#### Maps Section

```json
{
  "maps": [
    {
      "id": "uuid",
      "shortcut": "maps.world",
      "name": "World Map",
      "path": "World Map",
      "parent_scene_id": null,
      "background_asset_id": "uuid",
      "width": 2048,
      "height": 1536,
      "default_zoom": 1.0,
      "default_center_x": 50,
      "default_center_y": 50,
      "layers": [
        {
          "id": "uuid",
          "name": "Default",
          "is_default": true,
          "trigger_event_id": null,
          "position": 0
        },
        {
          "id": "uuid",
          "name": "After the War",
          "is_default": false,
          "trigger_event_id": "war_ends",
          "position": 1
        }
      ],
      "pins": [
        {
          "id": "uuid",
          "layer_id": null,
          "position_x": 45.5,
          "position_y": 30.0,
          "pin_type": "location",
          "icon": "castle",
          "color": "gold",
          "label": "Capital City",
          "target_type": "page",
          "target_id": "uuid",
          "target_shortcut": "loc.capital",
          "tooltip": "The heart of the kingdom",
          "size": "lg"
        }
      ],
      "connections": [
        {
          "id": "uuid",
          "from_pin_id": "uuid",
          "to_pin_id": "uuid",
          "line_style": "dashed",
          "color": "brown",
          "label": "3 days travel",
          "bidirectional": true
        }
      ]
    }
  ]
}
```

#### Localization Section

```json
{
  "localization": {
    "source_language": "en",
    "languages": [
      {"locale_code": "en", "name": "English", "is_source": true},
      {"locale_code": "es", "name": "Spanish", "is_source": false},
      {"locale_code": "de", "name": "German", "is_source": false}
    ],
    "strings": {
      "dlg_001": {
        "source_type": "flow_node",
        "source_id": "uuid",
        "character_shortcut": "mc.jaime",
        "translations": {
          "en": {
            "text": "Hello, traveler!",
            "status": "final",
            "vo_status": "recorded",
            "vo_asset_id": "uuid"
          },
          "es": {
            "text": "¡Hola, viajero!",
            "status": "final",
            "vo_status": "needed",
            "vo_asset_id": null
          },
          "de": {
            "text": "Hallo, Reisender!",
            "status": "review",
            "vo_status": "none",
            "vo_asset_id": null
          }
        }
      }
    },
    "glossary": [
      {
        "term": "Eldoria",
        "translations": {
          "en": "Eldoria",
          "es": "Eldoria",
          "de": "Eldoria"
        },
        "do_not_translate": true,
        "context": "Name of the kingdom"
      }
    ]
  }
}
```

#### Assets Section

```json
{
  "assets": {
    "mode": "references",
    "base_url": "https://storage.example.com/project-id/",
    "items": [
      {
        "id": "uuid",
        "filename": "jaime_portrait.png",
        "content_type": "image/png",
        "size": 245760,
        "key": "assets/jaime_portrait.png",
        "url": "https://storage.example.com/project-id/assets/jaime_portrait.png",
        "checksum": "sha256:abc123..."
      }
    ]
  }
}
```

**Asset Export Modes:**
- `references` - URLs only (default, smaller file)
- `embedded` - Base64 encoded (self-contained, larger file)
- `bundled` - Separate ZIP with assets folder

#### Metadata Section

```json
{
  "metadata": {
    "statistics": {
      "page_count": 145,
      "flow_count": 32,
      "node_count": 856,
      "connection_count": 1024,
      "map_count": 5,
      "asset_count": 89,
      "word_count": {
        "total": 45000,
        "by_language": {
          "en": 45000,
          "es": 42000,
          "de": 38000
        }
      },
      "localization_progress": {
        "es": 93,
        "de": 84
      }
    },
    "validation": {
      "status": "passed",
      "warnings": [
        {
          "type": "orphan_page",
          "message": "Page 'Old Character' has no references",
          "entity_id": "uuid"
        }
      ],
      "errors": []
    }
  }
}
```

---

### 8.2 Game Engine Formats

#### Design Principles for Engine Exports

- **Target real plugins, not abstract formats.** Each engine has a dominant dialogue plugin. Export compatible with it and you cover 80%+ of users.
- **Expressions are the hard part.** The JSON/XML structure is mechanical; translating conditions and instructions to each engine's scripting language is where 80% of the complexity lives (see Expression Transpiler above).
- **Provide escape hatches.** Include raw Storyarn expressions as comments/metadata alongside transpiled versions, so users can debug mismatches.
- **Asset paths use engine conventions.** Unity: `Assets/...`, Godot: `res://...`, Unreal: `/Game/...`

#### Unity Export (JSON)

**Target:** [Dialogue System for Unity](https://www.pixelcrushers.com/dialogue-system/) by PixelCrushers — the most widely used dialogue plugin in the Unity ecosystem. Its JSON import format is well-documented and stable.

**Key mappings:**
- Sheets → Actors (with custom fields from blocks)
- Flows → Conversations (with entries and links_to)
- Dialogue nodes → DialogueEntry with `actor_id`, `dialogue_text`, `sequence`
- Condition nodes → `conditionsString` field (Lua syntax via transpiler)
- Instruction nodes → `userScript` field (Lua syntax via transpiler)
- Variables → Global variables table with typed initial values
- Hubs/Jumps → Group entries with cross-conversation links

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
        "es": "¡Hola, viajero!",
        "de": "Hallo, Reisender!"
      }
    }
  }
}
```

#### Godot Export (Resource/JSON)

**Target:** [Dialogic 2](https://github.com/dialogic-godot/dialogic) — the dominant dialogue addon for Godot 4. Alternative: generic JSON for custom parsers.

**Key mappings:**
- Sheets → Character resources with custom properties
- Flows → Timeline resources (Dialogic's core unit)
- Dialogue nodes → `[text]` events with character reference
- Condition nodes → `[if]`/`[elif]`/`[else]` events (GDScript expressions via transpiler)
- Instruction nodes → `[code]` events
- Variables → Dialogic variable store or project autoload
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
          "next": "choice_1"
        },
        "choice_1": {
          "type": "choice",
          "text": "How do you respond?",
          "options": [
            {"text": "Hello!", "next": "response_1"},
            {"text": "Leave me alone.", "next": "response_2", "condition": "mc.player.mood == 'angry'"}
          ]
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

#### Unreal Export (DataTable CSV + JSON)

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

### 8.3 articy:draft Compatible Export

For teams migrating from or collaborating with articy:draft users. The mapping is natural since Storyarn's data model is inspired by articy:

**Key mappings:**
- Sheets → Entities (with TechnicalName = shortcut)
- Flows → FlowFragments
- Dialogue nodes → DialogueFragment (Speaker, Text, StageDirections)
- Condition nodes → Condition pins on connections
- Variables → GlobalVariables with Namespaces (sheet shortcut prefix = namespace)
- Connections → Connection elements with Source/Target GUIDs
- Hub nodes → articy Hubs (direct equivalent)
- Jump nodes → articy Jumps (direct equivalent)

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

---

## Implementation Tasks

### 8.1 Export Infrastructure

#### 8.1.1 Export Context Module
- [ ] Create `Storyarn.Exports` context (facade pattern)
- [ ] `Exports.export_project/2` - Main export function
- [ ] `Exports.export_flows/2` - Export specific flows
- [ ] `Exports.export_sheets/2` - Export specific sheets
- [ ] `Exports.get_export_options/1` - Get available options

#### 8.1.2 Export Options Schema
```elixir
%ExportOptions{
  format: :storyarn | :unity | :godot | :unreal | :articy,
  version: "1.0.0",
  include_sheets: true,
  include_flows: true,
  include_scenes: true,
  include_localization: true,
  include_assets: :references | :embedded | :bundled,
  languages: ["en", "es"] | :all,
  flow_ids: [uuid] | :all,
  sheet_ids: [uuid] | :all,
  validate_before_export: true,
  pretty_print: true
}
```

#### 8.1.3 Serializer Behaviour + Registry
- [ ] Define `Storyarn.Exports.Serializer` behaviour (see Architecture section)
- [ ] Create `Storyarn.Exports.SerializerRegistry` module
- [ ] Serializer implementations (each implements the behaviour):
  - [ ] `Exports.Serializers.StoryarnJSON` - Native format
  - [ ] `Exports.Serializers.UnityJSON` - Dialogue System for Unity format
  - [ ] `Exports.Serializers.GodotJSON` - Dialogic 2 / generic format
  - [ ] `Exports.Serializers.UnrealCSV` - DataTable CSV + metadata JSON
  - [ ] `Exports.Serializers.ArticyXML` - articy:draft XML format

#### 8.1.4 Data Collector (Dual Mode)
- [ ] Create `Storyarn.Exports.DataCollector` module
- [ ] `stream/2` - Streaming mode via `Repo.stream` (constant memory, for production exports)
- [ ] `collect/2` - In-memory mode (for validation, conflict detection, tests)
- [ ] Batched preloads (500 rows per batch) to avoid N+1 without loading everything
- [ ] Respect `ExportOptions` filters (selected flows, sheets, languages)
- [ ] Entity counting for progress calculation (`count_entities/2`)

#### 8.1.5 Expression Transpiler
- [ ] Create `Storyarn.Exports.ExpressionTranspiler` behaviour
- [ ] `ExpressionTranspiler.Parser` - Parse Storyarn expressions → AST
- [ ] Structured condition fast-path (builder-mode data → target syntax without parsing)
- [ ] Engine-specific emitters:
  - [ ] `ExpressionTranspiler.Unity` - Emit Lua syntax for Dialogue System
  - [ ] `ExpressionTranspiler.Godot` - Emit GDScript-like syntax for Dialogic
  - [ ] `ExpressionTranspiler.Unreal` - Emit Blueprint-friendly syntax
  - [ ] `ExpressionTranspiler.Articy` - Emit articy:draft expression syntax
- [ ] Include raw Storyarn expression as metadata/comment alongside transpiled output
- [ ] Validation: report untranspilable expressions as export warnings

---

### 8.2 Pre-Export Validation

#### 8.2.1 Validation Rules

| Rule                   | Severity   | Description                                 |
|------------------------|------------|---------------------------------------------|
| `orphan_nodes`         | Warning    | Nodes not connected to flow graph           |
| `broken_references`    | Error      | References to deleted pages/flows           |
| `missing_entry`        | Error      | Flow without Entry node                     |
| `unreachable_nodes`    | Warning    | Nodes not reachable from Entry              |
| `missing_translations` | Warning    | Untranslated strings for selected languages |
| `circular_jumps`       | Warning    | Flow A → B → A cycles (may be intentional)  |
| `empty_dialogue`       | Warning    | Dialogue nodes with no text                 |
| `invalid_conditions`   | Error      | Unparseable condition expressions           |
| `invalid_instructions` | Error      | Unparseable instruction code                |
| `missing_speakers`     | Warning    | Dialogue without speaker                    |
| `orphan_pages`         | Info       | Pages with no references                    |

#### 8.2.2 Validation Implementation
- [ ] Create `Exports.Validator` module
- [ ] `Validator.validate_project/2` - Run all validations
- [ ] `Validator.validate_flows/2` - Flow-specific validations
- [ ] `Validator.validate_pages/2` - Page-specific validations
- [ ] `Validator.validate_localization/2` - Translation validations
- [ ] Return structured results with severity, message, entity references

#### 8.2.3 Validation Results Schema
```elixir
%ValidationResult{
  status: :passed | :warnings | :errors,
  errors: [
    %{
      rule: :broken_reference,
      severity: :error,
      message: "Flow 'Tavern Intro' references deleted page 'Old NPC'",
      source_type: :flow_node,
      source_id: "uuid",
      target_type: :page,
      target_id: "uuid"
    }
  ],
  warnings: [...],
  info: [...],
  statistics: %{
    checked_flows: 32,
    checked_pages: 145,
    checked_nodes: 856
  }
}
```

---

### 8.3 Export UI

#### 8.3.1 Export Modal

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ EXPORT PROJECT                                                    [✕ Close] │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│ Format                                                                      │
│ ┌─────────────────────────────────────────────────────────────────────────┐ │
│ │ ● Storyarn JSON (full backup, recommended)                              │ │
│ │ ○ Unity (Dialogue System compatible)                                    │ │
│ │ ○ Godot (Dialogue Manager compatible)                                   │ │
│ │ ○ Unreal (DataTable CSV)                                                │ │
│ │ ○ articy:draft XML (interoperability)                                   │ │
│ └─────────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│ Content                                                                     │
│ ☑ Pages (145 pages, 423 blocks)                                            │
│ ☑ Flows (32 flows, 856 nodes)                                              │
│ ☑ Maps (5 maps, 89 pins)                                                   │
│ ☑ Localization (3 languages)                                               │
│                                                                             │
│ Languages (for localization export)                                         │
│ ☑ English (source)    ☑ Spanish (93%)    ☑ German (84%)                   │
│                                                                             │
│ Assets                                                                      │
│ ● References only (URLs in JSON)                                           │
│ ○ Embedded (Base64 in JSON - larger file)                                  │
│ ○ Bundled (ZIP with assets folder)                                         │
│                                                                             │
│ Options                                                                     │
│ ☑ Validate before export                                                   │
│ ☑ Pretty print JSON                                                        │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ VALIDATION                                              [Run Validation]    │
│ ┌─────────────────────────────────────────────────────────────────────────┐ │
│ │ ✅ Passed with 3 warnings                                               │ │
│ │                                                                         │ │
│ │ ⚠️ 2 orphan pages with no references                                    │ │
│ │ ⚠️ 1 dialogue node without speaker                                      │ │
│ │ ⚠️ 5 untranslated strings in German                                     │ │
│ │                                                                         │ │
│ │ [View Details]                                                          │ │
│ └─────────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│                                            [Cancel] [Export to JSON ↓]      │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### 8.3.2 Implementation Tasks
- [ ] LiveView: `ExportLive.Index` - Export modal
- [ ] Format selector with descriptions
- [ ] Content checkboxes with counts
- [ ] Language selector (multi-select)
- [ ] Asset mode selector
- [ ] Validation panel with results
- [ ] Real-time progress bar (PubSub subscription for async exports)
- [ ] Download trigger (browser download for sync, download link for async)
- [ ] Cancel button for in-progress async exports

---

### 8.4 Background Processing

#### 8.4.1 Oban Infrastructure
- [ ] Configure `:exports` queue (concurrency: 3) and `:imports` queue (concurrency: 2)
- [ ] Configure `:maintenance` queue (concurrency: 1) for cleanup cron
- [ ] Create `Exports.ExportWorker` (Oban worker with progress broadcast)
- [ ] Sync/async threshold logic (`@sync_threshold 1000` entities)
- [ ] PubSub topic: `"user:{user_id}:exports"` for progress + completion events

#### 8.4.2 Lifecycle Management
- [ ] `Exports.CleanupWorker` - Oban cron job to delete exports older than 24h
- [ ] Retry with checkpoint — resume from `last_entity_id` on crash recovery
- [ ] Cancellation via `Oban.cancel_job/1` with status update to `:cancelled`
- [ ] Temp file cleanup on success, failure, and cancellation (`Briefly` for temp paths)

---

### 8.4 Import System

#### 8.4.1 Import Workflow

1. **Upload File** - Select JSON/XML file
2. **Parse & Validate** - Check format, detect version
3. **Preview** - Show what will be imported
4. **Conflict Detection** - Identify existing entities
5. **Conflict Resolution** - Skip, overwrite, or merge
6. **Import** - Execute with transaction
7. **Report** - Show results

#### 8.4.2 Import UI

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ IMPORT PROJECT                                                    [✕ Close] │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│ File                                                                        │
│ ┌─────────────────────────────────────────────────────────────────────────┐ │
│ │ 📄 my-project-backup.json                      [Choose Different File]  │ │
│ │ Format: Storyarn JSON v1.0.0                                            │ │
│ │ Exported: Feb 1, 2026 at 3:30 PM                                        │ │
│ └─────────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│ Preview                                                                     │
│ ┌─────────────────────────────────────────────────────────────────────────┐ │
│ │ 📄 Pages: 145 (12 new, 133 existing)                                    │ │
│ │ 🔀 Flows: 32 (5 new, 27 existing)                                       │ │
│ │ 🗺️ Maps: 5 (0 new, 5 existing)                                          │ │
│ │ 🌍 Languages: 3 (0 new)                                                 │ │
│ │ 📁 Assets: 89 (15 new, 74 existing)                                     │ │
│ └─────────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│ Conflict Resolution                                                         │
│ When an entity already exists:                                              │
│ ○ Skip (keep existing)                                                      │
│ ● Overwrite (replace with imported)                                         │
│ ○ Merge (combine, keep newer timestamps)                                    │
│                                                                             │
│ ⚠️ 27 flows will be overwritten                                            │
│ ⚠️ 133 pages will be overwritten                                           │
│                                                                             │
│                                            [Cancel] [Import 292 entities]   │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### 8.4.3 Import Implementation
- [ ] Create `Storyarn.Imports` context
- [ ] `Imports.parse_file/1` - Parse and detect format
- [ ] `Imports.preview/2` - Generate import preview
- [ ] `Imports.detect_conflicts/2` - Find existing entities
- [ ] `Imports.execute/3` - Run import with options
- [ ] Parser modules per format:
  - [ ] `Imports.Parsers.StoryarnJSON`
  - [ ] `Imports.Parsers.ArticyXML`
- [ ] Transaction wrapper for atomic import
- [ ] Import report generation

---

### 8.5 API Endpoints

#### Export Endpoints

```elixir
# Start export job (async for large projects)
POST /api/projects/:id/exports
Body: { format: "storyarn", options: {...} }
Response: { job_id: "uuid", status: "processing" }

# Check export status
GET /api/projects/:id/exports/:job_id
Response: { status: "completed", download_url: "..." }

# Download export (direct)
GET /api/projects/:id/exports/:job_id/download
Response: File download

# Quick export (sync, small projects)
GET /api/projects/:id/export
Query: ?format=storyarn&include_assets=references
Response: JSON file download
```

#### Import Endpoints

```elixir
# Upload for import
POST /api/projects/:id/imports
Body: multipart/form-data with file
Response: { import_id: "uuid", preview: {...} }

# Execute import
POST /api/projects/:id/imports/:import_id/execute
Body: { conflict_resolution: "overwrite" }
Response: { status: "completed", report: {...} }
```

---

## Background Processing & Scalability

### Why BEAM is the right tool here (not Rust, not a sidecar)

Export is **I/O bound** — the bottleneck is reading from Postgres and writing to disk/S3, not CPU. The BEAM VM was designed for exactly this:

- **Preemptive scheduling:** Every ~4000 reductions (~1ms of work), the BEAM pauses the export process and gives CPU to other processes. A 30-second export runs alongside 500 LiveView connections without any of them noticing.
- **Isolated memory:** Each BEAM process has its own heap. An export process that uses 50MB doesn't affect other processes. If it crashes, only that process dies — the supervisor restarts it.
- **No thread contention:** BEAM processes don't share memory. No mutexes, no deadlocks, no race conditions between an export job and a LiveView event handler.

A Rust NIF would block the BEAM scheduler (NIFs run outside preemption), require manual dirty scheduler management, and force serialization/deserialization across the Elixir↔Rust boundary — often slower than staying in Elixir for I/O-bound work.

### Oban Configuration

Dedicated queue with controlled concurrency. Export jobs can run for minutes without affecting any other queue.

```elixir
# config/config.exs
config :storyarn, Oban,
  repo: Storyarn.Repo,
  queues: [
    default: 10,          # Normal jobs (emails, notifications)
    exports: 3,           # Max 3 concurrent exports (controlled by RAM, not CPU)
    imports: 2,           # Max 2 concurrent imports (heavy DB writes)
    maintenance: 1        # Cleanup old export files
  ]
```

**Why limit to 3 exports?** Not because BEAM can't handle more — it can handle thousands. The limit is practical: each export holds a Postgres transaction open (for `Repo.stream` consistency) and writes to disk. 3 concurrent exports + normal app traffic is a safe default. Tunable per deployment.

### Export Worker

```elixir
defmodule Storyarn.Exports.ExportWorker do
  use Oban.Worker,
    queue: :exports,
    max_attempts: 2,
    priority: 1

  alias Storyarn.Exports.{DataCollector, SerializerRegistry, Validator}

  @impl Oban.Worker
  def perform(%Job{args: %{"project_id" => project_id, "format" => format,
                            "options" => options, "user_id" => user_id,
                            "export_job_id" => export_job_id}}) do
    opts = ExportOptions.from_map(options)
    serializer = SerializerRegistry.get!(String.to_existing_atom(format))

    # 1. Count entities for progress tracking
    total = count_entities(project_id, opts)
    update_job_status(export_job_id, :processing, %{total: total})

    # 2. Optional pre-validation
    if opts.validate_before_export do
      case Validator.validate_project(project_id, opts) do
        %{status: :errors} = result ->
          update_job_status(export_job_id, :failed, %{validation: result})
          {:error, :validation_failed}
        result ->
          update_job_status(export_job_id, :processing, %{validation: result})
          do_export(project_id, opts, serializer, export_job_id, user_id, total)
      end
    else
      do_export(project_id, opts, serializer, export_job_id, user_id, total)
    end
  end

  defp do_export(project_id, opts, serializer, export_job_id, user_id, total) do
    tmp_path = Briefly.create!(extname: ".#{serializer.file_extension()}")

    # 3. Stream from DB → serialize to file (constant memory)
    Repo.transaction(fn ->
      data = DataCollector.stream(project_id, opts)

      serializer.serialize_to_file(data, tmp_path, opts,
        progress_fn: fn current ->
          if rem(current, 50) == 0 do
            percent = min(trunc(current / total * 100), 99)
            update_job_status(export_job_id, :processing, %{progress: percent})
            broadcast_progress(user_id, project_id, percent)
          end
        end
      )
    end)

    # 4. Upload result file to storage
    file_key = "exports/#{project_id}/#{export_job_id}.#{serializer.file_extension()}"
    file_size = File.stat!(tmp_path).size
    Assets.Storage.adapter().upload(file_key, File.read!(tmp_path), serializer.content_type())
    File.rm(tmp_path)

    # 5. Mark complete and notify user
    update_job_status(export_job_id, :completed, %{
      progress: 100,
      file_key: file_key,
      file_size: file_size
    })
    broadcast_complete(user_id, project_id, export_job_id)

    :ok
  end

  defp broadcast_progress(user_id, project_id, percent) do
    Phoenix.PubSub.broadcast(Storyarn.PubSub,
      "user:#{user_id}:exports",
      {:export_progress, project_id, percent})
  end

  defp broadcast_complete(user_id, project_id, export_job_id) do
    Phoenix.PubSub.broadcast(Storyarn.PubSub,
      "user:#{user_id}:exports",
      {:export_complete, project_id, export_job_id})
  end
end
```

### LiveView Integration (Real-Time Progress)

The user sees a live progress bar while the export runs in background.

```elixir
defmodule StoryarnWeb.ExportLive.Index do
  use StoryarnWeb, :live_view

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Storyarn.PubSub,
        "user:#{socket.assigns.current_scope.user.id}:exports")
    end
    {:ok, assign(socket, export_status: :idle, export_progress: 0)}
  end

  def handle_event("start_export", %{"format" => format} = params, socket) do
    # Create export job record
    {:ok, export_job} = Exports.create_export_job(socket.assigns.project, %{
      format: format,
      options: build_options(params),
      user_id: socket.assigns.current_scope.user.id
    })

    # Enqueue Oban job (returns immediately)
    %{project_id: socket.assigns.project.id, format: format,
      options: build_options(params),
      user_id: socket.assigns.current_scope.user.id,
      export_job_id: export_job.id}
    |> Storyarn.Exports.ExportWorker.new()
    |> Oban.insert()

    {:noreply, assign(socket, export_status: :processing, export_progress: 0)}
  end

  # Real-time progress updates via PubSub
  def handle_info({:export_progress, _project_id, percent}, socket) do
    {:noreply, assign(socket, export_progress: percent)}
  end

  def handle_info({:export_complete, _project_id, export_job_id}, socket) do
    {:noreply, assign(socket,
      export_status: :complete,
      export_progress: 100,
      download_job_id: export_job_id)}
  end
end
```

### Sync vs Async Decision

Not every export needs Oban. Small projects export instantly.

```elixir
defmodule Storyarn.Exports do
  @sync_threshold 1000  # entities

  def export_project(project, opts) do
    total = count_entities(project.id, opts)

    if total <= @sync_threshold do
      # Small project: sync export, return file directly
      export_sync(project, opts)
    else
      # Large project: enqueue Oban job, return job reference
      export_async(project, opts)
    end
  end

  defp export_sync(project, opts) do
    data = DataCollector.collect(project.id, opts)
    serializer = SerializerRegistry.get!(opts.format)
    serializer.serialize(data, opts)
  end

  defp export_async(project, opts) do
    {:ok, job} = create_export_job(project, opts)
    %{project_id: project.id, format: opts.format,
      options: opts, export_job_id: job.id}
    |> ExportWorker.new()
    |> Oban.insert()
    {:async, job}
  end
end
```

### Cancellation

Users can cancel an in-progress export. BEAM makes this trivial — kill the process, the supervisor handles cleanup.

```elixir
def handle_event("cancel_export", %{"job_id" => job_id}, socket) do
  case Oban.cancel_job(job_id) do
    :ok ->
      Exports.update_job_status(job_id, :cancelled)
      {:noreply, assign(socket, export_status: :idle)}
    _ ->
      {:noreply, socket}
  end
end
```

### Automatic Cleanup

Old export files are deleted after 24 hours via a scheduled Oban cron job.

```elixir
# config/config.exs
config :storyarn, Oban,
  plugins: [
    {Oban.Plugins.Cron, crontab: [
      {"0 */6 * * *", Storyarn.Exports.CleanupWorker}  # Every 6 hours
    ]}
  ]

# The worker
defmodule Storyarn.Exports.CleanupWorker do
  use Oban.Worker, queue: :maintenance

  @impl Oban.Worker
  def perform(_job) do
    Exports.cleanup_expired_exports(hours: 24)
    :ok
  end
end
```

### Retry with Checkpoint (Crash Recovery)

If a node restarts mid-export (deploy, OOM), the job retries. To avoid reprocessing from scratch, the worker can checkpoint progress.

```elixir
# On retry, check if partial file exists
def perform(%Job{attempt: attempt, args: args}) when attempt > 1 do
  case check_partial_export(args["export_job_id"]) do
    {:partial, last_entity_id, tmp_path} ->
      # Resume from checkpoint
      resume_export(args, last_entity_id, tmp_path)
    nil ->
      # No checkpoint, start fresh
      do_export(args)
  end
end
```

### Performance Characteristics

| Project Size   | Entities | Memory    | Time (est.) | Mode  |
|----------------|----------|-----------|-------------|-------|
| Small          | <500     | ~5MB      | <2s         | Sync  |
| Medium         | 500-5k   | ~20MB     | 2-10s       | Async |
| Large          | 5k-50k   | ~20MB*    | 10-60s      | Async |
| Massive        | 50k+     | ~20MB*    | 1-5min      | Async |

*Streaming keeps memory constant regardless of project size. The bottleneck is Postgres query time, not serialization.

---

## Database Changes

### Migration: Export Jobs (for async exports)

```elixir
create table(:export_jobs) do
  add :project_id, references(:projects, on_delete: :delete_all), null: false
  add :user_id, references(:users, on_delete: :nilify_all), null: false
  add :format, :string, null: false
  add :options, :map, default: %{}
  add :status, :string, default: "pending"  # pending, processing, completed, failed
  add :progress, :integer, default: 0       # 0-100
  add :file_key, :string                    # Storage key for result file
  add :file_size, :integer
  add :error_message, :text
  add :started_at, :utc_datetime
  add :completed_at, :utc_datetime

  timestamps()
end

create index(:export_jobs, [:project_id, :status])
create index(:export_jobs, [:user_id])
```

---

## Implementation Order

**Principle:** Native JSON round-trip (export → import) must be lossless before touching any engine format. Async with Oban is a performance optimization, not a blocker — it goes last.

### Phase A: Foundation + Native Round-Trip (Tasks 1-8)

| Order | Task                                    | Dependencies   | Testable Outcome                            |
|-------|-----------------------------------------|----------------|---------------------------------------------|
| 1     | Export context + options schema         | None           | ExportOptions struct validates correctly     |
| 2     | Serializer behaviour + registry         | Task 1         | Registry resolves format → module            |
| 3     | Data collector                          | Task 1         | Loads full project data in single pass       |
| 4     | Storyarn JSON serializer (all sections) | Tasks 2-3      | Full project exports to JSON                 |
| 5     | Import parser (Storyarn JSON)           | None           | Can parse exported JSON back                 |
| 6     | Import round-trip test                  | Tasks 4-5      | **export → import = identical project data** |
| 7     | Pre-export validation                   | Task 4         | Catches broken refs, orphans, etc.           |
| 8     | Import preview + conflict detection     | Task 5         | Shows diff before executing import           |

### Phase B: Expression Transpiler (Tasks 9-10)

| Order | Task                                        | Dependencies | Testable Outcome                            |
|-------|---------------------------------------------|--------------|---------------------------------------------|
| 9     | Expression parser (Storyarn syntax → AST)   | None         | Parses all expression patterns               |
| 10    | Structured condition fast-path              | None         | Builder-mode conditions bypass parser        |

### Phase C: Engine Serializers (Tasks 11-14)

| Order | Task                           | Dependencies  | Testable Outcome                                  |
|-------|--------------------------------|---------------|----------------------------------------------------|
| 11    | Unity serializer + Lua emitter | Tasks 2-3, 10 | Produces Dialogue System for Unity compatible JSON |
| 12    | Godot serializer + GDScript emitter | Tasks 2-3, 10 | Produces Dialogic 2 compatible JSON           |
| 13    | Unreal serializer + CSV emitter    | Tasks 2-3, 10 | Produces DataTable CSVs + metadata JSON        |
| 14    | articy:draft XML serializer        | Tasks 2-3, 10 | Produces valid articy:draft XML                |

### Phase D: UI + UX (Tasks 15-18)

| Order | Task                       | Dependencies  | Testable Outcome                   |
|-------|----------------------------|---------------|------------------------------------|
| 15    | Export UI (modal)          | Tasks 4, 7    | Format selection, validation panel |
| 16    | Export download             | Task 15       | Browser file download works        |
| 17    | Import execution + UI      | Tasks 6, 8    | Full import flow with conflicts    |
| 18    | Import from articy:draft   | None          | Can parse articy XML               |

### Phase E: Scale + API (Tasks 19-22)

| Order | Task                                    | Dependencies | Testable Outcome                             |
|-------|-----------------------------------------|--------------|----------------------------------------------|
| 19    | Oban ExportWorker + queue config        | Tasks 15-16  | Background export with progress broadcast    |
| 20    | Sync/async threshold decision logic     | Task 19      | Small projects sync, large projects async    |
| 21    | Cleanup cron + retry with checkpoint    | Task 19      | Old exports purged, crash recovery works     |
| 22    | REST API endpoints                      | Tasks 1-21   | Programmatic export/import access            |

---

## Testing Strategy

### Unit Tests
- [ ] Expression parser: all operator types, edge cases, malformed input
- [ ] Expression transpiler: per-engine emitter output validation
- [ ] Serializer output format validation (JSON schema / XML schema)
- [ ] Parser input handling (valid, malformed, missing fields, version mismatch)
- [ ] Validation rules (each rule independently)
- [ ] Conflict detection logic (new, existing, deleted entities)
- [ ] Options schema validation

### Integration Tests
- [ ] **Lossless round-trip** (export → import = identical) — this is the P0 test
- [ ] Round-trip with selective export (subset of flows/sheets)
- [ ] Large project handling (1000+ nodes, measure memory + time)
- [ ] Expression transpiler integration: Storyarn condition → Unity Lua → runs in Lua VM
- [ ] Cross-format: export Storyarn JSON, import, re-export — diff must be empty
- [ ] Concurrent export jobs (Oban)

### E2E Tests
- [ ] Export modal workflow (format selection, validation, download)
- [ ] Import with conflicts (skip, overwrite, merge)
- [ ] Download verification (file size, content type, filename)

---

## Success Criteria

- [ ] Export to Storyarn JSON preserves all data (lossless round-trip verified by test)
- [ ] Import from Storyarn JSON restores project exactly (diff = empty)
- [ ] Export to Unity produces files loadable by Dialogue System for Unity
- [ ] Export to Godot produces files loadable by Dialogic 2
- [ ] Export to Unreal produces valid DataTable CSVs importable as UDataTable
- [ ] Expression transpiler handles all condition/instruction patterns per engine
- [ ] Untranspilable expressions reported as warnings (not silent failures)
- [ ] Pre-export validation catches common issues with entity-level links
- [ ] Large projects (1000+ nodes) export without timeout via Oban
- [ ] Import handles conflicts gracefully (skip/overwrite/merge)
- [ ] articy:draft XML interoperability works (import and export)
- [ ] Adding a new engine format requires only 1 new module + 1 registry line

---

## Key Architectural Decisions

### Why Behaviour + Registry over Protocol

Elixir protocols dispatch on data type, but all serializers receive the same `%ProjectData{}` map. We need dispatch on **format atom**, not on data shape. A behaviour + registry map gives us explicit registration, easy listing for UI, and zero magic.

### Why a shared Data Collector

Without it, each serializer would independently query the database with slightly different preloads, causing N+1 issues and inconsistencies. The collector does one aggressive load, and serializers are pure transformations on in-memory data. This also makes testing trivial — pass a fixture map, assert output.

### Why Expression Transpiler is separate from Serializers

Expressions cut across all engine formats. Embedding Lua generation inside the Unity serializer and GDScript generation inside the Godot serializer would duplicate parsing logic. The transpiler is its own module tree with the parser shared and emitters per-engine.

### Why round-trip before engine formats

If native JSON export → import isn't lossless, every engine format built on top of it inherits data loss bugs. The round-trip test is the foundation — it must pass before anything else matters.

### Why BEAM over Rust/sidecar for background processing

Export is I/O bound (Postgres reads + file writes), not CPU bound. The BEAM VM provides:
- **Preemptive scheduling** — a 30-second export yields to other processes every ~1ms automatically, no manual async/await or thread pools needed
- **Process isolation** — an export crash doesn't affect LiveView sessions; the supervisor restarts it
- **Cancellation** — `Oban.cancel_job/1` kills the process cleanly; no dangling threads or zombie NIFs
- **Progress reporting** — PubSub broadcasts from within the export process to the LiveView in real-time, zero coordination overhead

A Rust NIF would block the BEAM scheduler (requiring dirty scheduler hacks), force data serialization/deserialization across the FFI boundary, and make debugging 10x harder. The ~3 seconds saved on JSON encoding doesn't justify the complexity.

### Why streaming from DB (not load-all-then-serialize)

A 50k-node project with all relations is ~200MB in memory. Streaming via `Repo.stream` with 500-row batches keeps memory at ~20MB constant. This is the difference between "works for any project size" and "OOMs on large projects." The serializers write to file incrementally, so the full output never exists in memory either.

### Why dual sync/async mode

Small projects (<1000 entities) return instantly via sync export — no Oban job, no progress bar, just a download. This covers the 95% case. Oban is reserved for large projects where the user needs progress feedback and the export takes >2 seconds. The threshold is configurable.

### Why sync-first in implementation order

Build all serialization logic as pure functions first (sync mode). They're easy to test — pass a map, assert output. Then wrap with Oban for async. This means the core logic is proven before adding job infrastructure, progress tracking, and crash recovery.

---

*This phase depends on 7.5 enhancements (Sheets, Flows, Localization, Scenes) being complete for full export coverage.*
