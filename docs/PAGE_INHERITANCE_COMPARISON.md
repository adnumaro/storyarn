# Page Inheritance: Comparison with Industry Tools

> **Date:** February 2024
> **Related Research:** [Entity Database Tools Research](./research/ENTITY_DATABASE_TOOLS_RESEARCH.md)
> **Related Proposal:** [Page Inheritance Proposal](./PAGE_INHERITANCE_PROPOSAL.md)

---

## Executive Summary

After researching how articy:draft, Arcweave, World Anvil, Campfire, Notion, and other tools handle entity databases (characters, items, locations, bestiary), I can confidently say that **Storyarn's proposed Page Inheritance system is unique and potentially superior** to existing solutions.

The key insight: **No tool currently combines wiki-style organic creation with structured inheritance**.

---

## How Competitors Handle Entity Databases

### articy:draft: Template-Locked Entities

```
Template Design → Entity Templates → Character Template
                                  → Item Template
                                  → Enemy Template

Usage: Create entity → Assign template → Fill properties
```

**Pros:**
- Professional, structured
- Validation and constraints
- Export-ready for engines

**Cons:**
- Templates locked to one type only
- Cannot use same template twice on one object
- Template editor locks the entire app
- Rigid hierarchy: must define templates BEFORE creating content
- Steep learning curve

### Arcweave: Flat Components

```
Components/
├── Characters/
│   ├── Hero (attributes: name, health, backstory)
│   └── Villain (attributes: name, health, backstory)
└── Items/
    └── Sword (attributes: damage, weight)
```

**Pros:**
- Simple, flexible
- No forced structure
- Easy to start

**Cons:**
- No inheritance
- No schema enforcement
- Must define attributes per-component
- Duplicate work if many similar components

### World Anvil: Preset Article Types

```
New Article → Select Type → Character (predefined fields)
                         → Location (predefined fields)
                         → Item (predefined fields)
```

**Pros:**
- Guided experience
- 25+ templates for worldbuilding
- Fields designed for common use cases

**Cons:**
- Preset templates may not fit project
- Customization is complex
- "Too complicated, dozens of features I didn't need"
- Sharp learning curve

### Notion: User-Defined Databases

```
Create Database → Define Properties → name (text)
                                   → age (number)
                                   → faction (select)
                                   → portrait (file)
```

**Pros:**
- Complete flexibility
- Familiar interface
- Relational databases

**Cons:**
- No guidance whatsoever
- No inheritance between items
- Must manually create schema for each database
- "Jack of all trades, master of none"
- No game engine export

### Campfire: Separate Modules

```
Characters Module → Character 1
                 → Character 2
Items Module     → Item 1
                 → Item 2
Relationships Module (cross-links)
```

**Pros:**
- Modules interconnect automatically
- Focused tools for each entity type
- Publishing integration

**Cons:**
- Pay per module (can get expensive)
- Fixed module structure
- No custom entity types
- Not designed for game development

---

## Storyarn's Proposed Approach: Emergent Inheritance

```
Pages/
├── Characters/ ← defines: Portrait, Age, Backstory (inherited)
│   ├── Jaime ← inherits all, adds: Weapon, Faction
│   ├── Elena ← inherits all
│   └── Nobles/ ← inherits all, adds for children: Title, House
│       └── Duke ← inherits: Portrait, Age, Backstory, Title, House
├── Items/ ← defines: Weight, Value, Rarity
│   └── Sword ← inherits all, adds: Damage
└── Locations/ ← defines: Climate, Description
    └── Night City ← inherits all, adds for children: District Type
```

**Key Differentiators:**

1. **No upfront configuration**: Start creating immediately, like Notion
2. **Inheritance emerges**: Add property with "inherit to children" scope
3. **Any page can become a "template"**: Just by having children with inherited properties
4. **Visual clarity**: Inherited vs own properties clearly distinguished
5. **Flexible at any level**: Detach, hide, or extend inheritance

---

## Feature Comparison Matrix

| Feature              | articy:draft  | Arcweave   | World Anvil   | Notion   | Campfire  | **Storyarn**      |
|----------------------|---------------|------------|---------------|----------|-----------|-------------------|
| Organic creation     | ❌             | ✅          | ⚠️            | ✅        | ⚠️        | ✅                 |
| Property inheritance | ❌             | ❌          | ❌             | ❌        | ❌         | ✅                 |
| User-defined schemas | ✅             | ⚠️         | ⚠️            | ✅        | ❌         | ✅                 |
| Preset templates     | ✅             | ❌          | ✅             | ❌        | ✅         | ⚠️ (via examples) |
| Hierarchical pages   | ❌             | ❌          | ❌             | ✅        | ❌         | ✅                 |
| Flow integration     | ✅             | ✅          | ❌             | ❌        | ❌         | ✅                 |
| Real-time collab     | ⚠️            | ✅          | ⚠️            | ✅        | ✅         | ✅                 |
| Learning curve       | High          | Low        | High          | Low      | Medium    | **Low**           |

---

## Opinion: What Storyarn Gets Right

### 1. Wiki-First, Structure-When-Needed

The biggest insight from research: **users want wiki simplicity**. They reach for Notion despite its limitations because it lets them just start creating.

articy:draft forces upfront template design. World Anvil overwhelms with options. Storyarn's approach says: "Create a page. Add content. Want children to inherit? Just check a box."

This is the right mental model.

### 2. Hierarchy as Natural Organization

Nobody else uses page hierarchy for inheritance. They all have:
- Flat entity lists (articy, Arcweave)
- Separate modules (Campfire)
- Independent databases (Notion)

But game designers ALREADY think hierarchically:
- Characters → Player Characters, NPCs → Named NPCs, Generic NPCs
- Locations → Regions → Cities → Buildings → Rooms
- Items → Weapons → Swords, Axes, Bows

Storyarn's pages-as-hierarchy matches this mental model perfectly.

### 3. No Template Lock-In

articy:draft's biggest limitation: "Template is fixed to one type only."

In Storyarn, any page can define inheritable properties. There's no "Character Template" that can ONLY be used for entities. A page is a page is a page.

### 4. Integration Potential

Unlike Notion, Storyarn pages can be:
- Referenced in dialogue nodes (speaker)
- Used in conditions (if has_item("Sword"))
- Exported with technical IDs
- Connected to assets

This is the game-engine-ready aspect that wiki tools lack.

---

## Opinion: What Could Be Improved

### 1. Guided Starting Experience

World Anvil and Campfire have predefined templates because many users DON'T want to start from scratch. They want:
- "Here's what a Character usually looks like"
- "Here are common Item properties"

**Recommendation:** Offer optional "starter pages" or examples that users can copy/adapt. Not forced templates, but helpful starting points.

### 2. Relationship First-Class Support

articy:draft users struggle with character relationships (Father-Son, Allies, etc.). It's a common pain point.

**Current proposal limitation:** Relationships would be manual property additions.

**Recommendation:** Consider a dedicated "Relationships" feature or a special "Reference" property type that:
- Auto-creates bidirectional links
- Shows relationship type (Father, Ally, Enemy)
- Visualizable as graph/tree

### 3. Calculated/Dynamic Properties

articy:draft has "Calculated Strips" that query related objects dynamically.

**Example:** "Show all Items where location = this page"

**Recommendation:** Consider a "References" tab that auto-populates:
- Where this page is mentioned
- What pages reference this one
- Children summary

### 4. Property Type Richness

articy:draft supports:
- Slots (single reference)
- Strips (multiple references)
- Dropdowns with predefined values
- Constraints (min/max, required)

**Recommendation:** Ensure property types include:
- Text, Number, Boolean, Date
- Single select, Multi-select
- Asset reference (image, audio)
- Page reference (link to another page)
- Rich text

### 5. Bulk Operations

When propagating to many children, the modal approach is good but may need:
- "Select all" / "Deselect all"
- Filter by page name
- "Apply to all future children only" option

---

## Strategic Positioning

### vs articy:draft

**Message:** "All the power, none of the complexity. Start creating in 30 seconds, not 30 minutes."

**Key advantages:**
- No template lock-in
- Organic creation
- Web-based, real-time collaboration
- Lower price point

### vs Arcweave

**Message:** "Components with superpowers. Your entities can inherit, relate, and evolve."

**Key advantages:**
- Property inheritance
- Hierarchical organization
- Self-hosting option

### vs World Anvil

**Message:** "Built for game developers, not just worldbuilders. Your wiki exports to your engine."

**Key advantages:**
- Flow editor integration
- Game engine export
- Cleaner, simpler UI

### vs Notion

**Message:** "Notion for game design. Wiki flexibility with dialogue flows and engine export."

**Key advantages:**
- Flow editor
- Inheritance (Notion databases don't inherit)
- Purpose-built for games

### vs Campfire

**Message:** "All modules in one, with the flexibility Campfire lacks."

**Key advantages:**
- No module purchases
- Custom entity types
- Flow integration

---

## Implementation Priority

Based on research, I recommend this order:

### Phase 1: Core Page Inheritance (Current Proposal)
- [x] Property scope (this page only / children)
- [x] Inherited vs own property distinction
- [x] Propagation modal for existing children
- [x] Detach/Hide actions

### Phase 2: Rich Property Types
- [ ] Asset reference (select from project assets)
- [ ] Page reference (link to another page)
- [ ] Single/Multi select with predefined options
- [ ] Required/Optional flag
- [ ] Default values

### Phase 3: References & Relationships
- [ ] Auto-populated "Used In" tab (where is this page referenced)
- [ ] Page reference bidirectional linking
- [ ] Optional relationship types (Father, Ally, etc.)

### Phase 4: Starter Content
- [ ] Example "Characters" page with common properties
- [ ] Example "Items" page
- [ ] Example "Locations" page
- [ ] One-click copy to user's project

### Phase 5: Advanced Features
- [ ] Calculated properties (queries)
- [ ] Property validation/constraints
- [ ] Bulk property operations

---

## Conclusion

Storyarn's Page Inheritance proposal is **innovative and well-positioned**. It addresses the core frustrations users have with existing tools:

1. **articy:draft users** frustrated by rigid templates → Storyarn offers organic creation
2. **Notion users** frustrated by no inheritance → Storyarn adds it naturally
3. **World Anvil users** frustrated by complexity → Storyarn is simpler
4. **All users** want wiki + game integration → Storyarn provides both

The key is execution: keep it simple, visual, and intuitive. Don't add complexity just because articy:draft has it. The value is in the simplicity.

**The tagline should be:** "Create like Notion. Export like articy:draft. Collaborate like Figma."
