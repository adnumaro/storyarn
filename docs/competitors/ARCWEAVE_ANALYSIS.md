# Arcweave – Complete Feature Analysis

> **Platform:** Web-based (cloud, browser-only, no install)
> **Developer:** Arcweave (Athens, Greece, founded 2018, seed-stage)
> **Funding:** $850,000 seed round led by Galaxy Interactive
> **URL:** https://arcweave.com

---

## Table of Contents

1. [Product Overview](#1-product-overview)
2. [Boards (Canvas)](#3-boards-canvas)
3. [Elements](#4-elements)
4. [Connections & Labels](#5-connections--labels)
5. [Branches (Conditional Flow)](#6-branches-conditional-flow)
6. [Jumpers (Cross-Board Navigation)](#7-jumpers-cross-board-navigation)
7. [Components (Game Object Database)](#8-components-game-object-database)
8. [Arcscript (Scripting Language)](#9-arcscript-scripting-language)
9. [Variables](#10-variables)
10. [Play Mode](#11-play-mode)
11. [Style Editor & CSS Customization](#12-style-editor--css-customization)
12. [Assets & Multimedia](#13-assets--multimedia)
13. [AI Features](#14-ai-features)
14. [Collaboration](#15-collaboration)
15. [Workspaces, Roles & Permissions](#16-workspaces-roles--permissions)
16. [Localization](#17-localization)
17. [Exports & Imports](#18-exports--imports)
18. [Game Engine Integration](#19-game-engine-integration)
19. [Web API](#20-web-api)
20. [Search, Notes & Comments](#21-search-notes--comments)
21. [Roadmap & Recent Updates](#22-roadmap--recent-updates)

---

## 1. Product Overview

Arcweave is a **web-based, collaborative game design tool** focused on narrative design, content management, and interactive prototyping. It runs entirely in the browser with no downloads or installation required.

**Core pillars:**
- Visual flowchart-based story authoring (boards + elements + connections)
- Component system for game objects (characters, items, locations)
- Built-in scripting language (Arcscript) for logic and conditions
- Real-time collaboration with comments and roles
- Play Mode for instant prototyping and testing
- JSON/CSV export with free engine plugins (Unity, Unreal, Godot)
- AI-powered writing and image generation tools

**Target users:** Game writers, narrative designers, game designers, indie developers, game jam participants, XR/serious games teams.

**Key differentiator:** Cloud-native, zero-install, real-time collaboration. Emphasizes accessibility and speed over feature depth. Especially popular for game jams (72-hour events).

----

## 3. Boards (Canvas)

Boards are the **canvases** where you design story flowcharts. They are the primary organizational unit.

### Features
- Visual drag-and-drop canvas for placing elements, connections, branches, jumpers
- **Multiple boards per project** - use different boards for different chapters, scenes, dialogue trees, mechanics
- **Board folders** - group related boards (e.g., "Dialogue Trees", "Act 1", "Puzzles")
- **Board export** - download as JPEG, PNG, or PDF (with ink-friendly mode)
- Notes and comments can be placed on boards (not part of flow)

### Organization Pattern
```
Project
├── Act 1/
│   ├── Scene 1 (board)
│   ├── Scene 2 (board)
│   └── Scene 3 (board)
├── Dialogue Trees/
│   ├── NPC: Merchant (board)
│   ├── NPC: Guard (board)
│   └── NPC: Blacksmith (board)
├── Game Mechanics/
│   ├── Combat System (board)
│   └── Inventory (board)
└── World Map (board)
```

### Key Difference from articy:draft
articy uses **nested flow** (nodes contain inner flowcharts at infinite depth). Arcweave uses **flat boards** with jumpers to link between them. This is simpler but doesn't provide the same hierarchical depth.

---

## 4. Elements

Elements are the **core content nodes** of Arcweave - each represents a story beat, dialogue line, scene, or game state.

### Properties
| Property         | Description                                                 |
|------------------|-------------------------------------------------------------|
| Title            | Element name (supports rich text)                           |
| Content          | Rich text body (the actual narrative content)               |
| Cover image      | Visual thumbnail/background (drag image asset onto element) |
| Cover video      | Video asset as cover (with playback settings)               |
| Audio            | Attached audio assets (music, VO, SFX)                      |
| Color            | Color theme (right-click to change)                         |
| Components       | Attached component references (characters, items)           |
| Arcscript        | Inline code segments for logic/dynamic text                 |
| Size             | Auto-resize or manual resize via corner/edge drag           |

### Rich Text Formatting
- **Bold** (`**text**` or Ctrl+B)
- **Italic** (`*text*` or Ctrl+I)
- **Underline** (Ctrl+U)
- **Blockquote**
- **Hyperlinks** (embedded links in text)
- **@Mentions** (reference components inline, stays updated if component name changes)

### Arcscript Segments in Content
Elements can contain inline code segments mixed with narrative text:
```
You enter the dark cave.
{ torch_lit = true }
{ if has_map }
  You consult your map and find a shortcut.
{ else }
  You stumble through the darkness.
{ endif }
```

---

## 5. Connections & Labels

Connections are **arrows** linking elements, branches, and jumpers to define narrative flow.

### Features
- Drag from element edge to create connection
- **Labels** - double-click connection to add text (appears as option button in Play Mode)
- Labels support Arcscript segments (dynamic text, conditions)
- Labels support @mentions (component references)
- Multiple connections from one element = multiple player choices
- Visual arrows show flow direction

### Play Mode Behavior
- Each outgoing connection from an element renders as a **choice button**
- The label text becomes the button text
- If no label, a default "Continue" or arrow button appears
- Connections through branches are filtered by conditions

---

## 6. Branches (Conditional Flow)

Branches are the **logic gates** of Arcweave - they evaluate conditions and direct flow accordingly.

### Structure
```
if condition
  → Connection to Element A
elseif other_condition
  → Connection to Element B
else
  → Connection to Element C
```

### Rules
- Exactly **1 mandatory `if`** condition
- **0 or more `elseif`** conditions (unlimited)
- **0 or 1 `else`** (optional, catch-all)
- Each condition has one output connection
- Multiple input connections allowed
- **First satisfied condition wins** (order matters)
- Best practice: use `else` for error/unexpected cases, not for the last logical outcome

### Example
```
if player_has_key
  → "Unlock the door" (Element B)
elseif player_lockpick_skill > 5
  → "Pick the lock" (Element C)
else
  → "The door is locked" (Element D)
```

### Visual
- Branch nodes appear as diamond-shaped items on the board
- Each output is labeled with its condition
- In Play Mode, only satisfied conditions render as available options

---

## 7. Jumpers (Cross-Board Navigation)

Jumpers are **links or aliases** that connect distant elements, even across different boards.

### Features
- Link to any element in any board
- Creates visual reference on current board
- Enables cross-board flow without duplicating elements
- Essential for multi-board project organization

### Use Cases
- Connecting scenes across different boards
- Creating loops back to earlier content
- Linking dialogue trees to main quest flow
- Modular story design

---

## 8. Components (Game Object Database)

Components are Arcweave's system for modeling game objects with structured data.

### What Components Represent
- Characters (PCs, NPCs)
- Items (weapons, keys, potions)
- Locations (towns, dungeons)
- Spells, abilities, skills
- Any abstract concept the project needs

### Component Structure
| Property    | Description                                      |
|-------------|--------------------------------------------------|
| Title       | Component name                                   |
| Cover Image | Visual thumbnail (uploaded or from icon library) |
| Attributes  | Custom data fields (4 types available)           |

### Attribute Types
Components support 4 types of attributes (exact types not fully documented in search results, but include):
- Text fields
- Component references (attach other components for relationships/inventory)
- Custom values

### Icon Library
- **4,000+ free game symbols and icons** built into Arcweave
- Can also upload personal artwork for component covers

### Organization
- Component folders and subfolders in sidebar
- Create custom folder hierarchy
- Searchable and browsable

### Attaching Components to Elements
- Drag component from sidebar onto element
- Creates visual reference in the element
- Component renders in Play Mode alongside content
- @Mention system keeps names synchronized (rename component -> all mentions update)

### Component References
- Track where a component is used across the project
- See all elements and other components that reference it
- Quick navigation to references

### Export
- Components and their attributes are included in JSON export
- Attributes used as metadata for engine integration
- Stable, documented JSON structure

---

## 9. Arcscript (Scripting Language)

Arcweave's built-in scripting language for adding logic, conditions, and dynamic content.

### Usage Contexts
1. **Conditions in branches** - if/elseif/else flow control
2. **Segments in elements** - inline code within narrative content
3. **Segments in connection labels** - dynamic option text

### Data Types
| Type     | Examples              |
|----------|-----------------------|
| Numeric  | `5`, `3.14`, `-1`     |
| String   | `"Tim"`, `"hello"`    |
| Boolean  | `true`, `false`       |

### Assignment Operators
| Operator | Effect                |
|----------|-----------------------|
| `=`      | Assign                |
| `+=`     | Add and assign        |
| `-=`     | Subtract and assign   |
| `*=`     | Multiply and assign   |
| `/=`     | Divide and assign     |
| `%=`     | Modulo and assign     |

### Arithmetic Operators
| Operator | Name           |
|----------|----------------|
| `+`      | Addition       |
| `-`      | Subtraction    |
| `*`      | Multiplication |
| `/`      | Division       |
| `%`      | Modulo         |
| `( )`    | Grouping       |

### Conditional Operators
| Operator        | Meaning               |
|-----------------|-----------------------|
| `==` / `is`     | Equality              |
| `!=` / `is not` | Inequality            |
| `>`             | Greater than          |
| `>=`            | Greater than or equal |
| `<`             | Less than             |
| `<=`            | Less than or equal    |

### Logical Operators
| Operator       | Meaning       |
|----------------|---------------|
| `&&` / `and`   | Both true     |
| `              |               |` / `or`    | At least one true      |
| `!` / `not`    | Negation      |

### Conditional Statements
```arcscript
if age >= 18
  Look at you! All grown up!
  type = "adult"
elseif age > 0
  You are not an adult yet.
  type = "child"
else
  Are you sure you have been born?
  type = "unborn"
endif
```

### Built-in Functions

| Function                | Returns                                        |
|-------------------------|------------------------------------------------|
| `abs(n)`                | Absolute value                                 |
| `sqr(n)`                | Square of n                                    |
| `sqrt(n)`               | Square root of n                               |
| `min(n1, n2, ...)`      | Minimum of series                              |
| `max(n1, n2, ...)`      | Maximum of series                              |
| `random()`              | Decimal in range [0, 1)                        |
| `round(n)`              | Rounds to nearest integer                      |
| `roll(m, n)`            | Roll n dice with m sides (tabletop simulation) |
| `show(e1, e2, ...)`     | Concatenate arguments as string for display    |
| `visits(element)`       | Number of times element has been visited       |
| `reset(v1, v2, ...)`    | Reset named variables to initial values        |
| `resetAll(v1, v2, ...)` | Reset ALL variables except those listed        |
| `resetVisits()`         | Reset all element visit counts to 0            |

### roll() - Dice Rolling
```arcscript
damage = roll(12)           // 1d12
dexterity = roll(6, 3)      // 3d6
player_hp -= roll(max_damage)

if roll(max_damage) > player_hp
  Oops... This isn't good...
endif
```

### show() - Dynamic Text
```arcscript
show("Your score is ", score, "/", max_score, ".")
// Output: "Your score is 3/256."
```

### visits() - Element Visit Tracking
```arcscript
if visits(examine_the_painting) > 1
  You make a mental note of the knight's name.
endif

// Without argument: refers to current element
if visits() > 3
  You've been here too many times.
endif
```

### Error Handling
- Compile-time errors show exclamation mark at element's lower-right corner
- Hover to see error description
- Auto-complete while typing (variables, functions, operators)
- Shortcut to insert segment: `Ctrl/Cmd + Shift + C`

---

## 10. Variables

### Global Variables
- Declared in **Global Variables** panel (bottom-left sidebar)
- Must be declared before use in any script or branch
- Each variable has: name, type, initial value
- Types: **Numeric**, **String**, **Boolean**
- Initial value = value at Play Mode start

### Variable Management
- Create, rename, delete in sidebar panel
- View and edit all variables in one place
- Variables accessible anywhere in Arcscript

### Scope
- All variables are **global** (no local/scoped variables)
- Accessible from any board, element, branch, or connection

---

## 11. Play Mode

Arcweave's built-in **interactive prototype runner** - test stories without a game engine.

### Features
- Press **Play** to instantly run the project as a choice-based game
- Navigate through elements by clicking choice buttons (connection labels)
- **Debugger** panel shows all variables with before/after values per element
- **Start from any element** - not just the beginning
- Tracks variable changes and story logic in real time
- Audio plays automatically on element render
- Video covers play with configurable settings (autoplay, controls, loop)
- Components attached to elements render visually

### Sharing
- Share prototype via **public or private link**
- Anyone with the link can play through the story
- **Embed Play Mode** (Nov 2025) - embed directly into any webpage
- Auto-sync: updates in Arcweave reflected automatically in embedded version

### Debugging
- Variable state panel: see values before and after each element
- Track which branches were taken and why
- Catch logic errors before engine integration
- Visit counts tracked per element

---

## 12. Style Editor & CSS Customization

Transform Play Mode's appearance with CSS.

### How It Works
- Enter Play Mode -> click palette icon (Style Editor)
- Write CSS directly in the editor panel
- **Real-time preview** - changes appear instantly
- Save CSS to project

### Targetable CSS Classes
| Class                                      | Targets                       |
|--------------------------------------------|-------------------------------|
| `.prototype__wrapper`                      | Outer container               |
| `.prototype__body`                         | Text content + option buttons |
| `.prototype__text`                         | Text content only             |
| `.prototype__text .editor .editor-content` | Rich text content             |
| `.prototype__media`                        | Cover image/video             |
| `.prototype__components .comp`             | Attached components           |

### Visual Novel Mode
Can be styled into a full **visual novel** interface:
- Full-screen background images
- Character sprites at bottom
- Dialogue box with scrolling text
- "Hijack" formatting tools (bold/italic/underline generate HTML tags targetable with CSS)

### Templates
- **Visual Novel template** (Sep 2025) - pre-built style for VN format
- **Serious Games template** - cybersecurity awareness scenario format

---

## 13. Assets & Multimedia

### Asset Types
| Type    | Supported Formats  | Usage                                           |
|---------|--------------------|-------------------------------------------------|
| Images  | Common formats     | Element covers, component covers, board visuals |
| Audio   | Common formats     | Music, voice-over, SFX on elements              |
| Video   | Common formats     | Element covers with playback settings           |

### Image Assets
- Upload personal artwork or use built-in icon library (4,000+ icons)
- Drag onto element to set as cover
- Thumbnail on board, full-size in Play Mode
- AI Image Generator can create images from prompts

### Audio Assets
- Attach to elements (drag from Assets sidebar)
- Play automatically in Play Mode when element renders
- Configurable: loop or one-shot
- Drag between elements to move
- Remove by dragging to empty board area (doesn't delete asset)

### Video Assets (Jun 2025)
- Set as element cover
- Playback settings: autoplay, show controls, loop
- Plays in Play Mode

### Asset Management
- **Assets tab** in sidebar
- Create folders and subfolders
- Deleting asset removes all attachments throughout project
- Assets included in export (ZIP download)

---

## 14. AI Features

Arcweave invested heavily in AI features through 2025, powered by their Galaxy Interactive funding.

### Element Generator (Mar 2025)
- Right-click element -> AI -> "Generate element"
- Enter prompt describing desired content
- AI generates element with **title and content**
- Uses project context for tone/structure alignment
- Useful for overcoming writer's block

### Element Enhancer (Mar 2025)
- Right-click existing element -> AI -> "Enhance"
- AI refines and improves existing content
- Maintains creative direction while polishing

### Image Generator (Mar 2025)
- Generate images from text prompts
- Select **size and orientation**
- **AI Settings guidelines** - set project-wide art style rules
  - Guidelines apply to all image generations in the project
  - Specify art style, mood, restrictions
- Generated images usable as element/component covers

### Design Assistant (Mar 2025)
- Project-aware **AI chat assistant**
- Analyzes project structure
- Suggests improvements
- Checks narrative consistency
- Context-aware (understands your specific project)

### Cover Generator
- Auto-generate covers for elements and components
- Style guide ensures visual consistency
- Matches story mood automatically

### Experimental: AI Drama Manager
- Research project exploring LLM + human-authored story frameworks
- Adaptive, responsive narratives
- Maintains coherence while allowing player freedom
- Not yet a production feature

### Control
- AI features are tools, not requirements
- User maintains full creative control
- Can be used selectively per element

---

## 15. Collaboration

### Real-Time Editing
- Multiple users edit the **same project simultaneously**
- See teammates' cursors moving in real-time
- Changes appear instantly for all collaborators
- No partition/locking system (unlike articy:draft)
- No merge conflicts to resolve

### Comments
- Leave comments directly on board elements
- Tag collaborators with @mentions
- Get notified of replies
- Use for feedback, questions, task assignments

### Notes
- Sticky-style notes on boards
- For communication, reminders, context
- Not part of the narrative flow (cannot be connected)
- Separate from elements and connections

### In-App Chat
- Built-in chat to communicate without leaving Arcweave
- Eliminates switching to Discord/Slack for quick discussions

### Access Levels
| Role            | Can Do                                   |
|-----------------|------------------------------------------|
| Owner           | Full control over workspace and projects |
| Editor          | Create, edit, delete content             |
| Commenter       | View and leave comments                  |
| Viewer          | View and play only                       |

---

## 16. Workspaces, Roles & Permissions

### Workspace Model
- Each workspace is an **independent environment**
- Contains: projects, members, settings, billing, API keys
- One user account can belong to multiple workspaces
- Three types: Basic, Pro, Team

### Member Types
| Type     | Access                                   |
|----------|------------------------------------------|
| Member   | Global access to all workspace projects  |
| Guest    | Access to specific invited projects only |

### Default Roles
- **Owner** - full control (billing, settings, members)
- **Editor** - create and edit content
- **Viewer** - view and play only

### Custom Roles (Team plan only)
- Create named custom roles
- Toggle individual permissions on/off
- Assign to any member
- Fine-grained access control

### Workspace Dashboard Sections
| Section   | Purpose                                     |
|-----------|---------------------------------------------|
| Projects  | View and manage all projects                |
| People    | Manage members, guests, invitations         |
| Roles     | View/create roles and permissions           |
| Settings  | Name, icon, billing email                   |
| Billing   | History and usage monitoring                |
| API       | Manage API keys                             |

---

## 17. Localization

**Status:** Launched January 2026 (was in beta through 2025). Available on Team plan.

### Features
- Multi-language content management in one workspace
- All languages viewable side-by-side
- Translators see content in context (understand full interaction flow)
- **Language selection in Play Mode** - players choose language
- **Export per language** to JSON for engine integration
- Collaborative translation workflow
- Updates go live instantly (no content duplication)

### Voice Over Workflow
- Export structured scripts for VO recording
- Create tracking spreadsheets for recording engineers
- Content and audio synchronized in export
- String IDs for localization systems

### Compared to articy:draft
- Less mature (just launched, articy has had it since v4.0)
- No DeepL integration
- No localization state management (final/in-progress/outdated)
- No localization report (word/line counts)
- No dedicated localization view (articy has one)
- Simpler but functional for basic multi-language needs

---

## 18. Exports & Imports

### Export Formats
| Format          | Plan Required   | Description                                                                        |
|-----------------|-----------------|------------------------------------------------------------------------------------|
| JSON            | All             | Full project data (elements, connections, branches, variables, components, assets) |
| CSV             | All             | Spreadsheet format, produces ZIP, HTML-encoded text                                |
| XLSX (Excel)    | Pro+            | One sheet per item type                                                            |
| JPEG/PNG/PDF    | All             | Board visual export (PDF has ink-friendly mode)                                    |
| ZIP             | All             | Project data + all assets bundled                                                  |
| Markdown        | All (Jan 2026)  | For sharing, reviews, documentation                                                |

### JSON Export Structure
Includes:
- All elements with content, covers, audio references
- All connections with labels
- All branches with conditions
- All jumpers with targets
- All variables with initial values
- All components with attributes
- Asset references (images, audio, video)
- Board structure and metadata

### Import
- No specific import formats documented (e.g., no Final Draft import)
- Projects can be restored via **Project History** (Dec 2025)

---

## 19. Game Engine Integration

### Unity Plugin
- **Free** plugin on Unity Asset Store + GitHub
- Import from JSON file (all plans) or Web API (Team)
- Click **Generate Project** to import
- Shows project name and global variables in inspector
- Also integrates with **Dialogue System for Unity** (Pixel Crushers) via built-in Arcweave importer

### Unreal Engine Plugin
- **Free** plugin (UE 5.0+)
- Import from JSON (all plans) or Web API (Team)
- Primary class: `UArcweaveSubsystem`
- Functions exposed to both **Blueprints and C++**
- Read, modify, and retrieve data from imported projects
- Available on GitHub (open source)

### Godot Engine Plugin
- **Free** plugin (Godot 4.0+, **.NET version required**)
- Import from JSON (all plans) or Web API (Team)
- Custom `ArcweaveNode` class (inherits Godot Node)
- Available on Godot Asset Library + GitHub
- Works from both GDScript and C# via cross-language scripting

### Defold Integration
- Community plugin **DefArc** (third-party)
- JSON parser and helper module for Lua
- Branching, interactive, or linear conversations

### General Pattern
```
Arcweave → Export JSON → Engine Plugin → Runtime Data
                or
Arcweave → Web API → Engine Plugin → Runtime Data (Team only)
```

---

## 20. Web API

**Available on Team plan only.**

### Features
- RESTful API with token authentication
- Fetch latest project state at runtime
- Sync updates between Arcweave and game without manual exports
- API tokens managed in workspace dashboard

### Endpoints
```
GET /api/{project_hash}/json    → Full project as JSON
GET /api/{project_hash}/godot   → Transpiled .gd format
```

### Use Cases
- CI/CD integration (automated builds)
- Live content updates in game
- Custom tooling and pipelines
- Runtime data fetching

---

## 21. Search, Notes & Comments

### Search
- **Global search** across all project items
- Find boards, elements, notes, components, and more
- Instant results

### Notes
- Sticky-note style items on boards
- Not connected to flow (purely informational)
- For team communication, reminders, design notes

### Comments
- Attached to specific elements or boards
- @Mention team members
- Notification on replies
- Thread-based discussions

---

## 22. Roadmap & Recent Updates

### Coming Next (Planned)

| Feature               | Description                                         |
|-----------------------|-----------------------------------------------------|
| Document boards       | Write in article format (long-form text)            |
| Component templates   | Attribute inheritance from multiple templates       |
| Minimap               | Board overview and quick navigation                 |
| Screenplay formatting | Enable screenplay text formatting in elements/notes |

### Recent Updates (Completed)
| Feature                       | Date       | Description                               |
|-------------------------------|------------|-------------------------------------------|
| Localization                  | Jan 2026   | Multi-language translation & export       |
| Markdown export               | Jan 2026   | For sharing, reviews, documentation       |
| Project History               | Dec 2025   | Revert to previous project states         |
| Embed Play Mode               | Nov 2025   | Embed play mode in external webpages      |
| Keyboard shortcuts            | Sep 2025   | Mouse-free navigation/editing             |
| Visual Novel template         | Sep 2025   | Pre-built style for visual novel format   |
| Video assets                  | Jun 2025   | Upload/embed video with playback settings |
| Play Mode Style Editor        | May 2025   | CSS customization for prototypes          |
| AI Image Generator            | Mar 2025   | Generate images from text prompts         |
| AI Element Generator/Enhancer | Mar 2025   | AI-assisted content creation/refinement   |
| AI Design Assistant           | Mar 2025   | Project-aware AI chat                     |

---

## Sources

- [Arcweave Official Website](https://arcweave.com/)
- [Arcweave Features Page](https://arcweave.com/features)
- [Arcweave Pricing](https://arcweave.com/pricing)
- [Arcweave Roadmap](https://arcweave.com/roadmap)
- [Arcweave Documentation](https://docs.arcweave.com/)
- [Arcweave - What is Arcweave?](https://docs.arcweave.com/introduction/what-is-arcweave)
- [Arcweave - Project Items](https://docs.arcweave.com/project-items/overview)
- [Arcweave - Arcscript](https://docs.arcweave.com/project-items/arcscript)
- [Arcweave - Variables](https://arcweave.com/docs/1.0/variables)
- [Arcweave - Branches](https://docs.arcweave.com/project-items/branches)
- [Arcweave - Jumpers](https://docs.arcweave.com/project-items/jumpers)
- [Arcweave - Components](https://arcweave.com/docs/1.0/components)
- [Arcweave - Elements](https://arcweave.com/docs/1.0/elements)
- [Arcweave - Connections](https://arcweave.com/docs/1.0/connections)
- [Arcweave - Play Mode](https://arcweave.com/docs/1.0/play-mode)
- [Arcweave - Export](https://arcweave.com/docs/1.0/export)
- [Arcweave - Web API](https://arcweave.com/docs/1.0/api)
- [Arcweave - AI Tools](https://docs.arcweave.com/project-tools/ai-features/overview)
- [Arcweave - Image Generator](https://docs.arcweave.com/project-tools/ai-features/image-generator)
- [Arcweave - Element Generator](https://docs.arcweave.com/project-tools/ai-features/element-generator)
- [Arcweave - Workspaces](https://docs.arcweave.com/workspaces/overview)
- [Arcweave - Workspace Billing](https://arcweave.com/docs/1.0/billing)
- [Arcweave - Boards](https://arcweave.com/docs/1.0/boards)
- [Arcweave - Assets](https://arcweave.com/docs/1.0/assets)
- [Arcweave - Sharing](https://arcweave.com/docs/1.0/sharing)
- [Arcweave Integrations](https://arcweave.com/integrations)
- [Arcweave - Unity Integration](https://docs.arcweave.com/integrations/unity)
- [Arcweave - Unreal Integration](https://docs.arcweave.com/integrations/unreal)
- [Arcweave - Godot Integration](https://docs.arcweave.com/integrations/godot)
- [Arcweave Unreal Plugin (GitHub)](https://github.com/arcweave/arcweave-unreal-plugin)
- [Arcweave Blog - Visual Novel Style](https://blog.arcweave.com/how-to-create-a-visual-novel-style-in-arcweaves-play-mode)
- [Arcweave Blog - CSS Customization](https://blog.arcweave.com/how-to-customize-your-arcweave-game-using-css)
- [Arcweave Blog - Arcscript Tutorial](https://blog.arcweave.com/add-code-segments-to-your-arcweave-project)
- [Arcweave Blog - Advanced Branches](https://blog.arcweave.com/use-arcweaves-branches-to-condition-your-story-flow)
- [Arcweave Blog - Workspaces](https://blog.arcweave.com/arcweave-introduces-workspaces)
- [Arcweave Blog - Game Jam Workflow](https://blog.arcweave.com/from-zero-to-playable-the-48-hour-game-jam-narrative-workflow)
- [Arcweave Blog - Arcjam 2025](https://blog.arcweave.com/game-writing-sig-arcjam-2025-retrospective)
- [Arcweave Blog - Monster and Monster Case Study](https://blog.arcweave.com/how-monster-and-monster-uses-arcweave-to-automate-3000-lines-of-dialogue)
- [Arcweave Blog - Seed Funding](https://blog.arcweave.com/seed-funding)
- [Arcweave - What's New](https://arcweave.com/whats-new)
- [Arcweave on Capterra](https://www.capterra.com/p/189507/Arcweave/)
- [DefArc - Defold Plugin (GitHub)](https://github.com/paweljarosz/defarc)
