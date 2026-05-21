%{
title: "Core Concepts",
category_label: "Welcome",
order: 2,
description: "A glossary of the core Storyarn concepts you will see across the documentation."
}

---

Storyarn connects world data, branching narrative, spatial scenes, localization, and export workflows. This glossary gives you the shared vocabulary used throughout the docs.

## Project structure

| Concept | Meaning | Where to learn more |
| ------- | ------- | ------------------- |
| **Workspace** | Your team's top-level container. It holds projects and controls workspace membership. | [Create a Workspace](/docs/quick-start/create-workspace) |
| **Project** | A self-contained narrative workspace with its own sheets, flows, scenes, localization data, assets, and project-level members. | [Core Workflow](/docs/welcome/core-workflow) |
| **Asset** | An uploaded media file such as an image or audio file. Assets can be referenced by sheets, flows, scenes, localization, and exports. | [Import & Export](/docs/import-export/import-export-overview) |

## World data

| Concept | Meaning | Where to learn more |
| ------- | ------- | ------------------- |
| **Sheet** | A structured data record for a character, item, location, faction, quest, or any world entity you need to track. | [Sheets Overview](/docs/world-building/sheets-overview) |
| **Block** | A typed field inside a sheet. Blocks can store text, rich text, numbers, booleans, selects, dates, tables, references, and more. | [Blocks](/docs/world-building/blocks) |
| **Variable** | A runtime-readable value generated from a non-constant block. Flows use variables in conditions and instructions. | [Your First Sheet](/docs/quick-start/first-sheet) |

Variables use the pattern:

```text
{sheet_shortcut}.{variable_name}
```

For example, a Health block on the `mc.jaime` sheet becomes `mc.jaime.health`.

## Narrative logic

| Concept | Meaning | Where to learn more |
| ------- | ------- | ------------------- |
| **Flow** | A visual graph that defines dialogue, branching logic, conditions, instructions, subflows, and execution paths. | [Flows Overview](/docs/narrative-design/flows-overview) |
| **Node** | A single step inside a flow. Common node types include Dialogue, Condition, Instruction, Sequence, Subflow, Hub, Jump, Entry, and Exit. | [Your First Flow](/docs/quick-start/first-flow) |
| **Pin** | A connection point on a node. Output pins connect to input pins to define execution order and branches. | [Flows Overview](/docs/narrative-design/flows-overview) |

## Spatial design

| Concept | Meaning | Where to learn more |
| ------- | ------- | ------------------- |
| **Scene** | A spatial map where narrative content can be explored through zones, pins, child scenes, and flow overlays. | [Scenes Overview](/docs/scene-design/scenes-overview) |
| **Zone** | A drawn region inside a scene. Zones can evaluate conditions, run instructions, link to flows, or drill into child scenes. | [Scenes Overview](/docs/scene-design/scenes-overview) |

## Localization

| Concept | Meaning | Where to learn more |
| ------- | ------- | ------------------- |
| **Localization ID** | A stable identifier used by the localization system to track extracted text across source changes, translation, review, and import/export. | [Localization Overview](/docs/localization/localization-overview) |

## How these concepts connect

Sheets define the world state. Blocks on sheets become variables. Flows read those variables through condition nodes and change them through instruction nodes. Scenes place flows in a spatial context. Localization extracts the player-facing text from those systems. Export & Import moves the result into backups or engine-specific formats.
