# Storyarn — Competitive Analysis

> **Last updated:** 2026-02-16
> **Competitors analyzed:** articy:draft X, Arcweave, Yarn Spinner, World Anvil

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Competitor Positioning](#2-competitor-positioning)
3. [Feature Comparison Matrix](#3-feature-comparison-matrix)
4. [Detailed Comparison by Area](#4-detailed-comparison-by-area)
5. [Storyarn Competitive Advantages](#5-storyarn-competitive-advantages)
6. [Feature Gaps vs Competitors](#6-feature-gaps-vs-competitors)
7. [Competitor-Specific Breakdown](#7-competitor-specific-breakdown)

---

## 1. Executive Summary

Storyarn is a **web-based, real-time collaborative narrative design platform** built on Elixir/Phoenix LiveView. It targets narrative designers, game writers, and interactive storytelling teams who need a modern, cloud-native alternative to desktop tools like articy:draft.

### Market Position

Storyarn occupies a unique niche: it combines the **professional depth of articy:draft** (visual flow editor, entity database, screenplay, variables, debug engine) with the **cloud-native accessibility of Arcweave** (real-time collaboration, browser-based, no install), while adding a **full industry-standard screenplay editor** that no competitor matches.

| Dimension        | Storyarn                   | articy:draft X                    | Arcweave            | Yarn Spinner          | World Anvil        |
|------------------|----------------------------|-----------------------------------|---------------------|-----------------------|--------------------|
| Platform         | Web (LiveView)             | Desktop (Win/Mac)                 | Web (browser)       | VS Code + Engine      | Web (browser)      |
| Primary strength | Flow + Screenplay + Sheets | Depth + Templates + Engine export | Simplicity + AI     | Engine integration    | Worldbuilding wiki |
| Collaboration    | Real-time (cursors, locks) | Partition-based (SVN)             | Real-time (cursors) | VS Code Live Share    | Async only         |
| Target           | Pro narrative teams        | AAA/indie studios                 | Indie/game jams     | Programmers + writers | TTRPG/authors      |
| Pricing model    | TBD                        | $100-250+/seat                    | Free-$19/mo         | Open source + add-ons | Free-$50/mo        |

---

## 2. Competitor Positioning

### articy:draft X — The Industry Standard
Desktop-native narrative design tool used by AAA studios. Deepest feature set but requires installation, per-seat licensing, and SVN for collaboration. The benchmark against which all narrative tools are measured.

### Arcweave — The Accessible Challenger
Browser-based visual narrative tool focused on simplicity and speed. Strong AI integration and collaboration, but shallower data modeling. Popular for game jams and indie teams.

### Yarn Spinner — The Developer Tool
Open-source text-based dialogue scripting language with engine plugins. Extremely writer-friendly syntax but no visual authoring beyond a basic graph view. Requires a game engine to test fully.

### World Anvil — The Worldbuilding Wiki
Massive worldbuilding platform for TTRPG and fiction writers. 28 article templates, interactive maps, timelines, campaign management. No flow-based narrative editing or game engine integration.

---

## 3. Feature Comparison Matrix

### Legend
- **Y** = Fully implemented
- **P** = Partially implemented or basic version
- **N** = Not available
- **—** = Not applicable to this tool's paradigm

### 3.1 Platform & Infrastructure

| Feature                 | Storyarn       | articy:draft X   | Arcweave       | Yarn Spinner           | World Anvil    |
|-------------------------|----------------|------------------|----------------|------------------------|----------------|
| Web-based (no install)  | Y              | N                | Y              | P (web playground)     | Y              |
| Desktop app             | N              | Y                | N              | N (VS Code ext)        | N              |
| Offline support         | N              | Y                | N              | Y                      | N              |
| Self-hostable           | Y (Elixir)     | N                | N              | —                      | N              |
| Open source             | N              | N                | N              | Y (MIT core)           | N              |
| Real-time collaboration | Y              | N (partition)    | Y              | P (VS Code Live Share) | N              |
| Dark mode               | Y              | Y                | P              | Y (VS Code)            | P (themes)     |
| Mobile support          | P (responsive) | N                | P (responsive) | N                      | P (responsive) |

### 3.2 Visual Flow Editor

| Feature               | Storyarn          | articy:draft X         | Arcweave        | Yarn Spinner     | World Anvil  |
|-----------------------|-------------------|------------------------|-----------------|------------------|--------------|
| Visual node canvas    | Y                 | Y                      | Y               | P (graph view)   | N            |
| Drag-and-drop nodes   | Y                 | Y                      | Y               | P (VS Code)      | N            |
| Zoom & pan            | Y                 | Y                      | Y               | Y                | —            |
| Minimap               | Y                 | Y                      | N (planned)     | N                | —            |
| Level of Detail (LOD) | Y                 | N                      | N               | N                | —            |
| Grid background       | Y                 | Y                      | N               | N                | —            |
| Node color coding     | Y                 | Y                      | Y               | P (node headers) | —            |
| Nested flows (depth)  | N                 | Y (infinite)           | N (flat boards) | N                | —            |
| Cross-flow navigation | Y (subflow, exit) | Y (jump, double-click) | Y (jumpers)     | Y (jump/detour)  | —            |
| Undo/redo             | Y                 | Y                      | Y               | Y (VS Code)      | N            |
| Copy/paste nodes      | P (duplicate)     | Y                      | Y               | —                | —            |
| Connection labels     | P (response text) | Y (on connections)     | Y               | —                | —            |
| Node locking (collab) | Y                 | Y (partition)          | N               | N                | —            |
| Cursor tracking       | Y                 | N                      | Y               | N                | —            |

### 3.3 Node Types

| Node Type             | Storyarn              | articy:draft X        | Arcweave             | Yarn Spinner        | World Anvil  |
|-----------------------|-----------------------|-----------------------|----------------------|---------------------|--------------|
| Entry/Start           | Y                     | Y (implicit)          | Y (starting element) | Y (node title)      | —            |
| Exit/End              | Y (3 modes)           | Y (implicit)          | N                    | Y (===)             | —            |
| Dialogue              | Y                     | Y (Dialogue Fragment) | Y (Element)          | Y (lines)           | —            |
| Condition/Branch      | Y (standard + switch) | Y                     | Y (Branch)           | Y (if/elseif/else)  | —            |
| Instruction           | Y                     | Y                     | P (inline Arcscript) | Y (set/commands)    | —            |
| Hub (merge point)     | Y                     | Y                     | N                    | N                   | —            |
| Jump (goto)           | Y                     | Y (any node globally) | Y (Jumper)           | Y (<<jump>>)        | —            |
| Scene heading         | Y                     | N                     | N                    | N                   | —            |
| Subflow (nested call) | Y                     | Y (nested flows)      | N                    | Y (<<detour>>)      | —            |
| Flow Fragment         | N                     | Y                     | N                    | N                   | —            |
| Generic container     | N                     | Y (Flow Fragment)     | Y (Element)          | N                   | —            |

### 3.4 Dialogue Features

| Feature                   | Storyarn         | articy:draft X      | Arcweave              | Yarn Spinner     | World Anvil  |
|---------------------------|------------------|---------------------|-----------------------|------------------|--------------|
| Speaker assignment        | Y (linked sheet) | Y (entity ref)      | P (@mention)          | Y (name prefix)  | —            |
| Speaker avatar on node    | Y                | Y (preview image)   | Y (cover image)       | N                | —            |
| Rich text                 | Y (TipTap HTML)  | Y                   | Y                     | P (markup tags)  | —            |
| Stage directions          | Y                | Y                   | N                     | N                | —            |
| Menu text                 | Y                | Y                   | N                     | N                | —            |
| Responses/choices         | Y (per-dialogue) | Y (pin connections) | Y (connection labels) | Y (-> options)   | —            |
| Per-response conditions   | Y                | Y (pin scripts)     | Y (branch)            | Y (<<if>> on ->) | —            |
| Per-response instructions | Y                | Y (pin scripts)     | P (inline code)       | Y (nested set)   | —            |
| Audio attachment          | Y (per dialogue) | Y (per dialogue)    | Y (per element)       | Y (via line ID)  | —            |
| @Mentions in text         | Y (sheets/flows) | N                   | Y (components)        | N                | —            |
| Word count                | Y                | P                   | N                     | N                | —            |
| Technical ID              | Y (auto-gen)     | Y (technical name)  | N                     | Y (line ID)      | —            |
| Localization ID           | Y (auto-gen)     | Y (built-in)        | P (per-language)      | Y (line tags)    | —            |

### 3.5 Entity/Character Database

| Feature                  | Storyarn                                                                             | articy:draft X                                            | Arcweave             | Yarn Spinner                   | World Anvil       |
|--------------------------|--------------------------------------------------------------------------------------|-----------------------------------------------------------|----------------------|--------------------------------|-------------------|
| Dedicated entity system  | Y (Sheets)                                                                           | Y (Entities)                                              | Y (Components)       | N                              | Y (Articles)      |
| Custom properties/fields | Y (9 block types)                                                                    | Y (template features)                                     | P (4 attr types)     | N                              | Y (28 templates)  |
| Property inheritance     | Y (parent→children)                                                                  | Y (templates)                                             | N                    | N                              | N                 |
| Hierarchical tree        | Y                                                                                    | Y (folders)                                               | Y (folders)          | N                              | Y (categories)    |
| Custom data types        | Y (text, number, select, multi_select, boolean, date, rich_text, divider, reference) | Y (int, bool, string, dropdown, script, strip, ref, slot) | P (limited types)    | Y (number, string, bool, enum) | Y (per template)  |
| Variable exposure        | Y (blocks as variables)                                                              | Y (global variables)                                      | Y (global variables) | Y (global variables)           | N                 |
| Entity avatar/image      | Y (avatar + banner)                                                                  | Y (preview image)                                         | Y (cover image)      | N                              | Y (cover image)   |
| Entity color             | Y                                                                                    | Y                                                         | Y                    | N                              | Y                 |
| Versioning/history       | Y (full snapshots)                                                                   | Y (SVN)                                                   | P (project history)  | N (git)                        | N                 |
| Soft delete/trash        | Y                                                                                    | N                                                         | N                    | N                              | N                 |
| Inline editing           | Y (contenteditable)                                                                  | Y                                                         | Y                    | —                              | Y                 |
| Reference blocks         | Y (sheet↔flow links)                                                                 | Y (strip/reference)                                       | Y (component refs)   | N                              | Y (article links) |

### 3.6 Variable System

| Feature                   | Storyarn                                                                           | articy:draft X               | Arcweave                     | Yarn Spinner                  | World Anvil   |
|---------------------------|------------------------------------------------------------------------------------|------------------------------|------------------------------|-------------------------------|---------------|
| Variable types            | number, text, rich_text, select, multi_select, boolean, date                       | integer, boolean, string     | numeric, string, boolean     | number, string, boolean, enum | —             |
| Variable scope            | Per-sheet (namespaced)                                                             | Global (variable sets)       | Global                       | Global                        | —             |
| Variable namespacing      | Y (sheet.variable)                                                                 | Y (Set.Variable)             | N                            | N                             | —             |
| Condition builder (GUI)   | Y (rule builder)                                                                   | N (code editor)              | N (code editor)              | N (text syntax)               | —             |
| Instruction builder (GUI) | Y (assignment builder)                                                             | N (code editor)              | N (code editor)              | N (text syntax)               | —             |
| Stale reference detection | Y                                                                                  | N                            | N                            | P (compile errors)            | —             |
| Variable repair tool      | Y                                                                                  | N                            | N                            | N                             | —             |
| Operators (conditions)    | Y (type-aware: equals, greater_than, contains, starts_with, is_true, is_nil, etc.) | Y (full expression language) | Y (full expression language) | Y (full expression language)  | —             |
| Operators (instructions)  | Y (set, add, subtract, toggle, clear)                                              | Y (=, +=, -=, *=, /=, %=)    | Y (=, +=, -=, *=, /=, %=)    | Y (=, +=, -=, *=, /=, %=)     | —             |
| Computed/smart variables  | N                                                                                  | N                            | N                            | Y                             | —             |
| Scripting language        | N (GUI-only)                                                                       | Y (articy:expresso)          | Y (Arcscript)                | Y (Yarn language)             | —             |
| Custom functions          | N                                                                                  | Y (getObj, getProp, etc.)    | Y (abs, roll, visits, etc.)  | Y (extensible from engine)    | —             |
| Seen/visit tracking       | N                                                                                  | Y (seen/unseen/seenCounter)  | Y (visits())                 | Y (visited/visited_count)     | —             |

### 3.7 Screenplay / Document Writing

| Feature                      | Storyarn                     | articy:draft X                      | Arcweave    | Yarn Spinner  | World Anvil  |
|------------------------------|------------------------------|-------------------------------------|-------------|---------------|--------------|
| Dedicated screenplay editor  | Y (full, TipTap)             | P (Document View)                   | N (planned) | N             | N            |
| Industry-standard formatting | Y (Courier Prime, US Letter) | P (basic screenplay)                | N           | N             | N            |
| Element types                | 18                           | ~4 (chapter, line, stage dir, menu) | —           | —             | —            |
| Scene heading auto-detect    | Y                            | N                                   | N           | N             | —            |
| Transition auto-detect       | Y                            | N                                   | N           | N             | —            |
| Character CONT'D             | Y                            | N                                   | N           | N             | —            |
| Slash command palette        | Y                            | N                                   | N           | N             | —            |
| Smart type progression       | Y (Enter cycles types)       | P (Ctrl+Enter)                      | N           | N             | —            |
| Tab cycling block types      | Y                            | P (Tab fields)                      | N           | N             | —            |
| Inline condition builder     | Y (atom blocks)              | N                                   | N           | N             | —            |
| Inline instruction builder   | Y (atom blocks)              | N                                   | N           | N             | —            |
| Inline response builder      | Y (atom blocks)              | N                                   | N           | N             | —            |
| Bidirectional flow sync      | Y (to/from flow)             | N (one-way drag)                    | N           | N             | —            |
| Fountain import              | Y                            | N (Final Draft .fdx)                | N           | N             | —            |
| Fountain export              | Y                            | N (Word export)                     | N           | N             | —            |
| Read mode                    | Y                            | N                                   | N           | N             | —            |
| Character sheet linking      | Y (auto-creates sheets)      | Y (entity reference)                | N           | N             | —            |
| Page tree (branching)        | Y                            | N                                   | N           | N             | —            |
| Dual dialogue                | Y                            | N                                   | N           | N             | —            |
| Title page                   | Y                            | N                                   | N           | N             | —            |

### 3.8 Debug / Simulation / Testing

| Feature                      | Storyarn                   | articy:draft X             | Arcweave              | Yarn Spinner        | World Anvil   |
|------------------------------|----------------------------|----------------------------|-----------------------|---------------------|---------------|
| Built-in debug/test mode     | Y                          | Y                          | Y (Play Mode)         | P (VS Code preview) | N             |
| Step forward/back            | Y                          | Y                          | N                     | N                   | N             |
| Variable inspector           | Y (filterable table)       | Y (variable state tab)     | Y (debugger panel)    | N                   | —             |
| Variable inline editing      | Y (during debug)           | Y (initial value override) | N                     | N                   | —             |
| Breakpoints                  | Y (per node)               | N                          | N                     | N                   | —             |
| Auto-play with speed control | Y (200ms-3s)               | N                          | N                     | N                   | —             |
| Execution path/history       | Y (Path tab)               | Y (journey)                | N                     | N                   | —             |
| Variable change history      | Y (History tab)            | P (highlighted changes)    | P (before/after)      | N                   | —             |
| Console/log                  | Y                          | N                          | N                     | N                   | —             |
| Cross-flow debugging         | Y (subflow enter/return)   | Y (nested flows)           | N                     | N                   | —             |
| Canvas visual feedback       | Y (pulse, visited, active) | P (breadcrumb)             | N                     | N                   | —             |
| Save/load debug session      | P (ETS-persisted)          | Y (save journeys)          | N                     | N                   | —             |
| Condition analysis           | N                          | Y (red highlight on false) | N                     | N                   | —             |
| Shareable test link          | N                          | N                          | Y (public/embed link) | Y (HTML export)     | —             |
| All-branches view            | N                          | Y (Analysis Mode)          | N                     | N                   | —             |

### 3.9 Assets & Media

| Featurec              | Storyarn                           | articy:draft X         | Arcweave            | Yarn Spinner   | World Anvil       |
|-----------------------|------------------------------------|------------------------|---------------------|----------------|-------------------|
| Image upload          | Y                                  | Y (attachments)        | Y                   | —              | Y                 |
| Audio upload          | Y                                  | Y (VO files)           | Y                   | —              | P (embed)         |
| Video upload          | N                                  | N                      | Y                   | —              | N                 |
| Asset library/browser | Y (grid + search)                  | Y (navigator)          | Y (sidebar)         | —              | Y (image manager) |
| Asset detail panel    | Y (preview + usage)                | Y (property inspector) | P                   | —              | P                 |
| Storage backend       | R2/S3 + local                      | Local filesystem       | Cloud               | —              | Cloud             |
| Image processing      | P (thumbnails, resize — not wired) | N                      | N                   | —              | N                 |
| Usage tracking        | Y (flows, sheets)                  | P (object references)  | P (attachment refs) | —              | P (article refs)  |
| Filter by type        | Y (All/Images/Audio)               | Y                      | P                   | —              | P                 |
| Per-project isolation | Y                                  | Y (per project)        | Y (per project)     | —              | Y (per world)     |
| Built-in icon library | N                                  | N                      | Y (4,000+)          | N              | N                 |
| AI image generation   | N                                  | Y (preview images)     | Y (DALL-E/etc.)     | N              | N                 |

### 3.10 Localization

| Feature                    | Storyarn                       | articy:draft X                 | Arcweave          | Yarn Spinner      | World Anvil  |
|----------------------------|--------------------------------|--------------------------------|-------------------|-------------------|--------------|
| Multi-language support     | P (UI only: en/es via Gettext) | Y (unlimited languages)        | Y (Team plan)     | Y (built-in)      | N            |
| Content localization       | N                              | Y (per-property)               | Y                 | Y (strings files) | N            |
| Localization view          | N                              | Y (dedicated view)             | P (side-by-side)  | N                 | —            |
| Translation state tracking | N                              | Y (final/in-progress/outdated) | N                 | P (NEEDS UPDATE)  | —            |
| Machine translation        | N                              | Y (DeepL)                      | N                 | N                 | —            |
| Export for translators     | N                              | Y (Excel)                      | Y (JSON per lang) | Y (CSV)           | —            |
| Import translations        | N                              | Y (Excel)                      | N                 | Y (CSV)           | —            |
| VO per language            | N                              | Y                              | N                 | Y                 | —            |
| Spellchecker               | N                              | Y (per language)               | N                 | N                 | —            |

### 3.11 Collaboration

| Feature                     | Storyarn                      | articy:draft X           | Arcweave                          | Yarn Spinner   | World Anvil         |
|-----------------------------|-------------------------------|--------------------------|-----------------------------------|----------------|---------------------|
| Real-time presence          | Y (Phoenix Presence)          | N                        | Y                                 | P (Live Share) | N                   |
| Live cursor tracking        | Y (colored, labeled)          | N                        | Y                                 | P (Live Share) | N                   |
| Node/object locking         | Y (ETS, 30s expiry)           | Y (partition-based)      | N                                 | N              | N                   |
| Conflict prevention         | Y (lock-based)                | Y (exclusive partition)  | N (last write wins)               | N              | N                   |
| Remote change notifications | Y (toast)                     | Y (publish/pull)         | Y (instant)                       | N              | N                   |
| User color assignment       | Y (12-color palette)          | N                        | Y                                 | N              | N                   |
| Workspace roles             | Y (owner/admin/member/viewer) | Y (admin/regular/viewer) | Y (owner/editor/commenter/viewer) | N              | Y (4 author tiers)  |
| Project roles               | Y (owner/editor/viewer)       | N (workspace-level)      | P (per-project guest)             | N              | N                   |
| Invitation system           | Y (email, 7-day, hashed)      | N (admin assigns)        | Y                                 | N              | P (co-author slots) |
| Comments on content         | N                             | N                        | Y                                 | N              | N                   |
| In-app chat                 | N                             | N                        | Y                                 | N              | N                   |

### 3.12 Engine Integration & Export

| Feature                 | Storyarn   | articy:draft X   | Arcweave       | Yarn Spinner     | World Anvil   |
|-------------------------|------------|------------------|----------------|------------------|---------------|
| Unity plugin            | N          | Y (Asset Store)  | Y (free)       | Y (core feature) | N             |
| Unreal plugin           | N          | Y (open source)  | Y (free)       | P (alpha)        | N             |
| Godot plugin            | N          | Y (generic JSON) | Y (free)       | Y (.NET)         | N             |
| JSON export             | N          | Y                | Y              | N (compiled)     | P (API)       |
| Custom export           | N          | Y (MDK plugins)  | N              | Y (via code)     | P (API)       |
| API                     | N          | Y (.NET API)     | Y (REST, Team) | —                | Y (REST)      |
| Fountain export         | Y          | N                | N              | N                | N             |
| Excel/CSV export        | N          | Y                | Y              | Y (strings)      | Y             |
| Plugin/extension system | N          | Y (MDK)          | N              | Y (code-level)   | N             |

### 3.13 AI Features

| Feature                | Storyarn   | articy:draft X     | Arcweave          | Yarn Spinner  | World Anvil   |
|------------------------|------------|--------------------|-------------------|---------------|---------------|
| AI dialogue generation | N          | Y (plugin)         | Y                 | N             | N             |
| AI image generation    | N          | Y (preview images) | Y                 | N             | N             |
| AI content enhancement | N          | N                  | Y (enhancer)      | N             | N             |
| AI design assistant    | N          | N                  | Y (project-aware) | N             | N             |
| AI voice synthesis     | N          | Y (ElevenLabs)     | N                 | N             | N             |

### 3.14 Additional Features

| Feature                    | Storyarn                | articy:draft X                   | Arcweave               | Yarn Spinner       | World Anvil                      |
|----------------------------|-------------------------|----------------------------------|------------------------|--------------------|----------------------------------|
| Location/map editor        | N                       | Y (vector 2D)                    | N                      | N                  | Y (interactive maps)             |
| Timeline visualization     | N                       | N                                | N                      | N                  | Y (timelines + chronicles)       |
| Relationship visualization | N                       | N                                | N                      | N                  | Y (family trees, diplomacy webs) |
| Novel/manuscript writing   | N                       | N                                | N                      | N                  | Y                                |
| Whiteboard/mind map        | N                       | N                                | N                      | N                  | Y                                |
| Quality/checkup tools      | P (stale ref detection) | Y (conflict search, spell check) | N                      | P (compile errors) | N                                |
| Template/prototype sharing | N                       | N                                | Y (public link, embed) | Y (HTML export)    | Y (public worlds)                |
| Dice rolling               | N                       | N                                | Y (roll())             | Y (dice())         | Y                                |
| Visit/seen tracking        | N                       | Y (seen/unseen)                  | Y (visits())           | Y (visited())      | N                                |
| Custom CSS theming         | N                       | N                                | Y (Play Mode)          | N                  | Y (full CSS)                     |

---

## 4. Detailed Comparison by Area

### 4.1 Flow Editor

**Storyarn vs articy:draft X:** Both have professional-grade flow editors. articy's key advantage is **infinite nesting** (flows within flows) and a larger node type vocabulary (Flow Fragment as generic container). Storyarn counters with **real-time collaboration** (cursors, locking, remote changes), **LOD rendering** for large flows, and a **minimap**. articy requires SVN/Perforce for any multi-user work.

**Storyarn vs Arcweave:** Arcweave uses flat boards connected by jumpers rather than a true hierarchical flow system. Storyarn has significantly more node types (9 vs ~3 functional types), a properties panel with per-type configuration, and cross-flow navigation via subflows/exits. Both offer real-time collaboration, but Storyarn adds node locking for conflict prevention.

**Storyarn vs Yarn Spinner:** Yarn Spinner's graph view in VS Code is a visualization aid, not a primary authoring surface. Writers work in text. Storyarn's visual canvas is the primary interface, making it more accessible to non-programmers. However, Yarn Spinner's text approach allows version control with standard git and diff tooling.

### 4.2 Screenplay Editing

**Storyarn is unmatched** in this category. No competitor offers a comparable screenplay editor:

- **articy:draft** has a basic "Document View" with screenplay-like formatting, but it's a secondary feature with limited element types, no bidirectional flow sync, no Fountain format, and no industry-standard formatting conventions.
- **Arcweave** has "screenplay formatting" on their roadmap but hasn't shipped it yet.
- **Yarn Spinner** uses text-based scripting that resembles a screenplay but has no formatting, no standard element types, and no export to industry formats.
- **World Anvil** has Manuscripts for novel writing but no screenplay format.

Storyarn's 18 element types, bidirectional flow sync, Fountain import/export, auto-detection, smart typing, inline interactive atom blocks (condition/instruction/response builders), page tree for branching narratives, and character sheet auto-linking represent a unique and comprehensive offering.

### 4.3 Entity/Character Database

**Storyarn vs articy:draft X:** articy's template system is more flexible — templates can have reusable "features" (property groups) shared across templates. Storyarn's blocks are per-sheet, but **property inheritance** (scope: children cascading to descendants) is a strong differentiator that articy lacks in that exact form. articy uses template inheritance (all instances of a template share schema), while Storyarn uses tree-based inheritance (parent sheets push blocks to children). Both approaches are valid for different workflows.

**Storyarn vs Arcweave:** Storyarn's Sheets are significantly deeper than Arcweave's Components. Storyarn has 9 block types (vs ~4 attribute types), inheritance, versioning with full snapshots, avatar/banner assets, variable exposure, and a references/backlinks system.

**Storyarn vs World Anvil:** World Anvil has 28 specialized article templates with curated prompts, which is broader in scope but less structured for game variables. Storyarn's Sheets are designed specifically as variable containers for interactive narratives, while World Anvil's articles are wiki pages for worldbuilding lore.

### 4.4 Variable System & Scripting

**Storyarn vs articy:draft X / Arcweave / Yarn Spinner:** Storyarn takes a fundamentally different approach. Where competitors use **scripting languages** (articy:expresso, Arcscript, Yarn), Storyarn uses **GUI builders** — a visual condition builder (rule rows with dropdowns) and an instruction builder (assignment rows). This makes Storyarn more accessible to non-programmers but less powerful for complex logic.

Key trade-offs:
- **Storyarn strengths:** No syntax to learn, type-aware operators, stale reference detection with repair tool, variables namespaced per-sheet
- **Competitor strengths:** Full expression evaluation, compound conditions (&&, ||), custom functions, mathematical operations, string manipulation, visit tracking, dice rolling

### 4.5 Debug Engine

Storyarn's debug engine is **more capable than Arcweave's Play Mode** and **comparable to articy's Simulation Mode** in several respects:

| Capability                    | Storyarn                         | articy:draft X     | Arcweave         |
|-------------------------------|----------------------------------|--------------------|------------------|
| Step-by-step execution        | Y (forward + back)               | Y (forward)        | N                |
| Variable editing during debug | Y                                | Y (initial values) | N                |
| Breakpoints                   | Y                                | N                  | N                |
| Auto-play with speed control  | Y                                | N                  | N                |
| Execution path visualization  | Y                                | Y (journey)        | N                |
| Variable change history       | Y (timeline)                     | P (highlighted)    | P (before/after) |
| Cross-flow support            | Y (subflow enter/return)         | Y (nested)         | N                |
| Canvas visual feedback        | Y (pulse, visited, active edges) | P                  | N                |
| Save/replay                   | P (ETS session)                  | Y (saved journeys) | N                |
| Shareable test                | N                                | N                  | Y (public link)  |
| Analysis mode (all branches)  | N                                | Y                  | N                |

Storyarn's breakpoints, auto-play with speed control, step-back capability, and console are features articy lacks. However, articy's Analysis Mode (showing all branches including failed conditions) and saved/shared journeys are capabilities Storyarn doesn't have.

### 4.6 Collaboration

Storyarn and Arcweave are the only tools with **true real-time collaboration** (live cursors, instant syncing). Storyarn goes further with **node locking** to prevent concurrent edits on the same content, while Arcweave uses a last-write-wins model.

articy:draft uses a partition/claiming system with SVN, which prevents conflicts but creates workflow friction (claim → edit → publish → release). It's designed for large teams working on separate project areas simultaneously.

### 4.7 Engine Integration (Major Gap)

This is Storyarn's **most significant competitive gap**. All three game-oriented competitors offer engine integration:

- **articy:draft:** Unity + Unreal + generic JSON (Godot); .NET API; MDK plugins
- **Arcweave:** Unity + Unreal + Godot + Defold; REST API
- **Yarn Spinner:** Unity (deep) + Godot + Unreal (alpha); runtime dialogue system

Storyarn currently has **no engine integration**, no JSON/XML export for game consumption, and no API. The Fountain export serves screenplay workflows but not game engine pipelines.

### 4.8 Localization (Major Gap)

Content localization is critical for game narrative tools. All three game-oriented competitors support it:

- **articy:draft:** Best-in-class (unlimited languages, DeepL, state tracking, Excel workflow, VO per language, spellcheck, dedicated view)
- **Yarn Spinner:** Deeply built-in (line IDs, CSV strings files, asset tables per language, runtime switching)
- **Arcweave:** Recently launched (multi-language, per-language export)

Storyarn has **UI localization** (en/es via Gettext) but no content localization for user-authored narratives.

---

## 5. Storyarn Competitive Advantages

### 5.1 Unique Differentiators (Features No Competitor Has)

1. **Full Industry-Standard Screenplay Editor with Bidirectional Flow Sync**
   - 18 element types (vs articy's ~4, others 0)
   - Bidirectional sync between screenplay and flow (articy is one-way drag-and-drop with separate copies)
   - Interactive atom blocks (condition/instruction/response builders inline in screenplay)
   - Fountain import with auto-character-sheet creation
   - Page tree for branching screenplay narratives
   - Smart typing, auto-detection, CONT'D, dual dialogue, slash commands

2. **GUI-Based Variable System with Per-Entity Namespacing**
   - Variables are sheet blocks, not global declarations — `mc.jaime.health` vs `GameState.playerLevel`
   - Visual condition and instruction builders with type-aware operators
   - Stale reference detection and bulk repair tool
   - No scripting language to learn

3. **Property Inheritance with Scope Control**
   - Parent sheets cascade properties to children with `scope: children`
   - Propagation modal for selective inheritance
   - Detach/reattach for overriding inherited values
   - Config sync across all instances

4. **Advanced Debug Engine with Breakpoints and Step-Back**
   - Breakpoints per node (no competitor has this)
   - Step-back via full state snapshots (no competitor has this)
   - Auto-play with configurable speed (200ms-3s)
   - Console log, variable history timeline, execution path with depth indentation
   - Canvas visual feedback (pulsing active node, visited indicators, animated edges)

5. **Scene Node Type**
   - Dedicated screenplay scene heading node in the flow editor
   - INT/EXT, sub-location, time of day — no other flow tool has this

### 5.2 Competitive Strengths (Better Than Most/All Competitors)

1. **Real-Time Collaboration with Conflict Prevention**
   - Live cursors + node locking + remote change notifications
   - Only platform combining real-time collaboration with locking (Arcweave has cursors but no locking; articy has locking but no real-time)

2. **Sheet Versioning with Full Snapshots**
   - Manual + rate-limited auto-versioning
   - Full snapshot restore (blocks, metadata, layout)
   - More granular than articy's SVN-based versioning

3. **Node Type Richness**
   - 9 node types (entry, exit, dialogue, condition, instruction, hub, jump, scene, subflow)
   - More than Arcweave (element, branch, jumper) and comparable to articy (7 core types)
   - Scene and subflow nodes are unique to Storyarn

4. **Modern Web Architecture**
   - No installation, works anywhere with a browser
   - LiveView provides near-desktop reactivity
   - Self-hostable (Elixir/Phoenix)

5. **Sheet Audio Tab**
   - Centralized voice line management per character
   - Shows all dialogue nodes where a character speaks across all flows
   - Upload/select/remove audio directly from the character sheet

---

## 6. Feature Gaps vs Competitors

### 6.1 Critical Gaps (High Impact on Competitiveness)

| Gap                                                  | Who Has It                                            | Impact                                                               |
|------------------------------------------------------|-------------------------------------------------------|----------------------------------------------------------------------|
| **Game engine integration** (Unity, Unreal, Godot)   | articy, Arcweave, Yarn Spinner                        | Cannot be used in a real game production pipeline without this       |
| **JSON/data export** for engine consumption          | articy, Arcweave, Yarn Spinner                        | Even without plugins, a structured export enables custom integration |
| **Content localization** (multi-language narratives) | articy, Arcweave, Yarn Spinner                        | Table-stakes for any commercial game targeting multiple markets      |
| **Scripting language** for complex expressions       | articy (expresso), Arcweave (Arcscript), Yarn Spinner | GUI builders can't express compound conditions, math, or string ops  |
| **API** (REST or similar)                            | articy (.NET), Arcweave (REST), World Anvil (REST)    | Required for CI/CD, custom tooling, runtime content delivery         |

### 6.2 Important Gaps (Would Strengthen Position)

| Gap                                                     | Who Has It                                   | Impact                                                   |
|---------------------------------------------------------|----------------------------------------------|----------------------------------------------------------|
| **Visit/seen tracking** (has player visited this node?) | articy, Arcweave, Yarn Spinner               | Common game mechanic for dynamic dialogue                |
| **Nested flows** (flows within flows)                   | articy (infinite depth)                      | Hierarchical story structure (acts → scenes → dialogues) |
| **AI features** (dialogue gen, image gen, assistant)    | articy (plugin), Arcweave (multiple)         | Growing expectation in creative tools                    |
| **Computed/smart variables**                            | Yarn Spinner                                 | Reduces duplication for derived state                    |
| **Custom functions** in expressions                     | articy, Arcweave, Yarn Spinner               | Extend variable system without code changes              |
| **Shareable play/test link**                            | Arcweave (public/embed), Yarn Spinner (HTML) | Share prototypes with stakeholders without access        |
| **Comments on content**                                 | Arcweave                                     | Collaboration workflow for feedback                      |
| **Copy/paste between flows**                            | articy                                       | Reuse flow structures across the project                 |

### 6.3 Nice-to-Have Gaps (Lower Priority)

| Gap                                 | Who Has It             | Impact                                                |
|-------------------------------------|------------------------|-------------------------------------------------------|
| Location/map editor                 | articy, World Anvil    | Visual world planning                                 |
| Dice rolling functions              | Arcweave, Yarn Spinner | Tabletop-style mechanics                              |
| CSS theming for play mode           | Arcweave, World Anvil  | Visual novel / prototype styling                      |
| Pin-level conditions/instructions   | articy                 | Conditions on input pins, instructions on output pins |
| Offline support                     | articy, Yarn Spinner   | Work without internet                                 |
| Analysis mode (all branches)        | articy                 | See every possible path including failed conditions   |
| Save/replay debug journeys          | articy                 | Reproducible testing, team sharing                    |
| In-app chat                         | Arcweave               | Team communication without switching tools            |
| Template import from other projects | articy                 | Reuse entity schemas across projects                  |

---

## 7. Competitor-Specific Breakdown

### 7.1 Storyarn vs articy:draft X

**Storyarn wins on:**
- Web-based, no install, works anywhere
- Real-time collaboration (cursors, locking, notifications vs SVN partitions)
- Screenplay editor (full industry-standard vs basic Document View)
- Bidirectional flow-screenplay sync (vs one-way copy)
- GUI variable builders (vs mandatory scripting)
- Debug breakpoints and step-back
- Auto-play with speed control
- Property inheritance with scope control
- Scene node type
- Modern, accessible UX
- Free from per-seat licensing

**articy:draft X wins on:**
- Infinite nested flows (hierarchical story structure)
- Full scripting language (articy:expresso)
- Template system with reusable features
- Localization (unlimited languages, DeepL, state tracking, VO)
- Engine integration (Unity, Unreal, Godot)
- Simulation modes (Analysis, Player, Record)
- Location editor (2D vector maps)
- Plugin system (MDK) with .NET API
- Export formats (JSON, XML, Excel, Word)
- Offline support
- Industry track record (AAA titles)
- Pin-level scripting (conditions on inputs, instructions on outputs)
- Seen/unseen visit tracking
- AI features (dialogue, barks, preview images, ElevenLabs VO)

**Verdict:** Storyarn is more accessible and collaborative; articy is deeper and more feature-complete. Storyarn's screenplay editor is a clear win, but articy's engine integration, localization, and scripting are must-have gaps to close.

---

### 7.2 Storyarn vs Arcweave

**Storyarn wins on:**
- Node type variety (9 vs 3)
- Properties panel with per-type configuration
- Entity system depth (Sheets with 9 block types, inheritance, versioning vs Components with ~4 types)
- Variable namespacing (sheet.variable vs flat globals)
- Condition/instruction GUI builders
- Full screenplay editor (Arcweave has none)
- Debug engine (step, breakpoints, auto-play vs simple Play Mode debugger)
- Node locking for collaboration safety
- Stale reference detection and repair
- Sheet Audio Tab (centralized voice lines)
- Fountain import/export

**Arcweave wins on:**
- AI features (element generator, enhancer, image generator, design assistant)
- Shareable prototypes (public links, embeddable Play Mode)
- Engine integration (Unity, Unreal, Godot, Defold plugins)
- REST API (Team plan)
- Scripting language (Arcscript with full expressions)
- Video asset support
- In-app chat
- Comments on elements
- CSS-customizable Play Mode (visual novel mode)
- Built-in icon library (4,000+)
- Simpler learning curve
- Localization (multi-language, per-language export)
- Excel export
- Visit tracking (visits() function)

**Verdict:** Storyarn is significantly deeper as a narrative design tool (screenplay, debug, entities, variables). Arcweave is more accessible and has stronger sharing/prototyping and AI features. Storyarn's main gaps relative to Arcweave are engine integration, AI, and shareable test links.

---

### 7.3 Storyarn vs Yarn Spinner

**These tools serve different workflows.** Yarn Spinner is a code-first scripting language; Storyarn is a visual-first design tool.

**Storyarn wins on:**
- Visual flow editor (primary interface vs secondary visualization)
- Entity/character database (Sheets vs none)
- Screenplay editor (full vs none)
- Real-time collaboration (full vs VS Code Live Share)
- Asset management (library, upload, preview vs none)
- Debug engine (GUI with breakpoints, auto-play, console vs text preview)
- Accessibility for non-programmers

**Yarn Spinner wins on:**
- Engine integration (Unity deep, Godot, Unreal alpha)
- Full scripting language with extensions
- Smart variables (computed read-only)
- Enums (type-safe constrained values)
- Node groups + saliency (multiple versions of same dialogue selected by conditions)
- Line groups (NPC barks with computer-selected content)
- Shadow lines (deduplicated localization)
- Detour (visit a node and return — cleaner than subflow for simple cases)
- Once blocks (run content only once)
- Localization (core design, line IDs, CSV workflow)
- Open source (MIT)
- Massive game portfolio (Night in the Woods, DREDGE, A Short Hike, etc.)
- Text-based = git-friendly (diffs, PRs, code review)
- Extensible from engine code (custom commands, functions)

**Verdict:** Complementary more than competitive. Storyarn targets visual designers and writing teams; Yarn Spinner targets programmer-writer pairs. However, if targeting the same user, Storyarn needs engine integration and export to be viable for Yarn Spinner's audience.

---

### 7.4 Storyarn vs World Anvil

**These tools serve different markets** with some overlap in character/entity management.

**Storyarn wins on:**
- Visual flow editor (World Anvil has none)
- Screenplay editor (World Anvil has none)
- Variables and game logic (World Anvil has none)
- Debug engine (World Anvil has none)
- Real-time collaboration (World Anvil is async only)
- Game-oriented entity system (blocks as variables)
- Modern UI/UX (World Anvil described as "dated" by reviewers)

**World Anvil wins on:**
- Worldbuilding breadth (28 article templates, maps, timelines, chronicles, family trees, diplomacy webs, whiteboards)
- Community (3M+ users, challenges, gamification)
- RPG campaign management (100+ systems, character sheets, DSTS)
- Novel writing (Manuscripts with chapters/scenes)
- CSS theming and customization
- Monetization tools (Patreon integration, custom domains)
- Secrets system (per-group visibility)
- Interactive maps with markers, layers, and linked articles

**Verdict:** Minimal direct competition. World Anvil is a worldbuilding wiki; Storyarn is a narrative design tool. However, World Anvil's character/entity management and its potential addition of interactive narrative features make it worth monitoring.
