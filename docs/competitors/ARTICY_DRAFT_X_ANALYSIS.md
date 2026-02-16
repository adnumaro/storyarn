# articy:draft X - Complete Feature Analysis

> **Version analyzed:** articy:draft X (v4.2.0 — August 2025)
> **Predecessor:** articy:draft 3 (legacy, maintenance-only)
> **Platform:** Windows + macOS (Mac since April 2025)
> **Developer:** Articy Software GmbH & Co.KG (Bochum, Germany)

---

## Table of Contents

1. [Product Overview](#1-product-overview)
2. [Flow Editor](#3-flow-editor)
3. [Flow Object Types](#4-flow-object-types)
4. [Pins & Connections](#5-pins--connections)
5. [Dialogue System](#6-dialogue-system)
6. [Document View (Screenplay Writing)](#7-document-view-screenplay-writing)
7. [Template System](#8-template-system)
8. [Entities (Game Object Database)](#9-entities-game-object-database)
9. [Scripting Language (articy:expresso)](#10-scripting-language-articyexpresso)
10. [Variables](#11-variables)
11. [Localization & Voice Over](#12-localization--voice-over)
12. [AI Extensions](#13-ai-extensions)
13. [Location Editor](#14-location-editor)
14. [Simulation & Presentation Mode](#15-simulation--presentation-mode)
15. [Checkup & Quality Tools](#16-checkup--quality-tools)
16. [Navigator & Content Organization](#17-navigator--content-organization)
17. [Exports & Imports](#18-exports--imports)
18. [Game Engine Integration](#19-game-engine-integration)
19. [Multi-User Collaboration](#20-multi-user-collaboration)
20. [Plugin System (MDK)](#21-plugin-system-mdk)
21. [Workspace & UI Customization](#22-workspace--ui-customization)
22. [Advanced Configuration](#23-advanced-configuration)
23. [Version History (X releases)](#24-version-history-x-releases)

---

## 1. Product Overview

articy:draft X is a **desktop narrative design tool** (not web-based) for creating interactive stories, managing game content, and building branching dialogue systems. It is the industry standard for AAA and indie game studios working on narrative-heavy games.

**Core pillars:**
- Visual flow-based story authoring
- Game object database with flexible templates
- Scripting for conditions/instructions
- Localization & voice over management
- Simulation/testing without a game engine
- Engine integration (Unity, Unreal, Godot, custom)
- Multi-user collaboration via SVN/Perforce

**Target users:** Narrative designers, game writers, quest designers, game developers, localization teams.

---

## 3. Flow Editor

The flow editor is the **heart of articy:draft** - a visual, drag-and-drop canvas for building branching narrative structures.

### Core Capabilities
- **Visual drag-and-drop** node placement and connection
- **Non-linear story flows** with arbitrary branching
- **Nested flow** (infinite depth) - any node can contain an inner flowchart
  - Top-level: chapters/acts
  - Mid-level: scenes/quests
  - Bottom-level: individual dialogue lines
- **Quick Create menu** - add multiple nodes at once, suggests speaker/template combos
- **Color coding** - nodes can be color-coded for visual organization
- **Zoom and pan** - standard canvas navigation
- **Copy/paste** - duplicate flow structures
- **Undo/redo** - full history

### Nesting Model
Each flow fragment or dialogue is a **container** that can hold its own branching flow inside. This creates a hierarchical structure:
```
Act 1 (Flow Fragment)
  ├── Scene 1 (Flow Fragment)
  │   ├── Dialogue: Tavern Talk (Dialogue)
  │   │   ├── Line 1 (Dialogue Fragment)
  │   │   ├── Line 2 (Dialogue Fragment)
  │   │   └── Branch...
  │   └── Event: Combat (Flow Fragment)
  └── Scene 2 (Flow Fragment)
      └── ...
```

### Navigation
- Double-click a node to "dive into" its inner flow
- Breadcrumb navigation bar shows current depth
- Back/forward buttons (browser-like)
- Home button returns to project root

---

## 4. Flow Object Types

The flow editor provides 7 core node types:

### Flow Fragment
- **Purpose:** Generic story/quest/scene container
- **Properties:** Display name, description, color, template, attachments
- **Nesting:** Can contain inner flow (other nodes)
- **Pins:** 1 input, 1 output (can add more)
- **Templates:** Assignable (custom properties)

### Dialogue
- **Purpose:** Conversation container (specialized Flow Fragment)
- **Properties:** Same as Flow Fragment plus dialogue-specific settings
- **Inner objects:** Dialogue Fragments, Hubs, Jumps
- **Nesting:** Contains individual lines of dialogue

### Dialogue Fragment
- **Purpose:** Single line of dialogue
- **Properties:**
  - **Speaker** - entity reference (character)
  - **Full text** - complete dialogue line (for VO/subtitles)
  - **Menu text** - shortened version (for choice menus with limited space)
  - **Stage directions** - instructions for voice actors on delivery
- **Pins:** 1 input, 1 output (can add more)
- **Templates:** Assignable

### Hub
- **Purpose:** Routing/merge point (no content, pure flow control)
- **Properties:** Display name, description (only visible in property sheet)
- **Use case:** Merge multiple branches back together, create re-entry points
- **Templates:** Assignable

### Jump
- **Purpose:** Teleport flow to any other node in the project
- **Properties:** Target node reference
- **Target:** Any node in any level of the hierarchy (not limited to same container)
- **Pins:** Input only (no output - the jump IS the exit)
- **Use case:** Cross-reference between scenes, loop back to earlier content

### Condition
- **Purpose:** Binary branch based on script evaluation
- **Properties:** Script field (articy:expresso condition)
- **Outputs:** Exactly 2 - green (true) and red (false)
- **Visual:** Script visible directly on the node (no need to open properties)

### Instruction
- **Purpose:** Execute script when flow passes through
- **Properties:** Script field (articy:expresso instructions)
- **Visual:** Script visible directly on the node
- **Use case:** Modify variables, trigger game events

---

## 5. Pins & Connections

### Pins
- **Input pins** (left side) - can carry **conditions** (gate entry)
- **Output pins** (right side) - can carry **instructions** (execute on exit)
- Default: 1 input + 1 output per node
- Container nodes (Flow Fragment, Dialogue) can have **additional pins**
- Pins with scripts are **highlighted in orange**
- Hover over orange pin to see script tooltip
- Double-click pin to open script editor

### Connections
- Drag from output pin to input pin to create
- Drag from pin to empty space to auto-create a new connected node
- Connections can have **text labels** (double-click connection to add)
- A pin can have multiple connections (fan-out/fan-in)
- Visual arrows show flow direction

### Pin Scripts
- **Condition on input pin:** Flow can only enter this node if condition is true
- **Instruction on output pin:** Executed when flow leaves via this output
- Script editor supports: syntax highlighting, auto-completion, error detection

---

## 6. Dialogue System

### Structure
```
Dialogue (container)
├── Dialogue Fragment (speaker: Alice, text: "Hello!")
│   ├── [output pin: instruction]
│   └── Connection →
├── Dialogue Fragment (speaker: Bob, text: "Hi there!")
│   ├── Connection → Branch A
│   └── Connection → Branch B
├── Hub (merge point)
└── Jump (to another dialogue)
```

### Dialogue Fragment Properties
| Property         | Description                                                  |
|------------------|--------------------------------------------------------------|
| Speaker          | Entity reference (auto-complete from project entities)       |
| Full Text        | Complete dialogue line (VO recordings, subtitles)            |
| Menu Text        | Shortened text for choice menus (optional)                   |
| Stage Directions | Delivery notes for voice actors                              |
| Template         | Custom properties via template system                        |
| Attachments      | Linked assets or external references                         |
| Pin conditions   | Gate dialogue availability                                   |
| Pin instructions | Execute on dialogue selection                                |

### Branching Dialogue
- Multiple output connections from a dialogue fragment = player choices
- Input pin conditions on branches = conditional availability
- Output pin instructions on branches = consequences of choice
- Hubs for merge-back points
- Jumps for cross-scene references

### Quick Create
- Shortcut to add multiple dialogue fragments at once
- Suggests speaker + template combinations based on existing flow content
- Reduces repetitive creation workflow

---

## 7. Document View (Screenplay Writing)

A **word processor-like** alternative to the flow editor for writing linear dialogue.

### Features
- **Screenplay format** - speakers, dialogue lines, stage directions
- **Dialogue chapters** - container with description of what's happening
- **Dialogue fragments** - individual lines within chapters
- **Auto-complete speakers** - suggests characters from project entities
- **Keyboard shortcuts:**
  - `Ctrl+Enter` - new dialogue line (stay in writing flow)
  - `Tab` - cycle through fields (speaker -> text -> stage directions -> menu text)
- **Word-like text formatting** (bold, italic, etc.)

### Flow Conversion
- **Drag and drop** from document view to flow view converts screenplay to nodes
- Chapter -> Dialogue node
- Dialogue lines -> Dialogue Fragment nodes within that Dialogue
- Note: Document and Flow are **separate copies** (changes don't sync)

### Import
- **Final Draft import** - import .fdx screenplay files
- Can import as document or directly convert to flow elements

### Export
- **Word export** from document view toolbar
- Also included in standard project exports

---

## 8. Template System

articy:draft's template system is a flexible, modular data definition system for extending any object type with custom properties.

### Hierarchy
```
Template (bound to one object type)
└── Feature (reusable container - can appear in multiple templates)
    └── Property (typed field)
```

### Key Concepts
- **Templates** are fixed to one object type (Entity template can only go on Entities)
- **Features** are object-independent (a "LootInfo" feature can be reused in NPC and Chest templates)
- Objects **inherit** characteristics from their template
- Templates are **modular** - add/remove features freely
- **Iteration-friendly** - modify template, all instances update

### Property Types
| Type              | Description                                            |
|-------------------|--------------------------------------------------------|
| Number (Integer)  | Numeric values                                         |
| Boolean           | True/false                                             |
| String            | Text values                                            |
| Drop-down List    | Custom enumeration (define values in editor)           |
| Script            | Condition or instruction with syntax highlighting      |
| Strip             | List of references to other objects                    |
| Calculated Strip  | Auto-populated strip via query expression              |
| Reference         | Link to another articy object                          |
| Slot              | Asset slot (image, audio, etc.)                        |

### Advanced Features
- **Read-only properties** (v4.1) - prevents in-app edits, API manipulation still allowed
- **Constraints** - validation rules on property values
- **Calculated strips** - query-based auto-updating lists (e.g., "show all potions that use this ingredient")
- **Template import** - import templates from existing projects when creating new ones

### Template vs. Global Variables
- Use **templates** when a property belongs to an object type (e.g., NPC health, item weight)
- Use **global variables** for game-state tracking (e.g., quest progress, flags)
- Templates scale better: one "Health" property on a template applies to all NPCs automatically

---

## 9. Entities (Game Object Database)

Entities represent all types of game objects.

### Entity Types (via templates)
- Characters (PCs, NPCs, enemies)
- Items (weapons, armor, consumables)
- Skills, spells, abilities
- Abstract concepts (weather, time, factions)
- Anything the project needs

### Entity Properties
Every entity has **built-in properties:**
| Property       | Description                  |
|----------------|------------------------------|
| Display Name   | Human-readable name          |
| Technical Name | Script-addressable identifier|
| ID             | Unique identifier            |
| Text           | Description field            |
| Preview Image  | Visual thumbnail             |
| Color          | Color coding                 |
| Attachments    | Linked assets/references     |

Plus **custom properties** via templates.

### Organization
- Entities organized in **folders** (user-created, color-coded)
- Searchable and filterable
- Can be placed on location maps
- Referenced in dialogue fragments as speakers
- Addressable in scripts via `getObj()`

---

## 10. Scripting Language (articy:expresso)

articy:draft has its own scripting language called **articy:expresso** for controlling narrative flow.

### Enabling
- Checkbox in Project Settings > Flow > "Use built-in scripting support"
- Enables: syntax highlighting, auto-completion, error detection

### Conditions (Boolean expressions)
```
// Simple variable check
GameState.playerLevel >= 3

// Boolean shorthand
Inventory.key                    // same as Inventory.key == true
!GameState.talkedToNPC           // same as GameState.talkedToNPC == false

// Compound
GameState.talkedToGuard != true && Inventory.collectedTokens >= 10

// Object property access
getProp(getObj("Chr_Manfred"), "Player_Character.Strength") > 50
```

### Operators
| Category    | Operators                        |
|-------------|----------------------------------|
| Comparison  | `<`, `<=`, `==`, `!=`, `>`, `>=` |
| Logical     | `&&` / `AND`, `\|\|` / `OR`, `!` |
| Assignment  | `=`, `+=`, `-=`, `*=`, `/=`, `%=`|

### Instructions (Variable modifications)
```
// Simple assignment
GameState.playerLevel = 5

// Increment
Inventory.gold += 100

// Multiple (semicolon-separated)
GameState.questComplete = true; Inventory.gold += 500; NPC.mood -= 10

// Object property manipulation
setProp(getObj("Chr_Manfred"), "Player_Character.Morale", 80)
incrementProp(getObj("Chr_Manfred"), "Player_Character.Morale", 10)
decrementProp(speaker, "Player_Character.Morale", 20)
```

### Built-in Functions
| Function             | Description                                   |
|----------------------|-----------------------------------------------|
| `getObj(id)`         | Get object reference by technical name         |
| `getProp(obj, prop)` | Read a property value                          |
| `setProp(obj, prop, val)` | Set a property value                      |
| `incrementProp(obj, prop, val)` | Increment (default +1)              |
| `decrementProp(obj, prop, val)` | Decrement (default -1)              |
| `isPropInRange(obj, prop, lo, hi)` | Check if value is in range        |
| `random(min, max)`   | Random number                                  |
| `print(msg)`         | Debug output                                   |

### Seen/Unseen Keywords (v4.1)
Track whether the player has visited a node:
| Keyword/Function       | Description                                      |
|------------------------|--------------------------------------------------|
| `seen`                 | Boolean: has this node been visited?              |
| `unseen`               | Boolean: has this node NOT been visited?          |
| `seenCounter`          | Integer: how many times visited                   |
| `getSeenCounter()`     | Get seen counter for a specific object            |
| `setSeenCounter()`     | Manually set seen counter                         |
| `resetAllSeenCounters()` | Reset all counters                              |
| `fallback()`           | Mark a path as fallback when all others are seen  |

```
// Show option only if not seen before
unseen && Inventory.key

// Limit to 3 viewings
seenCounter < 3

// Fallback path
fallback()   // chosen when all sibling branches are "seen"
```

### Comments
```
// Single-line comment
/* Multi-line
   comment */
```

### Where Scripts Can Be Used
1. **Input pins** - conditions (gate entry)
2. **Output pins** - instructions (execute on exit)
3. **Condition nodes** - dedicated condition evaluation
4. **Instruction nodes** - dedicated instruction execution
5. **Script property fields** - on any templated object

---

## 11. Variables

### Global Variables
- **Types:** Boolean, Integer, String
- **Organization:** Grouped in **Variable Sets** (namespaces)
- **Access:** `VariableSet.VariableName` (e.g., `Inventory.gold`)
- **Scope:** Global across the entire project
- **Use:** Conditions, instructions, simulation testing

### Object Properties (via Templates)
- Defined per-template, per-object
- Accessed via `getProp()` / `setProp()` functions
- More scalable for per-entity data (e.g., NPC health)

### Variable Management
- Create, rename, delete in Variable Set editor
- Default values configurable
- Description field for documentation
- Variable sets can be organized by game system (Inventory, GameState, Player, etc.)

---

## 12. Localization & Voice Over

### Localization (v4.0+)

#### Project Languages
- Add unlimited languages to a project
- Mark any text property as "localizable"
- Mark any property as "VO-eligible"
- Reference language (source) vs. target languages

#### Localization View
- Dedicated view for managing all localizable content
- **Filter** by object type, template, language, state
- **Sort** by any column
- **Modify** translations inline
- **Add remarks** for translators and VO artists
- **Side-by-side** reference + target language display

#### Localization State Management
| State       | Description                                              |
|-------------|----------------------------------------------------------|
| Final       | Translation is approved and complete                     |
| In Progress | Translation is being worked on                           |
| Outdated    | Reference text changed since last translation            |

- Auto-marks other languages as "outdated" when reference text changes

#### DeepL Integration
- Automatic machine translation for new languages
- Translate individual properties or bulk translate

#### Spelling Dictionaries
- Auto-downloaded for all project languages
- Integrated spellchecker

#### Export/Import Workflow
- **Export to Excel** - text + VO content for external teams
- **Import from Excel** - reimport translated content
- **Proofreading mode** (v4.2) - export same language as reference + target for review

#### Localization Report
- Word/line counts per character per language
- Separate counts for text vs. voice over
- Useful for budget estimation and progress tracking

### Voice Over Management

#### VO File Management
- Attach audio files to dialogue fragments
- Manage VO files across all languages
- Match localized VO files with corresponding localized text

#### VO Playback
- Play audio files directly within articy:draft
- Simulation mode supports automatic VO playback
- Switch languages during simulation to hear different VO tracks

#### VO Extension Plugin (v4.2 - ElevenLabs)
- Integration with **ElevenLabs** voice synthesis
- Generate synthetic voice previews for prototyping
- Access and manage synthesized voice library
- Prototype tone, timing, and delivery
- Guide voice actors with AI-generated references
- Reduce re-recording loops

#### Voice Over Management Plugin (Legacy - articy:draft 3)
- Creates empty WAV files or auto-generated TTS placeholders
- Placeholder files can be exchanged with final recordings
- Audio reviewable in simulation mode
- Export spoken lines, filenames, and info to Excel

---

## 13. AI Extensions

Available as an optional, disableable plugin (v4.0+).

### AI-Assisted Dialogue
- Select a dialogue or flow fragment
- Describe what the dialogue should convey
- AI generates dialogue content
- Useful for overcoming writer's block / blank page

### AI-Assisted Barks
- Generate entity barks directly in Flow Fragments
- Specify number of barks needed
- Configure in task settings

### AI-Assisted Preview Images
- Generate placeholder images for entities
- Visually distinguish characters in the flow
- Useful during early development before final art

### Privacy & Control
- **Disable AI:** Turn off via Plugin Manager
- **Server restriction:** Multi-user server admins can disable AI for all accounts
- **Third-party services:** Uses external AI services (the specific service is user-configured)
- User decides if and how AI services are used

---

## 14. Location Editor

A **vector-based 2D drawing tool** for planning game worlds and levels. Not a game-level editor - it's a planning/communication tool.

### Drawing Tools
| Tool              | Shortcut    | Description                     |
|-------------------|-------------|---------------------------------|
| Custom zone       | Shift+1     | Free-form polygon               |
| Rectangular zone  | Shift+2     | Rectangle                       |
| Circular zone     | Shift+3     | Circle/ellipse                  |
| Path              | Shift+4     | Line/route                      |
| Free-hand path    | Shift+5     | Freeform drawing                |
| Image             | Shift+9     | Place image on map              |

### Features
- **Background images** - use concept art or existing maps as base layer
- **Layer management** - each element on its own layer
  - Layers can be hidden/shown individually or by folder
  - Layer order = z-order (front/back)
  - Folder-based bulk show/hide
- **Zone editing** - transform (scale/rotate), edit shape (move individual points), add/remove points
- **Spots** - point markers for locations of interest
- **Links** - clickable references to other articy objects
- **Text elements** - labels and descriptions on map
- **Entity placement** - place character icons on the map with their game data
- **Story event markers** - plan where events/triggers/spawns occur

### Use Cases
- World map planning
- Level layout sketching
- NPC placement planning
- Quest trigger zone mapping
- 2D backgrounds for point-and-click adventures (actual game output)
- Hidden object game backgrounds (actual game output)

### Metadata
- Each location object has a description field
- Zones, spots, and paths can reference other articy objects
- Everything is exportable

---

## 15. Simulation & Presentation Mode

Test stories and debug logic without a game engine.

### Presentation View
- **PowerPoint-like** story walkthrough
- Displays dialogue text, speakers, choices
- Conditions and instructions are **evaluated live**
- Navigate through the flow interactively

### Modes
| Mode          | Description                                          |
|---------------|------------------------------------------------------|
| Record Mode   | Default - walk through story, make choices, record    |
| View Mode     | Replay a previously recorded journey                  |
| Analysis Mode | Show ALL branches (including failed conditions in red)|
| Player Mode   | Hide invalid branches (simulate player experience)    |

### Variable Debugging
- **Variable State tab** - shows all variables with:
  - Initial value
  - Previous value (last journey point)
  - Current value
- Variables that changed are **highlighted**
- Filter: show only changed variables
- **Initial value override** - test with specific starting conditions per journey

### Property Inspector
- Monitor object properties in a **separate pane** during simulation
- **Live updates** as you traverse the flow
- Synchronized pane mode - inspector follows selection in another pane
- Works alongside any other view

### Journey Management
- **Save journeys** - bookmark specific paths through the story
- **Replay** saved journeys
- **Share** journeys with team members
- Invalid path indicators (red icons) when deliberately choosing failed conditions

### Script Debugging
- Debug mode highlights which part of a condition evaluated to false (red highlight)
- Custom method popup - enter expected return values for functions not evaluable in simulation
- Scripts in template properties are NOT evaluated (only pin/node scripts)

### Language & VO in Simulation
- Switch display language during simulation
- Automatic playback of attached VO files per language

---

## 16. Checkup & Quality Tools

### Conflict Search
Detects:
- Invalid property values
- Invalid references (broken links)
- Duplicate technical names
- Defective assets
- Missing required fields

### Localization Error Check
- Flags missing translation entries
- Filter by language or check all languages
- Highlights incomplete localization

### Spellchecker
- Integrated spell checking
- Dictionaries for all project languages
- Auto-downloaded

### Search (Query)
- **Standard search** - find objects by name
- **Advanced query** - custom criteria with query language
- Search across all object types and properties

---

## 17. Navigator & Content Organization

### Navigator (Sidebar)
- **Hierarchical tree** of all project objects (like Windows Explorer)
- **Collapsible/expandable** at all levels
- **Drag-and-drop** reorganization
- **Color-coded folders:**
  - Orange = system folders (predefined)
  - Blue = user-created folders

### Display Options
| Mode           | Shows                          |
|----------------|--------------------------------|
| None (default) | Display name only              |
| Technical Name | Script-addressable identifier  |
| Template Name  | Applied template name          |

### Navigation
- **Address bar** with breadcrumb path
- **Back/forward** history buttons
- **Home button** to project root
- **Dropdown breadcrumbs** - click to see sub-structure
- **Collapse all** / **Expand all** buttons

### Favorites
- Mark any object or folder as favorite
- Yellow outline in flow editor
- Dedicated Favorites folder in Library tab
- Add from Navigator, Flow, or Content browser

### Multi-User Indicators
- Signal-light icons showing claiming state:
  - Available (not claimed)
  - Claimed by you (editable)
  - Claimed by someone else (read-only)

### Library Tab
- Content browser for entities, assets, templates
- Favorites folder
- Search and filter capabilities

---

## 18. Exports & Imports

### Export Formats

| Format           | Description                                         |
|------------------|-----------------------------------------------------|
| JSON             | Full project data as JSON files                     |
| XML              | Full project data with XSD schema                   |
| Excel            | Spreadsheet format for data management              |
| Word             | Document export (flow-to-Word)                      |
| XPS              | Flow & location visual export                       |
| Unity            | Native Unity importer format                        |
| Unreal           | Native Unreal importer format                       |
| Generic Engine   | JSON + Assets archive (BBCode text) for any engine  |

### Export Customization
- **Filter by object type** or template
- **Select properties** to include/exclude
- **Highly customizable rulesets** for each export

### Import Formats
| Format      | Description                                     |
|-------------|-------------------------------------------------|
| Excel       | Import data from spreadsheets                   |
| Final Draft | Import .fdx screenplay files                    |
| Custom      | MDK-based custom importers                      |

### Localization Export/Import
- Export text + VO to Excel for external translation
- Reimport translated Excel back into project
- Proofreading workflow (v4.2): export same language as reference + target

---

## 19. Game Engine Integration

### Unity Importer
- **Automatic data import** from articy export
- Convenient access to objects and properties in C#
- Fully customizable **flow traversal engine**
- Fast automated **script evaluation**
- **Localization via Excel** workflow
- Easy-to-use **Unity components** (drag-and-drop)
- Available on Unity Asset Store
- Supports Unity 2021 LTS through Unity 6000.0

### Unreal Importer
- Easy data import including dialogue and entities
- Full **Blueprint support** (visual scripting)
- Automatic **dialogue traversal engine** (Flow Player actor component)
- Custom editor elements including **articy asset picker**
- **Unreal localization support**
- **Open source** on GitHub - customizable codebase with PR support
- Custom Expresso methods can trigger game-side effects
- Supports UE 5.3, 5.4, 5.5

### Generic Engine Export (Godot, Custom)
- JSON-based export archive
- Includes all generated JSON files + optional assets
- BBCode text format
- Designed for: Godot, custom engines, any engine that parses JSON
- Requires custom import solution on engine side

### Custom Integration (via API)
- .NET library for reading/writing articy project data
- Available as NuGet package ("Articy.API")
- Use cases: automated exports, batch operations, CI/CD integration

---

## 20. Multi-User Collaboration

Requires Multi-User license. All Single-User features included.

### Architecture
```
articy:server (central)
├── User/license management
├── Project metadata
├── SVN repository (internal)
└── Active Directory / LDAP sync (optional)

articy:draft clients (per designer)
├── Local working copy
├── Claim partitions for editing
├── Publish changes
└── Pull changes from others
```

### Partition System (Conflict Prevention)
- Project split into **partitions** (atomic editing units)
- Only one user can **claim** a partition at a time
- Visual indicators (signal-light icons):
  - Green: Available
  - Yellow: Claimed by you (editable)
  - Red: Claimed by someone else (read-only)
- **Publish** your changes to broadcast to all clients
- **Discard** to rollback to server version
- No merge conflicts possible (exclusive editing model)

### Version Control
- **Internal SVN** server integrated into articy:server
- Support for **external SVN** or **Perforce** (stream depots not supported)
- **SSO for Perforce** (v4.2)
- Version history with date picker and text search
- **Rollback** any partition to a previous revision
- **Auto-generated change comments** (articy tracks what changed)
- Custom commit messages also supported

### User Management
- Centralized on articy:server
- Admin role: assign/remove users, claim projects exclusively
- Regular role: read/write access
- Viewer role: read-only access
- Active Directory / LDAP integration for SSO

### Cross-Platform
- Windows and macOS clients can collaborate on the same project (new in X)

### Hosting Options
- Self-hosted articy:server
- Optional articy-hosted service
- Use your own SVN/Perforce infrastructure

---

## 21. Plugin System (MDK)

The Macro Development Kit enables custom plugin development.

### MDK Features
- Available as **NuGet package** with automated project setup
- **DevKit Tools plugin** - automates creation and deployment of MDK plugins
- **Plugin Manager** - activate/deactivate/install plugins
- Develop in **.NET** (C#)

### Plugin Capabilities
| Capability                     | Description                                       |
|--------------------------------|---------------------------------------------------|
| Custom imports/exports         | Add import/export options with config UI          |
| Toolbar extensions (v4.2)      | Add custom buttons to toolbars across views       |
| Asset callbacks (v4.2)         | Respond when assets/files/thumbnails are created  |
| Configuration framework (v4.2) | Persistent plugin data with optional UI           |
| Template modification          | Create/modify templates, features, properties     |
| Property change callbacks      | Detailed callbacks including list changes         |
| Task automation                | Automate repetitive workflows                     |

### Configuration (v4.2)
- **Plugin Configurations Tab** in Project Settings
- Centralized view of all plugin configurations
- Persistable plugin data with minimal code

### Articy API (.NET)
- Read/write articy project data programmatically
- Use cases:
  - Trigger automated exports (CI/CD)
  - Batch-create objects
  - Create localization spreadsheets
  - Generate VO scripts
  - Import from custom Excel spreadsheets
  - Batch-create TTS voice-overs
  - Production reports

---

## 22. Workspace & UI Customization

### Multi-Window Support
- Multiple customizable workspace windows
- Add view panes by dragging horizontally or vertically
- Each pane can show a different view (Flow, Document, Localization, etc.)

### Synchronized Panes
- One pane can "listen" to selection changes in another
- Property Inspector automatically shows selected object's properties
- Useful for flow editing + property monitoring simultaneously

### Workspace Layouts
- Custom pane arrangements
- Save/restore layouts (implicitly through project settings)

### Navigator
- Collapsible sidebar
- Resizable splitter
- Drag-out bar for quick show/hide

---

## 23. Advanced Configuration

### articy Configuration File
- Replace command-line switches
- Modify startup parameters
- Hidden settings for workflow customization
- Full options documented in Help Center

### Autosave
- Enabled by default
- Triggers every 15 minutes
- Configurable

### In-App Help
- Help Center content accessible directly within the application
- Jumpstart page with quick links

---

## 24. Version History (X releases)

### v4.0.0 (Launch - 2024)
- Localization & Voice Over toolset (full)
- AI Extensions (dialogue, barks, preview images)
- Generic Engine Export (JSON for Godot/custom)
- MDK: custom imports/exports with config UI
- Advanced configuration file
- Updated Unity & Unreal importers

### v4.1.0
- Seen/unseen path tracking keywords
- Read-only template properties
- Codebase migration to .NET 8
- DevKit Tools plugin
- articy API as NuGet package
- API: create/modify templates programmatically
- In-App Help
- Performance improvements for large flow graphs
- Requires Subversion 1.9+ for multi-user

### v4.2.0 (August 2025)
- VO Extension plugin (ElevenLabs integration)
- Searchable template dropdowns
- Proofreading-friendly localization export
- SSO for Perforce
- MDK: Configuration Framework
- MDK: Plugin Configurations Tab
- MDK: Toolbar Extensions
- MDK: Asset Callbacks
- MDK: Multi-line strings, multi-object pickers, multi-language selectors

---

## Sources

- [articy:draft X Official Feature List](https://www.articy.com/en/articydraft/feature-list/)
- [articy:draft X Launch Announcement](https://www.articy.com/en/out-now-articydraft-x/)
- [articy:draft X v4.2 Update](https://www.articy.com/en/whats-new-in-articydraft-x-4-2/)
- [articy:draft X v4.2 Press Release](https://www.prnewswire.com/news-releases/articy-software-releases-major-articydraft-x-update-to-boost-narrative-design-workflows-302529168.html)
- [articy:draft X Free Edition](https://www.articy.com/en/articydraft/free/)
- [articy:draft X Pricing (Single-User)](https://www.articy.com/shop/pricing/single-user/)
- [articy:draft X Integration](https://www.articy.com/en/articydraft/integration/)
- [articy:draft X Technical Exports](https://www.articy.com/en/articydraft/integration/techexports/)
- [articy Help Center - Scripting](https://www.articy.com/help/adx/Scripting_in_articy.html)
- [articy Help Center - Conditions & Instructions](https://www.articy.com/help/adx/Scripting_Conditions_Instructions.html)
- [articy Help Center - Flow View](https://www.articy.com/help/adx/UI_View_Flow.html)
- [articy Help Center - Dialogues](https://www.articy.com/help/adx/Flow_Dialog.html)
- [articy Help Center - Templates](https://www.articy.com/help/adx/Templates_Templates.html)
- [articy Help Center - Entities](https://www.articy.com/help/adx/Entities_Sheet.html)
- [articy Help Center - Multi-User](https://www.articy.com/help/adx/MU_Overview.html)
- [articy Help Center - Navigation](https://www.articy.com/help/adx/UI_Navigation.html)
- [articy Help Center - Location Editor](https://www.articy.com/help/adx/Locations_Locations.html)
- [articy Help Center - Simulation Mode](https://www.articy.com/help/adx/Presentation_Simulation.html)
- [articy Help Center - What's New](https://www.articy.com/help/adx/WhatsNew.html)
- [articy:draft on Steam](https://store.steampowered.com/app/570090/articydraft_3/)
- [articy:draft 3 on Capterra](https://www.capterra.com/p/246158/articydraft3/)
- [Articy Unreal Importer (GitHub)](https://github.com/ArticySoftware/Articy3ImporterForUnreal)
- [articy:draft Basics - Entities](https://www.articy.com/en/adx_basics_entities/)
- [articy:draft Basics - Templates I](https://www.articy.com/en/adx_basics_templates1/)
- [articy:draft Basics - Templates II](https://www.articy.com/en/adx_basics_templates2/)
- [articy:draft Basics - Document View](https://www.articy.com/en/adx_basics_documents/)
- [articy:draft Basics - Flow](https://www.articy.com/en/adx_basics_flow1/)
- [articy:draft Basics - Location Editor](https://www.articy.com/en/adx_basics_locations/)
- [articy:draft Basics - Presentation View](https://www.articy.com/en/adx_basics_presentation_view/)
- [articy:draft Basics - Property Inspector](https://www.articy.com/en/adx_basics_property_inpector/)
- [articy:draft Basics - Exports & Imports](https://www.articy.com/en/adx_basics_exports/)
