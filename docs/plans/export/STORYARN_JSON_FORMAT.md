# Phase 8: Export — Storyarn JSON Format (Native)

> **Parent document:** [PHASE_8_EXPORT.md](../PHASE_8_EXPORT.md)

Full-fidelity export that preserves all Storyarn data for backup, migration, or external processing.

> **ID Strategy:** In the database, IDs are auto-incrementing integers. For export, they are serialized as opaque strings (stringified integers). Importers should treat IDs as opaque references — never assume numeric ordering. Re-imports generate new integer IDs and use an ID mapping table to reconnect references.

## Top-Level Structure

```json
{
  "storyarn_version": "1.0.0",
  "export_version": "1.0.0",
  "exported_at": "2026-02-24T15:30:00Z",
  "project": {
    "id": "uuid",
    "name": "My RPG Project",
    "slug": "my-rpg-project",
    "description": "An epic adventure...",
    "settings": {}
  },
  "sheets": [...],
  "flows": [...],
  "scenes": [...],
  "screenplays": [...],
  "localization": {...},
  "assets": {...},
  "metadata": {...}
}
```

## Sheets Section

Sheets are the entity/character/location data containers (previously called "pages").

**Block types:** `text`, `rich_text`, `number`, `select`, `multi_select`, `boolean`, `date`, `divider`, `reference`, `table`

```json
{
  "sheets": [
    {
      "id": "uuid",
      "shortcut": "mc.jaime",
      "name": "Jaime",
      "description": "<p>Main character</p>",
      "color": "#3b82f6",
      "parent_id": "uuid-or-null",
      "position": 0,
      "avatar_asset_id": "uuid-or-null",
      "banner_asset_id": "uuid-or-null",
      "hidden_inherited_block_ids": [],
      "current_version_id": "uuid-or-null",
      "blocks": [
        {
          "id": "123",
          "type": "text",
          "position": 0,
          "config": { "label": "Name", "placeholder": "" },
          "value": { "content": "Jaime the Brave" },
          "is_constant": false,
          "variable_name": "name",
          "scope": "self",
          "required": false,
          "detached": false,
          "inherited_from_block_id": null,
          "column_group_id": null,
          "column_index": 0
        },
        {
          "id": "124",
          "type": "number",
          "position": 1,
          "config": { "label": "Health", "placeholder": "0", "min": 0, "max": 100, "step": null },
          "value": { "content": 100 },
          "is_constant": false,
          "variable_name": "health",
          "scope": "self",
          "required": false,
          "detached": false,
          "inherited_from_block_id": null,
          "column_group_id": null,
          "column_index": 0
        },
        {
          "id": "125",
          "type": "select",
          "position": 2,
          "config": {
            "label": "Class",
            "placeholder": "Select...",
            "options": [
              { "key": "warrior", "value": "Warrior" },
              { "key": "mage", "value": "Mage" }
            ]
          },
          "value": { "content": "warrior" },
          "is_constant": false,
          "variable_name": "class",
          "scope": "self",
          "required": false,
          "detached": false,
          "inherited_from_block_id": null,
          "column_group_id": null,
          "column_index": 0
        },
        {
          "id": "126",
          "type": "boolean",
          "position": 3,
          "config": { "label": "Is Alive", "mode": "two_state" },
          "value": { "content": true },
          "is_constant": false,
          "variable_name": "is_alive",
          "scope": "self",
          "required": false,
          "detached": false,
          "inherited_from_block_id": null,
          "column_group_id": null,
          "column_index": 0
        },
        {
          "id": "127",
          "type": "reference",
          "position": 4,
          "config": { "label": "Current Location", "allowed_types": ["sheet", "flow"] },
          "value": { "target_type": "sheet", "target_id": "200" },
          "is_constant": false,
          "variable_name": null,
          "scope": "self",
          "required": false,
          "detached": false,
          "inherited_from_block_id": null,
          "column_group_id": null,
          "column_index": 0
        },
        {
          "id": "128",
          "type": "table",
          "position": 5,
          "config": { "label": "Inventory", "collapsed": false },
          "value": null,
          "is_constant": false,
          "variable_name": null,
          "scope": "self",
          "required": false,
          "detached": false,
          "inherited_from_block_id": null,
          "column_group_id": null,
          "column_index": 0,
          "table_data": {
            "columns": [
              { "id": "301", "name": "Item", "slug": "item", "type": "text", "is_constant": false, "required": false, "position": 0, "config": {} },
              { "id": "302", "name": "Quantity", "slug": "quantity", "type": "number", "is_constant": false, "required": false, "position": 1, "config": {} }
            ],
            "rows": [
              { "id": "401", "name": "Sword", "slug": "sword", "position": 0, "cells": { "item": "Sword", "quantity": 1 } }
            ]
          }
        }
      ]
    }
  ]
}
```

**Block field reference:**

| Field                     | Type                     | Description                                                                                                              |
|---------------------------|--------------------------|--------------------------------------------------------------------------------------------------------------------------|
| `is_constant`             | boolean                  | If true, block is NOT exposed as a variable (even for variable-capable types)                                            |
| `variable_name`           | string\|null             | The variable identifier (auto-generated from label via `variablify`). null for dividers, references, and constant blocks |
| `scope`                   | `"self"` \| `"children"` | `"self"` = block belongs to this sheet only. `"children"` = inherited by child sheets (property inheritance)             |
| `required`                | boolean                  | Whether the block must have a value (validation)                                                                         |
| `detached`                | boolean                  | If true, an inherited block has been detached from its parent (no longer syncs)                                          |
| `inherited_from_block_id` | string\|null             | Points to the parent block this was inherited from (null for original blocks)                                            |
| `column_group_id`         | string\|null             | UUID grouping blocks into visual columns (layout)                                                                        |
| `column_index`            | integer                  | 0, 1, or 2 — column position within a column group                                                                       |

**Variable derivation:** A block is a variable if `is_constant == false` AND `type` is NOT in `[divider, reference]`. The export uses `is_constant` + `variable_name` (not a computed `is_variable` flag) so importers can reconstruct the same logic.

**Table column/row fields:**

| Field                | Type    | Description                                                                                                                        |
|----------------------|---------|------------------------------------------------------------------------------------------------------------------------------------|
| Column `slug`        | string  | URL-safe identifier for the column (auto-generated from name). Used in cell keys and variable paths: `sheet.table.row.column_slug` |
| Column `is_constant` | boolean | Whether column values are exposed as variables                                                                                     |
| Column `required`    | boolean | Whether cells must have a value                                                                                                    |
| Column `config`      | map     | Type-specific config (same structure as block config for that type)                                                                |
| Row `name`           | string  | Human-readable row name                                                                                                            |
| Row `slug`           | string  | URL-safe identifier for the row. Used in variable paths: `sheet.table.row_slug.column_slug`                                        |

## Flows Section

**Node types (9):** `entry`, `exit`, `dialogue`, `condition`, `instruction`, `hub`, `jump`, `subflow`, `scene`

> **Note:** There is NO `choice`, `event`, or `interaction` node type. Choices are `responses[]` inside dialogue nodes. Events are handled via instruction assignments. The `source` field on nodes indicates origin: `"manual"` (user-created) or `"screenplay_sync"` (auto-synced from screenplay).

```json
{
  "flows": [
    {
      "id": "uuid",
      "shortcut": "act1.tavern-intro",
      "name": "Tavern Introduction",
      "description": "",
      "parent_id": "uuid-or-null",
      "position": 0,
      "is_main": false,
      "settings": {},
      "scene_id": "uuid-or-null",
      "nodes": [
        {
          "id": "uuid",
          "type": "entry",
          "position_x": 100.0,
          "position_y": 300.0,
          "source": "manual",
          "data": {}
        },
        {
          "id": "uuid",
          "type": "dialogue",
          "position_x": 300.0,
          "position_y": 300.0,
          "source": "manual",
          "data": {
            "speaker_sheet_id": "uuid-or-null",
            "text": "<p>Hello, traveler!</p>",
            "stage_directions": "",
            "menu_text": "",
            "audio_asset_id": null,
            "technical_id": "",
            "localization_id": "dlg_a1b2c3d4",
            "responses": [
              {
                "id": "resp_001",
                "text": "Hello!",
                "condition": null,
                "instruction": null,
                "instruction_assignments": []
              },
              {
                "id": "resp_002",
                "text": "Leave me alone.",
                "condition": {
                  "logic": "all",
                  "rules": [
                    { "sheet": "mc.player", "variable": "mood", "operator": "equals", "value": "angry" }
                  ]
                },
                "instruction": null,
                "instruction_assignments": []
              }
            ]
          }
        },
        {
          "id": "uuid",
          "type": "condition",
          "position_x": 700.0,
          "position_y": 200.0,
          "source": "manual",
          "data": {
            "condition": {
              "logic": "all",
              "rules": [
                { "id": "rule_001", "sheet": "mc.jaime", "variable": "health", "operator": "greater_than", "value": "50" }
              ]
            },
            "expression": null,
            "switch_mode": false,
            "cases": [
              { "id": "case_true", "value": "true", "label": "True" },
              { "id": "case_false", "value": "false", "label": "False" }
            ]
          }
        },
        {
          "id": "uuid",
          "type": "instruction",
          "position_x": 700.0,
          "position_y": 400.0,
          "source": "manual",
          "data": {
            "assignments": [
              {
                "id": "assign_001",
                "sheet": "mc.jaime",
                "variable": "health",
                "operator": "subtract",
                "value": "10",
                "value_type": "literal",
                "value_sheet": null
              },
              {
                "id": "assign_002",
                "sheet": "flags",
                "variable": "met_jaime",
                "operator": "set_true",
                "value": null,
                "value_type": "literal",
                "value_sheet": null
              }
            ],
            "description": "Reduce health and set flag"
          }
        },
        {
          "id": "uuid",
          "type": "jump",
          "position_x": 900.0,
          "position_y": 300.0,
          "source": "manual",
          "data": {
            "target_hub_id": "after_greeting"
          }
        },
        {
          "id": "uuid",
          "type": "subflow",
          "position_x": 900.0,
          "position_y": 500.0,
          "source": "manual",
          "data": {
            "referenced_flow_id": "uuid-or-null"
          }
        },
        {
          "id": "uuid",
          "type": "hub",
          "position_x": 1100.0,
          "position_y": 300.0,
          "source": "manual",
          "data": {
            "hub_id": "after_greeting",
            "label": "",
            "color": "#8b5cf6"
          }
        },
        {
          "id": "uuid",
          "type": "scene",
          "position_x": 100.0,
          "position_y": 100.0,
          "source": "manual",
          "data": {
            "location_sheet_id": "uuid-or-null",
            "int_ext": "int",
            "sub_location": "Back room",
            "time_of_day": "night",
            "description": "",
            "technical_id": ""
          }
        },
        {
          "id": "uuid",
          "type": "exit",
          "position_x": 1300.0,
          "position_y": 300.0,
          "source": "manual",
          "data": {
            "label": "success",
            "technical_id": "",
            "outcome_tags": [],
            "outcome_color": "#22c55e",
            "exit_mode": "terminal",
            "referenced_flow_id": null,
            "target_type": null,
            "target_id": null
          }
        }
      ],
      "connections": [
        {
          "id": "uuid",
          "source_node_id": "uuid",
          "source_pin": "output",
          "target_node_id": "uuid",
          "target_pin": "input",
          "label": null
        }
      ]
    }
  ]
}
```

### Dialogue Response Fields

Each response in `responses[]` has:

| Field                     | Type         | Description                                                                                                      |
|---------------------------|--------------|------------------------------------------------------------------------------------------------------------------|
| `id`                      | string       | Unique response identifier                                                                                       |
| `text`                    | string       | Response text shown to player                                                                                    |
| `condition`               | object\|null | Structured condition (same format as condition nodes — flat or block)                                            |
| `instruction`             | string\|null | **Raw JSON string** of assignments (as stored in DB). Present for backward compat.                               |
| `instruction_assignments` | array        | **Parsed structured array** of assignments (same format as instruction node). Use this for engine transpilation. |

> **`instruction` vs `instruction_assignments`:** In the database, response instructions are stored as a JSON string in the `instruction` field. On export, the serializer MUST also produce the parsed `instruction_assignments` array (same structure as instruction node assignments with `id`, `sheet`, `variable`, `operator`, `value`, `value_type`, `value_sheet`). Engine transpilers use `instruction_assignments`; the raw `instruction` string is for round-trip fidelity.

### Condition Formats

Conditions support TWO formats. Detection: presence of `"blocks"` key = block format.

**Flat format (legacy, still supported):**
```json
{
  "logic": "all",
  "rules": [
    { "id": "rule_001", "sheet": "mc.jaime", "variable": "health", "operator": "greater_than", "value": "50" }
  ]
}
```

**Block format (primary — used by the condition builder UI):**
```json
{
  "logic": "any",
  "blocks": [
    {
      "id": "block_1", "type": "block", "logic": "all",
      "rules": [
        { "id": "rule_001", "sheet": "mc.jaime", "variable": "health", "operator": "greater_than", "value": "50" }
      ]
    },
    {
      "id": "group_1", "type": "group", "logic": "all",
      "blocks": [
        { "id": "block_2", "type": "block", "logic": "all", "rules": [...] },
        { "id": "block_3", "type": "block", "logic": "all", "rules": [...] }
      ]
    }
  ]
}
```

Max nesting: 1 level (groups cannot contain groups). The expression transpiler must handle BOTH formats.

### Condition Operators by Block Type

| Block Type          | Operators                                                                                          |
|---------------------|----------------------------------------------------------------------------------------------------|
| `text`, `rich_text` | `equals`, `not_equals`, `contains`, `starts_with`, `ends_with`, `is_empty`                         |
| `number`            | `equals`, `not_equals`, `greater_than`, `greater_than_or_equal`, `less_than`, `less_than_or_equal` |
| `boolean`           | `is_true`, `is_false`, `is_nil`                                                                    |
| `select`            | `equals`, `not_equals`, `is_nil`                                                                   |
| `multi_select`      | `contains`, `not_contains`, `is_empty`                                                             |
| `date`              | `equals`, `not_equals`, `before`, `after`                                                          |

### Instruction Assignment Operators by Block Type

| Block Type               | Operators                                         |
|--------------------------|---------------------------------------------------|
| `number`                 | `set`, `add`, `subtract`, `set_if_unset`          |
| `boolean`                | `set_true`, `set_false`, `toggle`, `set_if_unset` |
| `text`, `rich_text`      | `set`, `clear`, `set_if_unset`                    |
| `select`, `multi_select` | `set`, `set_if_unset`                             |
| `date`                   | `set`, `set_if_unset`                             |

> **Note:** There is NO `multiply` operator. The `set_if_unset` operator only assigns if the variable is currently nil/unset.

### Assignment Field Reference

| Field         | Type                            | Description                                                                          |
|---------------|---------------------------------|--------------------------------------------------------------------------------------|
| `id`          | string                          | Unique identifier for the assignment (e.g., `"assign_001"`)                          |
| `sheet`       | string                          | Sheet shortcut (e.g., `"mc.jaime"`)                                                  |
| `variable`    | string                          | Variable name within the sheet (e.g., `"health"`)                                    |
| `operator`    | string                          | One of the operators listed above                                                    |
| `value`       | string\|null                    | The value to assign (null for operators like `set_true`, `toggle`, `clear`)          |
| `value_type`  | `"literal"` \| `"variable_ref"` | Whether `value` is a literal or a reference to another variable                      |
| `value_sheet` | string\|null                    | When `value_type` is `"variable_ref"`, the sheet shortcut of the referenced variable |

**Variable-to-variable assignment example:**
```json
{
  "id": "assign_003",
  "sheet": "mc.link",
  "variable": "has_master_sword",
  "operator": "set",
  "value": "sword_done",
  "value_type": "variable_ref",
  "value_sheet": "global.quests"
}
```
This sets `mc.link.has_master_sword` to the current value of `global.quests.sword_done`.

## Scenes Section

Scenes are the visual world-building canvases (previously called "maps").

```json
{
  "scenes": [
    {
      "id": "uuid",
      "shortcut": "scenes.world",
      "name": "World Map",
      "description": "",
      "parent_id": null,
      "position": 0,
      "background_asset_id": "uuid-or-null",
      "width": 2048,
      "height": 1536,
      "default_zoom": 1.0,
      "default_center_x": 50.0,
      "default_center_y": 50.0,
      "scale_unit": "km",
      "scale_value": 100.0,
      "layers": [
        {
          "id": "uuid",
          "name": "Default",
          "is_default": true,
          "position": 0,
          "visible": true,
          "fog_enabled": false,
          "fog_color": "#000000",
          "fog_opacity": 0.85
        },
        {
          "id": "uuid",
          "name": "After the War",
          "is_default": false,
          "position": 1,
          "visible": true,
          "fog_enabled": true,
          "fog_color": "#1a1a1a",
          "fog_opacity": 0.6
        }
      ],
      "pins": [
        {
          "id": "uuid",
          "layer_id": "uuid-or-null",
          "position_x": 45.5,
          "position_y": 30.0,
          "pin_type": "location",
          "icon": "castle",
          "color": "#fbbf24",
          "opacity": 1.0,
          "label": "Capital City",
          "target_type": "sheet",
          "target_id": "uuid-or-null",
          "tooltip": "The heart of the kingdom",
          "size": "lg",
          "position": 0,
          "locked": false,
          "icon_asset_id": null,
          "sheet_id": "uuid-or-null",
          "action_type": "none",
          "action_data": {},
          "condition": null,
          "condition_effect": "hide"
        }
      ],
      "zones": [
        {
          "id": "uuid",
          "name": "Kingdom Territory",
          "layer_id": "uuid-or-null",
          "vertices": [
            { "x": 20.0, "y": 10.0 },
            { "x": 60.0, "y": 10.0 },
            { "x": 60.0, "y": 50.0 },
            { "x": 20.0, "y": 50.0 }
          ],
          "fill_color": "#3b82f6",
          "border_color": "#1d4ed8",
          "border_width": 2,
          "border_style": "solid",
          "opacity": 0.3,
          "target_type": "scene",
          "target_id": "uuid-or-null",
          "tooltip": "Click to enter kingdom",
          "position": 0,
          "locked": false,
          "action_type": "none",
          "action_data": {},
          "condition": null,
          "condition_effect": "hide"
        }
      ],
      "connections": [
        {
          "id": "uuid",
          "from_pin_id": "uuid",
          "to_pin_id": "uuid",
          "line_style": "dashed",
          "line_width": 2,
          "color": "#92400e",
          "label": "3 days travel",
          "show_label": true,
          "bidirectional": true,
          "waypoints": []
        }
      ],
      "annotations": [
        {
          "id": "uuid",
          "text": "Dragon's Lair",
          "position_x": 75.0,
          "position_y": 20.0,
          "font_size": "lg",
          "color": "#ef4444",
          "layer_id": "uuid-or-null",
          "position": 0,
          "locked": false
        }
      ]
    }
  ]
}
```

## Screenplays Section

Screenplays are Fountain-compatible script documents linked to flows.

**Element types:**
- Standard: `scene_heading`, `action`, `character`, `dialogue`, `parenthetical`, `transition`, `dual_dialogue`
- Interactive (map to flow nodes): `conditional`, `instruction`, `response`
- Flow markers (round-trip sync): `hub_marker`, `jump_marker`
- Utility (no flow mapping): `note`, `section`, `page_break`, `title_page`

```json
{
  "screenplays": [
    {
      "id": "100",
      "shortcut": "sp.act1",
      "name": "Act 1 Screenplay",
      "description": "",
      "parent_id": null,
      "position": 0,
      "linked_flow_id": "50-or-null",
      "draft_label": null,
      "draft_status": "active",
      "draft_of_id": null,
      "elements": [
        {
          "id": "500",
          "type": "scene_heading",
          "content": "INT. TAVERN - NIGHT",
          "position": 0,
          "data": {},
          "depth": 0,
          "branch": null,
          "linked_node_id": "uuid-or-null"
        },
        {
          "id": "501",
          "type": "character",
          "content": "JAIME",
          "position": 1,
          "data": {},
          "depth": 0,
          "branch": null,
          "linked_node_id": null
        },
        {
          "id": "502",
          "type": "dialogue",
          "content": "Hello, traveler!",
          "position": 2,
          "data": {},
          "depth": 0,
          "branch": null,
          "linked_node_id": "uuid-or-null"
        },
        {
          "id": "503",
          "type": "conditional",
          "content": "",
          "position": 3,
          "data": { "condition": { "logic": "all", "rules": [...] } },
          "depth": 0,
          "branch": null,
          "linked_node_id": "uuid-or-null"
        },
        {
          "id": "504",
          "type": "dialogue",
          "content": "This branch only if condition is true",
          "position": 4,
          "data": {},
          "depth": 1,
          "branch": "true",
          "linked_node_id": null
        }
      ]
    }
  ]
}
```

**Screenplay field notes:**
- `linked_flow_id` is a SINGLE flow reference (not an array) — one screenplay links to at most one flow for bidirectional sync
- `depth` — nesting depth inside conditional blocks (0 = root level, 1+ = inside conditional)
- `branch` — which branch of a conditional this element belongs to: `null`, `"true"`, or `"false"`
- `linked_node_id` — links the element to its corresponding flow node (for screenplay <-> flow sync)
- `data` — type-specific metadata (e.g., condition data for `conditional` elements)

## Localization Section

The localization section exports the full `localized_texts` table. Each entry represents ONE translation of ONE field in ONE locale.

**Source types:** `flow_node`, `block`, `sheet`, `flow`, `screenplay`
**Status workflow:** `pending` → `draft` → `in_progress` → `review` → `final`
**VO status:** `none`, `needed`, `recorded`, `approved`

```json
{
  "localization": {
    "source_language": "en",
    "languages": [
      {"locale_code": "en", "name": "English", "is_source": true},
      {"locale_code": "es", "name": "Spanish", "is_source": false},
      {"locale_code": "de", "name": "German", "is_source": false}
    ],
    "strings": [
      {
        "source_type": "flow_node",
        "source_id": "uuid",
        "source_field": "text",
        "source_text": "Hello, traveler!",
        "source_text_hash": "sha256:abc...",
        "speaker_sheet_id": "uuid-or-null",
        "translations": {
          "en": {
            "translated_text": "Hello, traveler!",
            "status": "final",
            "vo_status": "recorded",
            "vo_asset_id": "uuid-or-null",
            "translator_notes": null,
            "reviewer_notes": null,
            "word_count": 2,
            "machine_translated": false,
            "last_translated_at": "2026-02-24T15:00:00Z",
            "last_reviewed_at": "2026-02-24T16:00:00Z"
          },
          "es": {
            "translated_text": "Hola, viajero!",
            "status": "final",
            "vo_status": "needed",
            "vo_asset_id": null,
            "translator_notes": null,
            "reviewer_notes": null,
            "word_count": 2,
            "machine_translated": true,
            "last_translated_at": "2026-02-24T15:30:00Z",
            "last_reviewed_at": null
          }
        }
      }
    ],
    "glossary": [
      {
        "source_term": "Eldoria",
        "source_locale": "en",
        "translations": {
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

**Note:** The `strings` section is an array (not a map keyed by localization_id) because each source entity+field can have multiple locale entries. The composite key is `(source_type, source_id, source_field, locale_code)`.

**Glossary aggregation:** In the database, glossary entries are stored per-pair (`source_term + source_locale → target_term + target_locale`). For export, we aggregate entries by `source_term + source_locale` into a grouped structure with a `translations` map. On import, the grouped format is expanded back to per-pair rows.

## Assets Section

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
        "metadata": { "width": 512, "height": 512, "thumbnail_key": "assets/thumbs/jaime_portrait.jpg" }
      }
    ]
  }
}
```

**Asset Export Modes:**
- `references` - URLs only (default, smaller file)
- `embedded` - Base64 encoded (self-contained, larger file)
- `bundled` - Separate ZIP with assets folder

## Metadata Section

```json
{
  "metadata": {
    "statistics": {
      "sheet_count": 145,
      "flow_count": 32,
      "node_count": 856,
      "connection_count": 1024,
      "scene_count": 5,
      "screenplay_count": 8,
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
          "type": "orphan_sheet",
          "message": "Sheet 'Old Character' has no references",
          "entity_id": "uuid"
        }
      ],
      "errors": []
    }
  }
}
```
