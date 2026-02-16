# Yarn Spinner - Complete Feature Analysis

> **Version analyzed:** Yarn Spinner 3.1 (December 2025)
> **Platform:** Cross-platform (VS Code extension + game engine plugins)
> **Developer:** Secret Lab (Australia)
> **License:** MIT (open source core) + paid add-ons
> **URL:** https://yarnspinner.dev
> **GitHub:** https://github.com/YarnSpinnerTool/YarnSpinner

---

## Table of Contents

1. [Product Overview](#1-product-overview)
3. [The Yarn Language](#3-the-yarn-language)
4. [Nodes & Lines](#4-nodes--lines)
5. [Options & Branching](#5-options--branching)
6. [Flow Control](#6-flow-control)
7. [Variables](#7-variables)
8. [Smart Variables](#8-smart-variables)
9. [Enums](#9-enums)
10. [Functions](#10-functions)
11. [Commands](#11-commands)
12. [Markup & Tags](#12-markup--tags)
13. [Line Groups](#13-line-groups)
14. [Node Groups & Saliency](#14-node-groups--saliency)
15. [Shadow Lines](#15-shadow-lines)
16. [VS Code Extension (Editor)](#16-vs-code-extension-editor)
17. [Try Yarn Spinner (Web Playground)](#17-try-yarn-spinner-web-playground)
18. [Localization](#18-localization)
19. [Voice Over & Audio](#19-voice-over--audio)
20. [Unity Integration](#20-unity-integration)
21. [Godot Integration](#21-godot-integration)
22. [Unreal Engine Integration](#22-unreal-engine-integration)
23. [Paid Add-Ons](#23-paid-add-ons)
24. [2026 Roadmap](#24-2026-roadmap)
25. [Notable Games](#25-notable-games)

---

## 1. Product Overview

Yarn Spinner is a **dialogue system and scripting language** for building interactive narrative in games. Unlike articy:draft (desktop visual tool) or Arcweave (web-based visual tool), Yarn Spinner is primarily a **text-based scripting language** with an editor extension, designed to be deeply integrated into game engines.

**Core pillars:**
- Text-based dialogue scripting language (Yarn)
- VS Code extension with syntax highlighting, graph view, and preview
- Deep integration with Unity, Godot, and Unreal Engine
- Localization and voice-over support built into the design
- Open source (MIT license) with paid add-ons

**Target users:** Game writers, narrative designers, dialogue system programmers, indie developers.

**Key differentiator:** Writer-friendly scripting language that looks like a screenplay. No visual node editor as the primary interface - writers work in text, but get a graph visualization. Deeply code-oriented, designed for programmers to extend.

**Philosophy:** "It's easy for writers to use, and has powerful features for programmers."

---

## 3. The Yarn Language

Yarn is a **screenplay-like scripting language** for writing interactive dialogue. Files use the `.yarn` extension.

### Basic Structure
```yarn
title: Greeting
---
Player: Hey, Sally. How are you?
Sally: I'm great! Thanks for asking.
    -> Tell me about yourself
        Sally: I'm an NPC in a game!
    -> Goodbye
        Sally: See you later!
===
```

### Key Characteristics
- **Plain text** - looks like a screenplay
- **Nodes** contain dialogue passages
- **Lines** are individual dialogue statements
- **Options** (`->`) create player choices
- **Inline expressions** (`{$variable}`) for dynamic text
- **Commands** (`<<command>>`) for game integration
- **Conditions** (`<<if>>`) for logic
- **Full programming language** - not just a markup format

---

## 4. Nodes & Lines

### Nodes
Nodes are the fundamental organizational unit. Each node represents a block of dialogue.

```yarn
title: MyNode
tags: greeting casual
custom_header: some_value
---
Content goes here.
===
```

#### Node Structure
| Part     | Required | Description                                          |
|----------|----------|------------------------------------------------------|
| `title:` | Yes      | Unique name (letters, numbers, underscores only)     |
| Headers  | No       | Key-value pairs for metadata                         |
| `---`    | Yes      | Separator between headers and body                   |
| Body     | Yes      | Dialogue lines, options, commands, logic              |
| `===`    | Yes      | End-of-node marker                                   |

#### Node Headers
- `title:` - unique identifier (required)
- `tags:` - space-separated tags
- `when:` - conditions for node groups (e.g., `when: once`, `when: $has_sword`)
- `style:` - visual style (e.g., `style: note` for sticky notes)
- `color:` - color coding in graph view
- Custom headers with any `key: value` pairs

### Lines
Each line of text in a node body is a dialogue line delivered to the player.

```yarn
Player: Hey there!
Sally: Hello! How can I help?
```

- **Character name prefix** - `Character: text` format
- **Inline expressions** - `{$player_name}` expanded at runtime
- **Tags** - `#tag1 #tag2` appended to line end
- **Line IDs** - `#line:unique_id` for localization

---

## 5. Options & Branching

### Shortcut Options
Options create player choices without needing separate nodes:

```yarn
Sally: What would you like?
-> I'd like a coffee
    Sally: Coming right up!
-> I'd like tea
    Sally: Of course!
-> Nothing, thanks
    Sally: No problem.
```

### Nested Options
Options can be nested for multi-level choices:

```yarn
-> Tell me about the quest
    Sally: Which quest?
    -> The dragon quest
        Sally: Head to the mountains.
    -> The treasure quest
        Sally: Check the old ruins.
-> Goodbye
    Sally: See you!
```

### Conditional Options
Restrict availability based on conditions:

```yarn
-> Sure I am! The boss knows me! <<if $reputation > 10>>
-> I'll come back later
```

- Unavailable options are still delivered to the game
- Game decides: hide them entirely or show greyed out
- Enables "what could have been" design pattern

### Option Fallthrough (v3.1)
When ALL options are unavailable, Yarn Spinner skips the options group and runs the next content after them. Prevents dead ends.

---

## 6. Flow Control

### Jump
Move to a different node:
```yarn
<<jump AnotherNode>>
```

### Detour (v3)
Temporarily visit a node then return:
```yarn
<<detour SideConversation>>
// After SideConversation ends, execution continues here
```

- `<<return>>` - return early from a detoured node
- Detours can be nested (detour within a detour)
- If a detoured node uses `<<jump>>`, the return stack is cleared

### If / ElseIf / Else
```yarn
<<if $health > 50>>
    Player: I feel great!
<<elseif $health > 20>>
    Player: I've been better.
<<else>>
    Player: I need a doctor...
<<endif>>
```

- Expressions must return boolean
- Supports logical operators: `and`, `or`, `>=`, `<`, `==`, `!=`, `not`
- Multiple `elseif` branches allowed

### Once (v3)
Run content only one time:
```yarn
<<once>>
    Sally: Welcome! I haven't seen you before.
<<endonce>>
Sally: What can I help with?
```

### Stop
End dialogue immediately:
```yarn
<<stop>>
```

### Wait
Pause dialogue:
```yarn
<<wait 2.5>>
```

---

## 7. Variables

### Types
| Type     | Example          | Default   |
|----------|------------------|-----------|
| Number   | `42`, `3.14`     | `0`       |
| String   | `"hello"`        | `""`      |
| Boolean  | `true`, `false`  | `false`   |

### Declaration
```yarn
<<declare $player_name = "Alex">>
<<declare $health = 100>>
<<declare $has_key = false>>
```

### Assignment
```yarn
<<set $health = 80>>
<<set $gold += 50>>
<<set $has_key = true>>
```

### Operators
| Operator | Description      |
|----------|------------------|
| `=`      | Assign           |
| `+=`     | Add assign       |
| `-=`     | Subtract assign  |
| `*=`     | Multiply assign  |
| `/=`     | Divide assign    |
| `%=`     | Modulo assign    |

### Scope
- All variables are **global** (accessible across all nodes and files)
- Names start with `$` (dollar sign)
- Names are **case sensitive**
- **Implicit declaration** - if used without declaring, Yarn Spinner infers type and default value

### Inline Expressions
```yarn
Player: I have {$gold} gold pieces.
Sally: That's {"not " if $gold < 10}enough!
```

---

## 8. Smart Variables

Smart variables are **read-only computed variables** that recalculate every time they're accessed.

### Syntax
```yarn
<<declare $is_powerful = $strength > 50 && $magic_ability >= 20>>
<<declare $can_afford_pie = $player_money > 10>>
<<declare $has_enough_materials = $wood >= 5 && $nails >= 10>>
<<declare $can_build_chair = $has_enough_materials && $has_required_skill>>
```

### Characteristics
- **Read-only** - cannot be set with `<<set>>`
- **Auto-updating** - recalculated on every access
- **Composable** - smart variables can reference other smart variables
- **Accessible from code** - available via VariableStorage in C#/GDScript

### Use Cases
| Use Case                 | Example                                         |
|--------------------------|-------------------------------------------------|
| Relationship check       | `$sam_relationship_score > 50`                  |
| Resource check           | `$wood >= 5 && $nails >= 10`                    |
| Chained logic            | `$has_materials && $has_skill`                  |
| Time-based state         | `$game_hour >= 18 && $game_hour < 22`           |
| Quest status             | `$killed_dragon && $has_treasure`               |

---

## 9. Enums

Enums (v3) constrain variables to a predefined set of values.

### Syntax
```yarn
<<enum Food>>
    <<case Apple>>
    <<case Orange>>
    <<case Banana>>
<<endenum>>

<<declare $favorite_food = Food.Apple>>
```

### Features
- Variables can only be set to valid enum values
- Compile-time type checking
- Shorthand notation when context is clear: `<<set $favorite_food = .Banana>>`
- Generates C# enum declarations in Unity
- Usable in conditions: `<<if $favorite_food == Food.Apple>>`

---

## 10. Functions

Functions return values that can be used in expressions, conditions, and inline text.

### Built-in Functions
| Function                    | Returns                                |
|-----------------------------|----------------------------------------|
| `visited("NodeName")`       | `true` if node has been visited before |
| `visited_count("NodeName")` | Number of times node has been visited  |
| `string(value)`             | Convert any value to string            |
| `number(value)`             | Convert to number (if possible)        |
| `bool(value)`               | Convert to boolean (if possible)       |
| `dice(sides)`               | Random integer 1 to sides              |
| `random()`                  | Random float 0 to 1                    |
| `random_range(min, max)`    | Random number in range                 |
| `round(n)`                  | Round to nearest integer               |
| `round_places(n, places)`   | Round to decimal places                |
| `floor(n)`                  | Round down                             |
| `ceil(n)`                   | Round up                               |
| `inc(n)`                    | Increment by 1                         |
| `dec(n)`                    | Decrement by 1                         |
| `decimal(n)`                | Decimal portion of number              |
| `int(n)`                    | Integer portion of number              |

### Custom Functions
- Define in C# (Unity), GDScript/C# (Godot), or C++ (Unreal)
- Yarn scripts call them like built-in functions
- Type-checked at compile time (v3)
- Auto-complete in VS Code extension
- Functions are pure (no side effects - use commands for that)
- Results may be cached by Yarn Spinner

### Usage
```yarn
<<if visited("TavernGreeting")>>
    Bartender: Back again, are we?
<<else>>
    Bartender: Welcome, stranger!
<<endif>>

Player: I rolled a {dice(20)}!
```

---

## 11. Commands

Commands send instructions from Yarn scripts to the game engine.

### Built-in Commands
| Command        | Description                    |
|----------------|--------------------------------|
| `<<wait N>>`   | Pause dialogue for N seconds   |
| `<<stop>>`     | End dialogue immediately       |
| `<<jump N>>`   | Jump to node N                 |
| `<<detour N>>` | Visit node N then return       |
| `<<return>>`   | Return early from detour       |
| `<<set>>`      | Set variable value             |
| `<<declare>>`  | Declare variable               |
| `<<once>>`     | Run enclosed content only once |

### Custom Commands
- Defined in game code (C#, GDScript, C++/Blueprint)
- Called from Yarn scripts with `<<commandName args>>`
- Type-checked at compile time (v3)
- Documentation from code comments shown in VS Code hover
- Ctrl+click navigates to C# source code

### Example
```yarn
// In Yarn script:
<<fadeIn 2>>
Player: Where am I?
<<playSound "ambient_forest">>
<<setExpression Player "confused">>
```

```csharp
// In Unity C#:
[YarnCommand("fadeIn")]
public void FadeIn(float duration) { ... }

[YarnCommand("playSound")]
public void PlaySound(string soundName) { ... }
```

---

## 12. Markup & Tags

### Markup (Inline Attributes)
Apply attributes to ranges of text for custom rendering:

```yarn
Why, <wave size=5>hello</wave> there!
Player: I'm <color=#ff0000>very angry</color> right now!
```

- Produces plain text + ordered collection of attribute ranges
- Game decides how to render (wave effect, color, shake, etc.)
- Type-checked at compile time (v3)
- Properties can be constants, variables, or expressions

### Line Tags
Tags add metadata to lines (not shown to players):

```yarn
Sally: Hello there! #greeting #important
Player: Hi! #line:player_greeting_01
```

- Start with `#`
- Cannot contain spaces
- Multiple tags per line allowed
- Must be on same line
- `#line:id` - unique line ID for localization
- `#lastline` - auto-added by compiler before options

### Node Tags
```yarn
title: MyNode
tags: greeting casual important
---
```

### Metadata
Lines can carry metadata accessible to the game and included in exported CSV metadata files.

---

## 13. Line Groups

Line groups provide **computer-selected content** (as opposed to player-selected options).

### Syntax
```yarn
=> It's a lovely day! <<if $weather == "sunny">>
=> The rain is really coming down. <<if $weather == "rainy">>
=> I don't have anything to say. <<if $nothing_to_say>>
```

### Characteristics
- Use `=>` prefix (instead of `->` for player options)
- Computer picks which line to run (not the player)
- Conditions filter available lines
- Can combine with `once` to run a line only once
- Great for **barks** - short reactive dialogue

### Use Cases
- NPC ambient dialogue
- Barks and callouts
- Random greetings
- Context-sensitive reactions

---

## 14. Node Groups & Saliency

### Node Groups (v3)
Multiple nodes with the same name, each with `when:` conditions:

```yarn
title: Greeting
when: once
---
Sally: Welcome! First time here?
===

title: Greeting
when: $has_quest
---
Sally: Have you completed the quest?
===

title: Greeting
when: always
---
Sally: Hello again!
===
```

### `when:` Conditions
| Condition          | Behavior                                |
|--------------------|-----------------------------------------|
| `when: once`       | Run only once                           |
| `when: always`     | Always eligible                         |
| `when: $variable`  | Eligible when variable is true          |
| `when: expression` | Eligible when expression evaluates true |

### Saliency Strategy
When multiple nodes in a group are eligible, Yarn Spinner uses a **saliency strategy** to pick:
- Considers number of conditions that passed
- **Complexity scoring** - counts boolean operators + 1 if `once` condition
- `always` has complexity 0 (lowest priority)
- More specific conditions are preferred
- Game code can check how many nodes are eligible
- Customizable strategy

### Difference from Line Groups
- Line groups: short, single-line barks (computer picks a line)
- Node groups: longer passages with full dialogue (computer picks a node)

---

## 15. Shadow Lines

Shadow lines (v3) deduplicate repeated dialogue for localization.

```yarn
Sally: Hello! #line:sally_hello
...
// In another node, same line reused:
Sally: Hello! #line:sally_hello_shadow #shadow:sally_hello
```

### Characteristics
- Must have identical text to source line
- Share the same localization entry (no duplicate translations)
- Can have different tags (except `#shadow:` and `#line:`)
- Reduces translation workload

---

## 16. VS Code Extension (Editor)

The primary authoring tool for Yarn Spinner scripts.

### Syntax Highlighting
- Full color-coded syntax highlighting for `.yarn` files
- Commands, variables, options, comments all distinctly colored

### Graph View
- Interactive **node graph** visualization
- Displays nodes as boxes, connections as arrows
- `<<jump>>` commands visualized as connection lines
- Click and drag to rearrange nodes
- **Add Node button** creates new nodes from graph view
- Jump between sections by clicking nodes
- Export as `.dot` file for external graph tools

### Autocomplete / IntelliSense
- Suggestions for node names, variables, commands
- Hover documentation for commands (pulls from C# doc comments)
- Hover info for variables (default value, where defined)
- Type checking and error reporting

### Preview
- **Play through dialogue** directly in VS Code
- No game engine required
- Test branching paths interactively
- **Export as HTML** - standalone playable file to share with team

### Error Detection
- Red underlines for script problems
- Full Yarn Spinner compiler running in background
- Ctrl+click navigation:
  - Click variable -> go to declaration
  - Click node name -> go to node
  - Click command -> go to C# source code

### Collaboration
- Works with **VS Code Live Share**
- Shared workspace gets full extension features (syntax highlighting, graph view)

### Node Styling
- `style: note` header turns node into sticky note
- `color:` header sets node color in graph view

---

## 17. Try Yarn Spinner (Web Playground)

### Features
- **Browser-based** playground at try.yarnspinner.dev
- Write and test Yarn scripts without installing anything
- Instant preview of dialogue
- No account required

### Use Cases
- Writers drafting scenes
- Teachers using in classes
- Developers prototyping on the go
- Quick testing of script ideas

---

## 18. Localization

Localization is built into Yarn Spinner's core design - not an afterthought.

### Workflow
1. Set **base language** for your scripts
2. Add **line ID tags** to each line (auto-generated or manual)
3. **Export strings file** (CSV) for translation
4. Translators fill in target language columns
5. Import translated strings files
6. Line Provider loads correct language at runtime

### Line IDs
```yarn
Sally: Hello! #line:sally_hello_01
Player: How are you? #line:player_greeting_01
```

- Auto-generated via "Add Line Tags to Scripts" in Yarn Project
- Unique across entire project
- Stable (survive script edits)

### Strings Files (CSV)
| id                      | text          | file          | node     | lineNumber  |
|-------------------------|---------------|---------------|----------|-------------|
| line:sally_hello_01     | Hello!        | greeting.yarn | Greeting | 3           |
| line:player_greeting_01 | How are you?  | greeting.yarn | Greeting | 4           |

- Only translate `text` column
- Don't modify `id` column
- "NEEDS UPDATE" marker added when original text changes

### Metadata File
- Companion to strings file
- Contains: id, file, node, lineNumber, metadata
- Provides context for translators

### Unity Localization Options
1. **Built-in system** - simple, uses Yarn Project's strings files
2. **Unity Localization package** - advanced, integrates with Unity's localization system, supports asset tables

### Runtime Language Switching
- Line Provider fetches correct language strings
- Switch languages seamlessly at runtime
- Support unlimited number of languages

---

## 19. Voice Over & Audio

Voice over is **intimately tied to localization** in Yarn Spinner's design.

### Philosophy
> "If you want text-only dialogue in a single language, you don't need to do anything. If you want anything else (including voice over), you need localization."

### Workflow
1. Set up localization (line IDs, base language)
2. **Line IDs become audio file names** (e.g., `line:tom-1.mp3`)
3. Create audio assets per line per language
4. Line Provider delivers audio alongside text at runtime

### Unity Asset Tables
- Create **Asset Table** entries keyed by line ID
- Map line IDs to audio clips
- Supports per-language audio (different recordings per language)
- Line Provider serves correct audio for current language

### Bevy Engine Convention
- Audio files named after line ID: `assets/dialogue/en-US/13032079.mp3`
- Asset providers automatically resolve path

### Text Animation
- **Text Animator integration** (paid version)
- Typewriter effects with configurable speed
- Animated text effects via markup (wave, shake, color)
- Supports Text Animator 2 & 3

---

## 20. Unity Integration

The most mature and feature-complete engine integration.

### Installation
- Unity Asset Store or Itch.io
- Add via: **GameObject > Yarn Spinner > Dialogue System**

### Core Components
| Component          | Description                                                              |
|--------------------|--------------------------------------------------------------------------|
| Dialogue Runner    | Bridge between Yarn scripts and game. Loads, runs, manages Yarn Projects |
| Line View          | Displays single lines of dialogue in Unity UI canvas                     |
| Options List View  | Displays player options as selectable list                               |
| Option View        | Individual option button (used by Options List View)                     |
| Variable Storage   | Stores and retrieves variable values                                     |
| Line Provider      | Fetches localized text and assets (audio) for current language           |

### Dialogue Runner Settings
| Setting               | Description                                             |
|-----------------------|---------------------------------------------------------|
| Yarn Project          | The compiled Yarn project to run                        |
| Dialogue Views        | List of views that display content                      |
| Variable Storage      | Where variables are stored (in-memory default)          |
| Line Provider         | How localized content is fetched                        |
| Auto Continue         | Advance lines automatically when views finish           |
| Run Selected Options  | Re-run chosen option as a line                          |
| Verbose Logging       | Log state changes to Console                            |

### Line View Features
- Character name in separate text object (TextMeshPro)
- Auto-advance or manual advancement
- Fade in/out effects (Canvas Group opacity)
- Typewriter effect (configurable speed)
- "Continue" button integration

### Custom Dialogue Views
- Subclass `DialogueViewBase`
- Full control over how lines and options are presented
- Multiple views per Dialogue Runner (e.g., one for lines, one for options)

### Custom Commands & Functions
```csharp
[YarnCommand("fadeIn")]
public void FadeIn(float duration) { /* ... */ }

[YarnFunction("playerHealth")]
public static int PlayerHealth() { return currentHealth; }
```

### Async Support (v3.1)
- `StartDialogue` and `Stop` are now async
- Dialogue presenters complete initialization before scene changes
- Better handling of transitions

---

## 21. Godot Integration

### Status
- **Beta** (actively developed)
- Requires **C# support** (.NET version of Godot)
- GDScript support coming soon

### Components
| Component            | Description                                 |
|----------------------|---------------------------------------------|
| Dialogue Runner      | Main dialogue controller                    |
| Line Presenter       | Displays dialogue lines                     |
| Options Presenter    | Displays player choices                     |
| Variable Storage     | Variable persistence                        |
| Line Provider        | Localized content fetching                  |
| Markup Palette       | Visual markup handling                      |

### Setup
- Create `.yarnproject` via **Project > Tools > YarnSpinner > Create Yarn Project**
- Custom inspector similar to Unity version
- Works with both GDScript and C# via cross-language scripting

### Availability
- GitHub repository
- Planned for Godot Asset Library and Itch.io (with contributor revenue sharing)

---

## 22. Unreal Engine Integration

### Status
- **Alpha** (foundation built, full release planned 2026)
- Being built as **native integration** (not a Unity port)
- Respects Unreal's architecture and philosophy
- High community demand

### Features (Planned)
- Native Blueprint support
- C++ API
- Dialogue system components
- Variable storage integration
- Localization support

---

## 23. Paid Add-Ons

### Dialogue Wheel
- **Mass Effect-style** radial dialogue selector
- Two prefabs:
  - **Six-Segment Wheel** - fixed positions, light sci-fi appearance
  - **Automatic-Layout Wheel** - dynamic positioning
- Specify segment positions in Yarn scripts
- Supports up to 6 options
- Available on Itch.io and Unity Asset Store

### Speech Bubbles
- **Night in the Woods-style** speech bubbles
- Two prefabs:
  - **Casual Bubble** - informal style
  - **Formal Bubble** - structured style
- Customizable appearance
- Requires Unity 2022.3+
- Available on Itch.io and Unity Asset Store

### Text Animator Integration (Paid version only)
- Integration with Febucci's Text Animator 2 & 3
- Animated text effects within dialogue
- Unified markup system
- First paid/free divergence feature

---

## 24. 2026 Roadmap

| Feature                   | Status      | Description                                                                                 |
|---------------------------|-------------|---------------------------------------------------------------------------------------------|
| Visual Novel Kit          | Planned     | Pre-built VN presentation system                                                            |
| Rebuilt VS Code extension | Planned     | Rewritten extension with improved features                                                  |
| Native Unreal support     | In progress | Ground-up Unreal Engine integration                                                         |
| Godot development         | Ongoing     | GDScript support, stability improvements                                                    |
| Story Solver              | Planned     | Narrative debugging tool - visualize entire branching structure, test paths, find dead ends |
| "I Feel Fine" demo        | Planned     | Showcase game with full source and Yarn scripts                                             |
| Rewired integration       | Planned     | Input system integration                                                                    |
| i2Loc integration         | Planned     | Additional localization tool support                                                        |
| More add-ons              | Planned     | New dialogue presenters, UI components                                                      |
| Fab / Godot Asset Library | Planned     | Additional distribution platforms                                                           |
| Storefront                | Planned     | Browse add-ons and manage licenses                                                          |

---

## 25. Notable Games

Games built with Yarn Spinner demonstrate its production readiness:

| Game               | Developer             | Notes                          |
|--------------------|-----------------------|--------------------------------|
| Night in the Woods | Infinite Fall         | Cult classic indie             |
| A Short Hike       | adamgryu              | Award-winning exploration      |
| DREDGE             | Black Salt Games      | Fishing/horror, commercial hit |
| Lost in Random     | Zoink / EA            | AAA-published                  |
| Escape Academy     | Coin Crew Games       | Puzzle/escape room             |
| Baladins           | Seed by Seed          | Co-op narrative adventure      |
| Frog Detective 2&3 | worm club             | Comedy adventure               |
| Button City        | Subliminal Gaming     | Cozy adventure                 |
| Unbeatable         | D-Cell Games          | Rhythm/narrative               |

---

## Sources

- [Yarn Spinner Official Website](https://yarnspinner.dev/)
- [Yarn Spinner Features](https://yarnspinner.dev/features/)
- [Yarn Spinner Documentation](https://docs.yarnspinner.dev/)
- [Yarn Spinner in 2026 (Blog)](https://yarnspinner.dev/blog/yarn-spinner-in-2026/)
- [Yarn Spinner 3.1 Release](https://yarnspinner.dev/blog/yarn-spinner-3-1-release/)
- [Yarn Spinner 3.1 (Paris Buttfield-Addison)](https://hey.paris/posts/yarnspinner31/)
- [Yarn Spinner 3.0: What To Expect](https://www.yarnspinner.dev/blog/yarn-spinner-30-what-to-expect/)
- [Yarn Spinner on GitHub](https://github.com/YarnSpinnerTool/YarnSpinner)
- [Yarn Spinner VS Code Extension](https://marketplace.visualstudio.com/items?itemName=SecretLab.yarn-spinner)
- [Yarn Spinner for Godot (GitHub)](https://github.com/YarnSpinnerTool/YarnSpinner-Godot)
- [Get Yarn Spinner](https://yarnspinner.dev/install/)
- [Yarn Spinner on Unity Asset Store](https://assetstore.unity.com/packages/tools/behavior-ai/yarn-spinner-for-unity-the-friendly-dialogue-and-narrative-tool-267061)
- [Yarn Spinner on Itch.io](https://yarnspinner.itch.io/yarn-spinner)
- [Deep Dive: Developing Yarn Spinner (Gamedeveloper.com)](https://www.gamedeveloper.com/programming/deep-dive-yarn-spinner)
- [Docs: Variables](https://docs.yarnspinner.dev/write-yarn-scripts/scripting-fundamentals/logic-and-variables)
- [Docs: Smart Variables](https://docs.yarnspinner.dev/write-yarn-scripts/scripting-fundamentals/smart-variables)
- [Docs: Flow Control](https://docs.yarnspinner.dev/write-yarn-scripts/scripting-fundamentals/flow-control)
- [Docs: Functions](https://docs.yarnspinner.dev/3.0/write-yarn-scripts/scripting-fundamentals/functions)
- [Docs: Commands](https://docs.yarnspinner.dev/write-yarn-scripts/scripting-fundamentals/commands)
- [Docs: Detour](https://docs.yarnspinner.dev/write-yarn-scripts/scripting-fundamentals/detour)
- [Docs: Node Groups](https://docs.yarnspinner.dev/write-yarn-scripts/advanced-scripting/node-groups)
- [Docs: Tags and Metadata](https://docs.yarnspinner.dev/write-yarn-scripts/advanced-scripting/tags-metadata)
- [Docs: Markup](https://docs.yarnspinner.dev/getting-started/writing-in-yarn/markup)
- [Docs: Localization & Assets](https://docs.yarnspinner.dev/yarn-spinner-for-unity/assets-and-localization)
- [Docs: In-built Localisation](https://docs.yarnspinner.dev/yarn-spinner-for-unity/assets-and-localization/inbuilt-localisation)
- [Docs: Unity Localisation](https://docs.yarnspinner.dev/yarn-spinner-for-unity/assets-and-localization/unity-localization)
- [Docs: Voice Over Sample](https://docs.yarnspinner.dev/yarn-spinner-for-unity/samples/sample-guide-voice-over-and-localisation)
- [Docs: Dialogue Runner](https://docs.yarnspinner.dev/components/dialogue-runner)
- [Docs: Writing Yarn in VS Code](https://docs.yarnspinner.dev/write-yarn-scripts/yarn-spinner-editor/writing-yarn-in-vs-code)
- [Docs: Previewing Dialogue](https://docs.yarnspinner.dev/write-yarn-scripts/yarn-spinner-editor/previewing-your-dialogue)
- [Docs: VS Code Editor](https://docs.yarnspinner.dev/write-yarn-scripts/yarn-spinner-editor)
- [Docs: Unity Add-Ons](https://docs.yarnspinner.dev/yarn-spinner-for-unity/unity-add-ons)
- [Docs: Dialogue Wheel](https://docs.yarnspinner.dev/add-ons/dialogue-wheel)
- [Docs: Speech Bubbles](https://docs.yarnspinner.dev/yarn-spinner-for-unity/unity-add-ons/speech-bubbles)
- [Docs: Godot Installation](https://docs.yarnspinner.dev/using-yarnspinner-with-godot/installation-and-setup)
- [Docs: FAQ](https://docs.yarnspinner.dev/3.1/faq)
- [v3 Overview](https://docs.yarnspinner.dev/next/3-new-in-v3/overview)
- [Yarn Spinner v1 Syntax Reference](https://v1.yarnspinner.dev/docs/syntax/)
