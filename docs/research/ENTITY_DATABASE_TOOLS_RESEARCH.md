# Entity Database & Character Sheets Research

> **Date:** February 2024
> **Scope:** Analysis of how narrative design and worldbuilding tools handle entity databases (characters, items, locations, bestiary, etc.)

---

## Table of Contents

1. [Market Overview](#1-market-overview)
2. [Tool Analysis](#2-tool-analysis)
3. [Template & Schema Systems](#3-template--schema-systems)
4. [Data Relationships & References](#4-data-relationships--references)
5. [User Workflows & Pain Points](#5-user-workflows--pain-points)
6. [Wiki-Style Tools (Notion, Obsidian, World Anvil)](#6-wiki-style-tools)
7. [What Designers Need](#7-what-designers-need)
8. [Database Architecture Patterns](#8-database-architecture-patterns)
9. [References](#9-references)

---

## 1. Market Overview

### Tool Categories

| Category             | Tools                               | Primary Use Case                  |
|----------------------|-------------------------------------|-----------------------------------|
| **Narrative Design** | articy:draft, Arcweave              | Game dialogue + entity database   |
| **Worldbuilding**    | World Anvil, LegendKeeper, Campfire | Writers, DMs, world documentation |
| **General Wiki**     | Notion, Obsidian, Confluence        | Flexible, multi-purpose           |
| **TTRPG Specific**   | D&D Beyond, Roll20, Foundry VTT     | Character sheets, bestiaries      |

### Target Audiences

- **Game Writers/Narrative Designers**: Need integration between entities and dialogue flows
- **Worldbuilders/Authors**: Need extensive documentation, relationships, timelines
- **Game Masters/DMs**: Need quick reference, session management, player sharing
- **Indie Developers**: Need lightweight, affordable, exportable data

---

## 2. Tool Analysis

### 2.1 articy:draft X

**Entity System Overview:**
Entities represent game objects and can be used for all sorts of object types like characters, enemies, items, but also abstract things like weather or time. Entities are set up with templates making them extremely flexible.

**Template System:**
- Templates add custom properties to basic articy:draft objects
- Can create objects directly from templates or assign templates later
- Templates are type-locked (entity template can only be used on entities)
- Supported on: Flow elements, Entities, Locations, Assets, Documents

**Property Types:**
- Basic types: String, Number, Boolean
- Slots: Single object reference
- Strips: List of object references
- Calculated Strips: Dynamic queries for related objects
- Dropdown lists with predefined values
- Constraints: Min/max values, validation

**Reference System:**
- Reference strips on most object sheets
- Can hold assets and other entities
- Automatic reference tracking (where entity is used as speaker, in flows, etc.)
- Double-click to navigate to linked object

**Known Limitations:**
- Template is fixed to one type only
- Cannot use same template twice on one object
- Entities with custom color don't update when template color changes
- Cannot customize the References tab content
- Template editor locks other articy:draft sections while editing

**User Feedback (Steam):**
- Users request relationship linking between entities (Father-Son, etc.)
- Solution requires manual Strip/Slot configuration in templates
- Complex relationship networks are cumbersome to set up

### 2.2 Arcweave

**Components System:**
Components function as flexible containers for representing story objects. They store information about narrative elements such as characters, locations, items, weapons, spells, emotions, and statistics.

**Attribute Types:**
- String
- Rich text
- Component list (references to other components)
- Asset list

**Key Features:**
- Custom folder organization
- Drag-and-drop attachment to elements (dialogue nodes)
- Visual references in Play Mode
- @mentions to create internal links
- Cover images from assets or icon library
- References panel showing all usages

**Integration with Flow:**
- Components attach directly to elements
- Create visual references during plot points
- Attachments render in Play Mode
- Can be reordered within elements

**Limitations:**
- No inheritance between components
- No template system (each component is unique)
- Cannot define "component types" with shared schemas

### 2.3 World Anvil

**Overview:**
A worldbuilding toolset that helps create, organize and store world settings with wiki-like articles, interactive maps, historical timelines, and RPG Campaign Manager.

**Template System:**
- Over 25 worldbuilding templates
- Templates for: Characters, Locations, Items, Organizations, Species, Languages, Religions, Magic Systems, etc.
- Easy-to-use fields for tracking everything about a character

**Character Features:**
- Year of birth, relatives, alignment, hobbies
- Fields can interact with rest of the world
- Interactive character sheets for 100+ RPG systems
- Support for D&D, Pathfinder, Call of Cthulhu, etc.

**Worldbuilding Features:**
- Timelines with eras
- Family trees
- Diplomatic relationships
- Interactive maps with linked lore
- Secrets and spoiler markers

**User Feedback:**
- "Too complicated, dozens of features I didn't need"
- "Sharp learning curve"
- "Has a complicated UI"
- Some features require paid version (privacy, storage)
- Large userbase (750,000+ worldbuilders)

### 2.4 Campfire Writing

**Module System:**
17 separate modules that can be purchased individually:
- Characters, Manuscript, Locations, Maps, Research, Timeline
- Arcs, Relationships, Encyclopedia, Magic, Species
- Cultures, Items, Systems, Languages, Religions, Philosophies

**Character Features:**
- Essential info: name, age, personality traits
- Backstory, relationships, custom panels
- Character grouping by factions
- Arc tracking (emotional, physical, etc.)
- Visual relationship maps and family trees

**Key Differentiators:**
- Modules interconnect automatically
- Relationships and Arcs connect to Characters module
- Custom calendars with seasons, holidays, lunar patterns
- Publishing platform integration

**Pricing:**
- Each module: $12.50/month, $125/year, or $375/lifetime
- All modules can get expensive

### 2.5 LegendKeeper

**Philosophy:**
Focuses on streamlined, distraction-free writing with auto-linking wiki pages.

**Features:**
- Free-form whiteboards
- Real-time multiplayer
- Reusable templates
- Visual text editor with auto-interlinking
- Nested maps (continents → buildings)
- Images up to 10,000+ pixels, 100 MB

**User Feedback:**
- "Polished, shareable, intuitive"
- "Not made for mobile"
- "Currently in beta, may have bugs"
- No forced forms or rigid categories

### 2.6 Notion

**Approach:**
All-in-one productivity tool blending note-taking, project management, and database functionality.

**Game Design Usage:**
- Character profile databases
- Item/inventory tracking
- Location wikis
- Lore documentation
- Story arc timelines

**Strengths:**
- Full creative control
- Build system for specific needs
- Easy to learn
- Free version sufficient for most uses
- Templates marketplace

**Limitations:**
- No offline mode
- Enterprise-focused, getting clunky
- Can't integrate directly into code repositories
- Tables can't perform advanced calculations like Excel
- No native calendar function
- "Jack of all trades, master of none"
- "Limited in complex and custom note taking"

### 2.7 Obsidian

**Approach:**
Local app with interlinked notes, like building your own Wikipedia.

**Features:**
- Cross-linked notes (graph view)
- Plain text markdown files
- Extensive plugin system
- Local storage (owns your data)
- Free for personal use

**For Worldbuilding:**
- Not differentiated by default
- Requires plugins and customization
- Can be as simple or feature-heavy as wanted

**Limitations:**
- Learning curve
- Plugin functionality doesn't work with publishing
- Remote backup costs extra

---

## 3. Template & Schema Systems

### 3.1 articy:draft Approach (Type-Locked Templates)

```
Templates/
├── Entity Templates/
│   ├── Character
│   ├── Item
│   └── Enemy
├── Location Templates/
│   └── Interior
└── Flow Templates/
    └── Quest Dialogue
```

**Characteristics:**
- Templates are defined in a separate "Template Design" area
- Each template is locked to one object type
- Objects can be created from templates or assigned later
- Properties defined: name, icon, color, custom fields

**Property Features:**
- Slots: Reference single object
- Strips: Reference multiple objects
- Constraints: Validation rules (min/max, required)
- Calculated Strips: Dynamic queries

### 3.2 Arcweave Approach (Flat Components)

```
Components/
├── Characters/
│   ├── Hero
│   └── Villain
├── Items/
│   ├── Sword
│   └── Potion
└── Locations/
    └── Tavern
```

**Characteristics:**
- No formal template system
- Each component is unique
- Folder organization is manual
- Attributes defined per-component
- No inheritance or schema enforcement

### 3.3 World Anvil Approach (Preset Article Types)

```
Articles/
├── Characters (preset template)
├── Locations (preset template)
├── Items (preset template)
├── Organizations (preset template)
└── Custom Category (user-defined)
```

**Characteristics:**
- Many preset article types with built-in fields
- Custom categories possible
- Fields designed for worldbuilding (relatives, affiliations)
- RPG-specific integrations

### 3.4 Campfire Approach (Module-Based)

```
Modules/
├── Characters Module
│   ├── Character 1
│   └── Character 2
├── Items Module
├── Locations Module
└── Relationships Module (cross-links Characters)
```

**Characteristics:**
- Separate modules for different entity types
- Modules interconnect automatically
- Each module has predefined schema
- Purchase modules as needed

### 3.5 Notion Approach (User-Defined Databases)

```
Databases/
├── Characters (user-created, user schema)
├── Items (user-created, user schema)
└── Locations (user-created, user schema)
```

**Characteristics:**
- Complete flexibility
- User defines all schemas
- No guidance or presets
- Relations between databases
- Can get complex to manage

---

## 4. Data Relationships & References

### 4.1 articy:draft Relationships

**Problem Reported (Steam):**
> "How do I link entities in relationships? Char A and Char B are father-son. I can store this in a template field, but it only works with a single pair. For multiple relationships (A↔B Father-Son, A↔C Husband-Wife, B↔C Mother-Son), I need multiple sets."

**Solution:**
- Use Strip features in templates
- Create bi-directional references manually
- Calculated Strips for dynamic queries

**Automatic References:**
- References tab shows where entity is used
- Speakers in dialogues
- Location placements
- Flow references

### 4.2 Arcweave Relationships

- Component lists allow referencing other components
- @mentions create navigable links
- References panel shows all usages
- No formal relationship typing

### 4.3 World Anvil Relationships

- Family trees
- Diplomatic relationships between organizations
- Timeline connections
- Map-based location relationships
- Article cross-linking

### 4.4 Campfire Relationships

- Dedicated Relationships module
- Visual relationship maps
- Family trees
- Automatic connection to Characters module
- Arc tracking across characters

---

## 5. User Workflows & Pain Points

### 5.1 Common Frustrations

**Complexity & Learning Curve:**
- World Anvil: "Too complicated, dozens of features I didn't need"
- World Anvil: "Sharp learning curve could be a barrier"
- articy:draft: "Complex interface may overwhelm beginners"
- General: "Extensive functionalities may be overwhelming"

**Flexibility vs Structure:**
- Too rigid: Preset templates don't fit all use cases
- Too flexible: No guidance, users build everything from scratch
- Ideal: Guidance with customization options

**Relationship Management:**
- articy:draft: Complex to set up bi-directional relationships
- Most tools: Relationships are manual, not automatically bi-directional
- Users want: Easy character relationship mapping

**Data Portability:**
- World Anvil: Export features limited to paid tiers
- Notion: Can't integrate directly with game engines
- articy:draft: Proprietary format, complex export rules

**Offline Access:**
- Notion: No offline mode
- World Anvil: No offline mode
- Arcweave: Requires internet connection
- Users want: Local copies of their work

### 5.2 What Users Praise

**World Anvil:**
- Extensive templates for worldbuilding
- RPG system integration
- Large community

**Notion:**
- Flexibility
- Easy to learn basics
- Free tier generosity

**LegendKeeper:**
- Distraction-free writing
- Auto-linking
- Clean interface

**Obsidian:**
- Local files
- Plugin extensibility
- Free

**articy:draft:**
- Integration with game engines
- Professional-grade features
- Entity + Flow in one tool

---

## 6. Wiki-Style Tools

### 6.1 Why Designers Use Wiki Tools

Many game designers use Notion or wiki-like platforms because:

1. **Familiarity**: Wikipedia/wiki mental model is intuitive
2. **Flexibility**: No forced structure
3. **Linking**: Everything can connect to everything
4. **Organic Growth**: Start simple, add complexity as needed
5. **Collaboration**: Easy to share and edit together
6. **Cost**: Many have generous free tiers

### 6.2 Comparison: Wiki vs Game-Specific Tools

| Aspect             | Wiki Tools (Notion)   | Game Tools (articy:draft)  |
|--------------------|-----------------------|----------------------------|
| Learning curve     | Low                   | High                       |
| Structure          | User-defined          | Preset templates           |
| Game engine export | Manual                | Built-in                   |
| Flow integration   | None                  | Native                     |
| Price              | Free/Low              | Higher                     |
| Collaboration      | Easy                  | Complex                    |
| Offline            | Limited               | Yes (desktop)              |

### 6.3 Key Insight

> Users want **wiki simplicity** with **game tool integration**.

The ideal tool would:
- Feel like Notion (organic, flexible, low learning curve)
- Export like articy:draft (game engine ready)
- Connect to flows (entities as speakers, items in conditions)

---

## 7. What Designers Need

### 7.1 Character Sheets

Based on industry standards, character sheets typically include:

**Visual Elements:**
- Full-body, full-color image
- Additional poses/attitudes
- Expression sheet (3-6 emotions)
- Costume variations

**Written Information:**
- Name and aliases
- Brief personality description
- Backstory
- Relationships
- Motivations/Goals
- Voice/Speech patterns

**Technical Data (for games):**
- Stats/Attributes
- Abilities
- Inventory
- Faction/Affiliation
- AI behavior notes

### 7.2 Item Sheets

**Common Properties:**
- Name, Description
- Category/Type
- Rarity
- Value/Cost
- Weight
- Stats/Effects
- Visual (icon, 3D model reference)
- Lore/History
- Crafting recipe
- Where to find

### 7.3 Location Sheets

**Common Properties:**
- Name, Description
- Type (city, dungeon, building)
- Climate/Environment
- Population
- Notable NPCs
- Connected locations
- Map/Layout
- Lore/History
- Available quests
- Available items/shops

### 7.4 Bestiary Sheets

**Common Properties:**
- Name, Description
- Type/Category
- Stats (HP, Attack, Defense)
- Abilities/Attacks
- Weaknesses
- Loot drops
- Spawn locations
- AI behavior
- Lore
- Visual reference

### 7.5 Workflow Requirements

**Documentation Phase:**
- Easy entry of basic information
- Flexible fields (not all characters need all fields)
- Quick navigation between related entities
- Search and filter

**Design Phase:**
- Connect entities to flows
- Track where entities are used
- Version history
- Collaboration

**Production Phase:**
- Export to game engine
- Localization support
- Asset linking (images, audio)
- Technical IDs for code

---

## 8. Database Architecture Patterns

### 8.1 Entity-Component-System (ECS)

Game development has moved away from deep inheritance hierarchies toward composition:

> "ECS prioritizes composition over inheritance. Every entity is defined not by a type hierarchy, but by the components associated with it."

**Problem with Inheritance:**
- Monster → FlyingMonster → SpellFlyingMonster creates rigid hierarchies
- Adding new capability requires new class
- Diamond inheritance problems

**ECS Solution:**
- Entity = Collection of components
- FlyingMonster = Entity + Health + Damage + Flying
- SpellFlyingMonster = Entity + Health + Damage + Flying + Spellcasting
- Components are independent and reusable

### 8.2 Database Inheritance Strategies

**Table Per Hierarchy (TPH):**
- Single table with discriminator column
- All properties in one table, nulls for unused
- Simple queries, some wasted space

**Table Per Type (TPT):**
- Separate table for each entity type
- Foreign key to parent table
- Normalized, but requires joins

**Table Per Concrete Type (TPC):**
- Each concrete class has own table
- No base table
- Good for leaf-type queries

### 8.3 Implications for Storyarn

The research suggests:

1. **Avoid rigid type hierarchies** - Don't force "Character", "Item", "Location" as fixed types
2. **Support composition** - Let users add properties flexibly
3. **Enable inheritance when useful** - Parent pages can define schemas for children
4. **Keep it simple** - Don't over-engineer the data model

---

## 9. References

### Official Documentation

- [articy:draft X Entities](https://www.articy.com/en/adx_basics_entities/)
- [articy:draft Entity Templates](https://www.articy.com/help/adx/Entities_Templates.html)
- [articy:draft Templates Overview](https://www.articy.com/help/adx/Templates_Templates.html)
- [articy:draft Entity Property Sheet](https://www.articy.com/help/adx/Entities_Sheet.html)
- [Arcweave Components Documentation](https://docs.arcweave.com/project-items/components)
- [Arcweave Elements Documentation](https://docs.arcweave.com/project-items/elements)
- [World Anvil Worldbuilding Templates](https://www.worldanvil.com/features/worldbuilding-templates)
- [World Anvil Character Sheets](https://www.worldanvil.com/features/interactive-character-sheets-statblocks)
- [Campfire Worldbuilding Tools](https://www.campfirewriting.com/worldbuilding-tools)
- [Campfire Write Review](https://kindlepreneur.com/campfire-write-review/)

### Comparisons & Reviews

- [LegendKeeper vs World Anvil](https://www.legendkeeper.com/world-anvil-alternative)
- [LegendKeeper vs Campfire](https://www.legendkeeper.com/legendkeeper-vs-campfire/)
- [World Anvil Alternatives](https://www.legendkeeper.com/best-world-anvil-alternatives/)
- [Campfire vs World Anvil](https://kindlepreneur.com/campfire-vs-world-anvil/)
- [Arcweave Top 10 Worldbuilding Tools](https://blog.arcweave.com/top-10-tools-for-worldbuilding)
- [Best Worldbuilding Software](https://www.quillandsteel.com/blogs/writing-tips/worldbuilding-software-tools)
- [Game Master's Guide to Worldbuilding Tools](https://artificerdm.com/the-game-masters-ultimate-guide-to-the-best-worldbuilding-tools/)

### Notion & Game Design

- [Notion for Indie Game Developers 2024](https://www.landmarklabs.co/blog/notion-for-indie-game-developers-ultimate-guide-2024)
- [Notion GDD Template](https://www.notion.com/templates/game-design-document-gdd-771)
- [Notion Character Template](https://www.notion.com/templates/game-design-document-characters)
- [Notion Worldbuilding Template](https://www.notion.com/templates/game-design-document-worldbuilding)
- [Why Users Abandon Notion](https://medium.com/@ruslansmelniks/why-users-abandon-notion-complexity-limitations-and-the-rise-of-ai-alternatives-cba91a95b535)
- [Why I Stopped Using Notion](https://uxplanet.org/why-i-stopped-using-notion-an-honest-ux-review-ebf03e268a01)

### Community Discussions

- [articy:draft Entity Relationships (Steam)](https://steamcommunity.com/app/230780/discussions/0/620700960784458920/)
- [Campfire Pro vs World Anvil (Steam)](https://steamcommunity.com/app/965480/discussions/0/1648791520851441879/)
- [World Anvil Experiences (D&D Beyond)](https://www.dndbeyond.com/forums/d-d-beyond-general/general-discussion/76516-website-world-anvil-experiences)
- [World Anvil Community Voting](https://www.worldanvil.com/community/voting/)
- [Organizational Tools Discussion (Choice of Games)](https://forum.choiceofgames.com/t/organizational-tools-programs-and-strategies/74627)

### Technical Resources

- [Entity Component System (Wikipedia)](https://en.wikipedia.org/wiki/Entity_component_system)
- [Evolve Your Hierarchy (Cowboy Programming)](https://cowboyprogramming.com/2007/01/05/evolve-your-heirachy/)
- [Database Inheritance Patterns (Redgate)](https://www.red-gate.com/blog/inheritance-in-database)
- [Games as Databases (Medium)](https://ajmmertens.medium.com/why-it-is-time-to-start-thinking-of-games-as-databases-e7971da33ac3)

### Design Resources

- [Character Design Sheets for Video Games](https://retrostylegames.com/blog/character-design-sheets-video-game/)
- [Game Character Profile Template (Milanote)](https://milanote.com/templates/game-design/game-character-profile)
- [Game Design Document Template (Nuclino)](https://www.nuclino.com/articles/game-design-document-template)
- [GDD Roadmap (Stepico)](https://stepico.com/blog/game-design-documentation/)
- [How to Write Game Lore](https://kreonit.com/idea-generation-and-game-design/game-lore/)
