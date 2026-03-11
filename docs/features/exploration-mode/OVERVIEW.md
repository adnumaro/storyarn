# Exploration Mode — Epic Overview

## Vision

Transform the Scene Exploration Mode from a simple interactive viewer into a **playable prototype engine** for CRPGs, Point & Click adventures, and narrative-driven games — without writing a single line of code.

**Core insight:** Storyarn doesn't compete with Unity/Godot. It competes with static design documents, PowerPoint decks, and 50-page GDDs that nobody reads. The Exploration Mode turns narrative design into a **playable experience** that designers, stakeholders, and playtesters can interact with immediately.

## Target Users

| User                               | Value                                                                                                         |
|------------------------------------|---------------------------------------------------------------------------------------------------------------|
| **Narrative designers in studios** | Prototype the full exploration experience BEFORE programming starts. "This is how exploring this area feels." |
| **Indie/solo developers**          | Build a complete narrative game (Point & Click, visual novel + exploration) without a game engine             |
| **TTRPG game masters**             | Prepare explorable scenes for their groups — players explore the map, collect items, talk to NPCs             |
| **Pitch/demo teams**               | Present game concepts to publishers with an interactive demo, not a PDF                                       |

## Design Philosophy

**Progressive complexity, immediate value.**

A designer should be able to:
1. Upload an image, place 2-3 pins, and hit "Explore" in **5 minutes** — and already feel value
2. Add layers of depth (walkable areas, items, patrols, audio) incrementally, **only when they want to**
3. Never feel overwhelmed — the Layer system keeps complexity organized and opt-in

Like Photoshop: a beginner uses 3 tools and is productive. A professional uses 30. Same program.

## Epics

Each epic is self-contained and delivers standalone value. Within each epic, every feature is an independent unit with its own implementation plan — they are NOT meant to be executed all at once.

### [Epic 1 — Playable Exploration](./EPIC_1_PLAYABLE_EXPLORATION.md)
> Foundation: make the scene feel like a game you can play

| # | Feature                                  | Standalone Value                                                                            |
|---|------------------------------------------|---------------------------------------------------------------------------------------------|
| 1 | Display modes (scaled/fit) + CRPG camera | Scene fills the screen like a real game map, camera pans with mouse at edges                |
| 2 | Walkable zones + character movement      | Player clicks on walkable area, character moves there — core CRPG/P&C interaction           |
| 3 | Collection zones                         | Clickable zones that open an item modal — loot chests, search bookshelves, pick up objects  |
| 4 | Exploration session persistence          | Save/load exploration state — variables, position, collected items survive between sessions |

### [Epic 2 — Living World](./EPIC_2_LIVING_WORLD.md)
> Make the scene feel alive with autonomous behaviors and atmosphere

| # | Feature                               | Standalone Value                                                                       |
|---|---------------------------------------|----------------------------------------------------------------------------------------|
| 1 | NPC patrol routes                     | NPCs move along defined paths automatically — guards patrol, merchants wander          |
| 2 | Ambient flows (Morte-style)           | Flows that execute without blocking interaction — companion commentary, narrator voice |
| 3 | Audio zones with distance attenuation | Spatial audio: tavern noise fades as you walk away, forest sounds blend with river     |
| 4 | Fog of war / discovery zones          | Areas hidden until the player enters them — progressive map revelation                 |
| 5 | Visual interaction indicators         | Cursor/icon changes on hoverable elements — hand for items, speech bubble for NPCs     |

### [Epic 3 — Advanced Mechanics](./EPIC_3_ADVANCED_MECHANICS.md)
> Deep game mechanics for complex prototypes

| # | Feature                                 | Standalone Value                                                  |
|---|-----------------------------------------|-------------------------------------------------------------------|
| 1 | Zone interaction chains (unlock/attack) | Multi-step interactions: locked chest → pick lock → open → loot   |
| 2 | Zone templates (shop, chest, NPC)       | Pre-configured interaction patterns — create a shop in one click  |
| 3 | Minimap                                 | Navigation aid for large scaled scenes                            |
| 4 | Scene transitions with animations       | Smooth fade/slide between connected scenes                        |
| 5 | Quick preview from editor               | Test exploration without leaving the editor — fast iteration loop |

## Execution Strategy

1. **Plan per feature, not per epic.** Each numbered feature gets its own implementation plan when it's time to build it.
2. **Ship incrementally.** Each feature adds value on its own — no need to complete an entire epic before it's useful.
3. **Validate early.** After Epic 1.1 (display modes + camera), the exploration mode already feels dramatically different. Test with users before going deeper.
4. **Leverage existing systems.** Variables, conditions, instructions, sheets, flows, layers — almost everything is already built. The new features are primarily new **behaviors** on top of existing data.

## Technical Foundation (existing)

| System                        | How it supports exploration                                                |
|-------------------------------|----------------------------------------------------------------------------|
| **Variables** (sheets/blocks) | Game state: health, inventory, flags, quest progress                       |
| **Conditions**                | Visibility, access control, branching — already on zones, pins, flow nodes |
| **Instructions**              | State mutations — collect item, take damage, set flag                      |
| **Flows**                     | Dialogue, combat encounters, puzzles — launched from zones/pins            |
| **Layers**                    | Organization — walkable areas, audio zones, triggers on separate layers    |
| **Connections/paths**         | NPC patrol routes, visual paths between locations                          |
| **Scene hierarchy**           | Parent/child scenes for world → region → location navigation               |
