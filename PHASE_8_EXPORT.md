# Phase 8: Export & Import System

> **Goal:** Enable full project export/import for game engine integration and backup/migration
>
> **Priority:** High - Core feature for game development workflow
>
> **Dependencies:** Phase 7.5 (Pages/Flows enhancements, Localization, World Builder)
>
> **Last Updated:** February 2, 2026

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
      "parent_map_id": null,
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

#### Unity Export (JSON)

Optimized for Dialogue System for Unity, Ink integration, or custom parsers.

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

For teams migrating from or collaborating with articy:draft users.

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
- [ ] `Exports.export_pages/2` - Export specific pages
- [ ] `Exports.get_export_options/1` - Get available options

#### 8.1.2 Export Options Schema
```elixir
%ExportOptions{
  format: :storyarn | :unity | :godot | :unreal | :articy,
  version: "1.0.0",
  include_pages: true,
  include_flows: true,
  include_maps: true,
  include_localization: true,
  include_assets: :references | :embedded | :bundled,
  languages: ["en", "es"] | :all,
  flow_ids: [uuid] | :all,
  page_ids: [uuid] | :all,
  validate_before_export: true,
  pretty_print: true
}
```

#### 8.1.3 Export Serializers
- [ ] `Exports.Serializers.StoryarnJSON` - Native format
- [ ] `Exports.Serializers.UnityJSON` - Unity format
- [ ] `Exports.Serializers.GodotJSON` - Godot format
- [ ] `Exports.Serializers.UnrealCSV` - Unreal DataTables
- [ ] `Exports.Serializers.ArticyXML` - articy:draft format

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
- [ ] Progress indicator for large exports
- [ ] Download trigger (browser download)

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

| Order   | Task                                    | Dependencies          | Testable Outcome        |
|---------|-----------------------------------------|-----------------------|-------------------------|
| 1       | Export context + options schema         | None                  | Export options work     |
| 2       | Storyarn JSON serializer (pages)        | Task 1                | Can export pages        |
| 3       | Storyarn JSON serializer (flows)        | Task 1                | Can export flows        |
| 4       | Storyarn JSON serializer (maps)         | Task 1, World Builder | Can export maps         |
| 5       | Storyarn JSON serializer (localization) | Task 1, Localization  | Can export translations |
| 6       | Pre-export validation                   | Tasks 2-5             | Validation works        |
| 7       | Export UI (modal)                       | Tasks 2-6             | UI works                |
| 8       | Export download                         | Task 7                | Can download file       |
| 9       | Unity format serializer                 | Task 1                | Unity export works      |
| 10      | Godot format serializer                 | Task 1                | Godot export works      |
| 11      | Unreal format serializer                | Task 1                | Unreal export works     |
| 12      | articy:draft XML serializer             | Task 1                | articy export works     |
| 13      | Import parser (Storyarn JSON)           | None                  | Can parse JSON          |
| 14      | Import preview                          | Task 13               | Preview works           |
| 15      | Import conflict detection               | Task 14               | Conflicts detected      |
| 16      | Import execution                        | Task 15               | Import works            |
| 17      | Import UI                               | Tasks 13-16           | Full import flow        |
| 18      | articy:draft XML parser                 | None                  | Can import from articy  |
| 19      | Async export (Oban)                     | Tasks 7-8             | Large exports work      |
| 20      | API endpoints                           | Tasks 1-19            | API access works        |

---

## Testing Strategy

### Unit Tests
- [ ] Serializer output format validation
- [ ] Parser input handling (valid/invalid)
- [ ] Validation rules (each rule)
- [ ] Conflict detection logic
- [ ] Options schema validation

### Integration Tests
- [ ] Full export round-trip (export → import)
- [ ] Cross-format compatibility
- [ ] Large project handling
- [ ] Concurrent export jobs

### E2E Tests
- [ ] Export modal workflow
- [ ] Import with conflicts
- [ ] Download verification

---

## Success Criteria

- [ ] Export to Storyarn JSON preserves all data (lossless)
- [ ] Import from Storyarn JSON restores project exactly
- [ ] Export to Unity/Godot/Unreal produces usable files
- [ ] Pre-export validation catches common issues
- [ ] Validation errors link to source entities
- [ ] Large projects export without timeout (async)
- [ ] Import handles conflicts gracefully
- [ ] articy:draft interoperability works

---

*This phase depends on 7.5 enhancements (Pages, Flows, Localization, World Builder) being complete for full export coverage.*
