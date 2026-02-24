# Page Property Inheritance Proposal

> **Date:** February 2024
> **Status:** Proposal
> **Related:** [Narrative Design Tools Research](../research/NARRATIVE_DESIGN_TOOLS_RESEARCH.md)

---

## Overview

A system for organic property inheritance between parent and child sheets, inspired by Notion's simplicity. No explicit "template mode" - inheritance emerges naturally from user decisions when creating properties.

## Design Principles

1. **Organic** - No configuration needed, just start creating
2. **In-context decisions** - Choose inheritance scope when adding each property
3. **Visual clarity** - Clear distinction between inherited vs own properties
4. **Flexible** - Any sheet can define inheritable properties, any child can detach
5. **Notion-like** - Feels natural, not "enterprise"

---

## Core Concept: Property Scope

When adding a property to a sheet, the user chooses its scope:

```
┌─────────────────────────────────────────┐
│ Add Property                            │
├─────────────────────────────────────────┤
│ Name: [Portrait          ]              │
│ Type: [Image Asset    ▼]                │
│                                         │
│ Scope:                                  │
│ ○ This sheet only                        │
│ ● This sheet and all children            │
│                                         │
│ [Cancel]                    [Add]       │
└─────────────────────────────────────────┘
```

- **"This sheet only"** → Property is local, only exists on this sheet
- **"This sheet and children"** → Property is inherited by all child sheets

---

## UI: Content Tab Layout

### Child Sheet View (e.g., "Jaime")

```
┌─────────────────────────────────────────────────────────┐
│ 📄 Jaime                                    [Content ▼] │
├─────────────────────────────────────────────────────────┤
│                                                         │
│ ┌─ Inherited from Characters ─────────────────────┐    │
│ │ 👤 Portrait    [Select image...]           🔗 ↑  │    │
│ │ 📅 Age         [32                ]        🔗 ↑  │    │
│ │ 📝 Backstory   [Rich text editor... ]      🔗 ↑  │    │
│ └──────────────────────────────────────────────────┘    │
│                                                         │
│ ┌─ Own Properties ────────────────────────────────┐    │
│ │ ⚔️ Weapon      [Sword             ]             │    │
│ │ 🏰 Faction     [House Lannister   ]             │    │
│ │                                                  │    │
│ │ [+ Add property]                                 │    │
│ └──────────────────────────────────────────────────┘    │
│                                                         │
│ ─────────────────────────────────────────────────────   │
│                                                         │
│ ## Description                                          │
│ Jaime is the eldest son of Tywin Lannister...          │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

The `🔗 ↑` icon indicates inherited property. Click navigates to the source sheet.

### Parent Sheet View (e.g., "Characters")

```
┌─────────────────────────────────────────────────────────┐
│ 📁 Characters                               [Content ▼] │
├─────────────────────────────────────────────────────────┤
│                                                         │
│ ┌─ Properties for children ───────────────────────┐    │
│ │ These properties will appear in all child sheets  │    │
│ │                                                  │    │
│ │ 👤 Portrait    [Image Asset    ]  [Required ✓]  │    │
│ │ 📅 Age         [Number         ]  [Optional  ]  │    │
│ │ 📝 Backstory   [Rich Text      ]  [Optional  ]  │    │
│ │                                                  │    │
│ │ [+ Add inherited property]                       │    │
│ └──────────────────────────────────────────────────┘    │
│                                                         │
│ ┌─ Own Properties ────────────────────────────────┐    │
│ │ (none)                                           │    │
│ │ [+ Add property]                                 │    │
│ └──────────────────────────────────────────────────┘    │
│                                                         │
│ ─────────────────────────────────────────────────────   │
│                                                         │
│ ## About Characters                                     │
│ This section contains all playable and non-playable    │
│ characters in the game world...                        │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

---

## Propagation Behavior

### New Children

New child sheets **automatically** inherit all "children scope" properties from their parent.

### Existing Children

When adding a new inheritable property to a sheet that already has children, show a propagation modal:

```
┌─────────────────────────────────────────────────────────┐
│ Propagate "Faction" to existing children?               │
├─────────────────────────────────────────────────────────┤
│                                                         │
│ This property will automatically appear in all          │
│ NEW children. For existing children:                    │
│                                                         │
│ ☑ Select all (12 sheets)                                │
│                                                         │
│ ▼ Characters                                            │
│   ☑ Jaime                                              │
│   ☑ Cersei                                             │
│   ☑ Tyrion                                             │
│   ▼ Nobles                                              │
│     ☑ Duke                                             │
│     ☐ Baron  ← (user deselected)                       │
│                                                         │
│ ───────────────────────────────────────────────────     │
│ ℹ️ Unselected sheets won't get this property but can     │
│    add it manually later.                               │
│                                                         │
│ [Cancel]                           [Propagate]          │
└─────────────────────────────────────────────────────────┘
```

---

## Multi-Level Inheritance

Properties cascade through the hierarchy:

```
Characters/           → Defines: Portrait, Age, Backstory
├── Jaime            → Inherits all, adds own: Weapon
├── Nobles/          → Inherits all, adds for children: Title, House
│   ├── Duke         → Inherits: Portrait, Age, Backstory, Title, House
│   └── Baron        → Inherits: Portrait, Age, Backstory, Title, House
└── Commoners/       → Inherits all, HIDES for children: Backstory
    └── Peasant      → Inherits: Portrait, Age (no Backstory)
```

---

## Actions on Inherited Properties

When hovering over an inherited property, show a context menu:

```
┌─ Inherited from Characters ─────────────────────────┐
│ 👤 Portrait    [Select image...]           [⋮]      │
│                                             │       │
│                              ┌──────────────┴─────┐ │
│                              │ 🔗 Go to source    │ │
│                              │ ✂️ Detach property │ │
│                              │ 🚫 Hide for children│ │
│                              └────────────────────┘ │
└─────────────────────────────────────────────────────┘
```

### Go to source
Navigate to the parent sheet where the property is defined.

### Detach property
Convert the inherited property into an "own" property. It will no longer sync with the parent definition. Useful when a child needs different configuration.

### Hide for children
This sheet still inherits the property, but its children will NOT inherit it. Useful for breaking inheritance at a specific level.

---

## Data Model Considerations

### Sheet Schema

```elixir
# Each sheet tracks:
# - Own properties (local to this sheet)
# - Inherited property definitions (for children)
# - Hidden inherited properties (from parent, not passed to children)
# - Detached properties (were inherited, now local)

%Sheet{
  properties: [
    %Property{
      name: "portrait",
      type: :image_asset,
      scope: :children,        # :self | :children
      inherited_from: nil,     # sheet_id if inherited
      detached: false,         # true if was inherited but now local
      hidden_for_children: false
    }
  ]
}
```

### Inheritance Resolution

When rendering a sheet's properties:

1. Get all properties with `scope: :children` from ancestors (walking up the tree)
2. Filter out any marked as `hidden_for_children` by intermediate sheets
3. Mark detached properties as local (don't sync with parent)
4. Merge with sheet's own properties
5. Display with visual distinction

---

## Use Cases

### Case 1: Game Characters

```
Characters/
├── Portrait (image) - inherited
├── Age (number) - inherited
├── Backstory (rich text) - inherited
│
├── Jaime
│   ├── [inherited: Portrait, Age, Backstory]
│   └── [own: Weapon, Faction]
│
└── NPCs/
    ├── [adds for children: Role, Schedule]
    │
    └── Merchant
        └── [inherited: Portrait, Age, Backstory, Role, Schedule]
```

### Case 2: Game Locations

```
Locations/
├── Climate (select) - inherited
├── Description (rich text) - inherited
├── Cover Image (image) - inherited
│
├── Night City/
│   ├── [inherited: Climate, Description, Cover Image]
│   ├── [own: Population, Factions]
│   ├── [adds for children: District Type]
│   │
│   ├── Watson/
│   │   ├── [inherited: all above]
│   │   └── [adds for children: Gang Territory]
│   │
│   │   └── Lizzie's Bar
│   │       └── [inherited: Climate, Description, Cover, District Type, Gang Territory]
```

### Case 3: Game Mechanics

```
Mechanics/
├── Description (rich text) - inherited
├── Complexity (select) - inherited
│
├── Movement/
│   ├── [adds for children: Input Key, Animation]
│   │
│   ├── Jump
│   │   ├── [inherited: Description, Complexity, Input Key, Animation]
│   │   │
│   │   ├── Long Jump
│   │   │   └── [inherited: all, own: Distance Multiplier]
│   │   │
│   │   └── Wall Jump
│   │       └── [inherited: all, own: Wall Detection Radius]
```

---

## Tab Organization

With many tabs needed (Content, References, Gallery, Audio, History, Version Control...), use grouped navigation:

```
┌─────────────────────────────────────────────────────────┐
│ 📄 Jaime                                                │
├─────────────────────────────────────────────────────────┤
│ [Content] [Media ▼] [History ▼] [Advanced ▼]           │
│            │         │           │                      │
│            │         │           └─ Version Control     │
│            │         │              Settings            │
│            │         │                                  │
│            │         └─ Changes                         │
│            │            Comments                        │
│            │                                            │
│            └─ Gallery                                   │
│               Audio                                     │
│               References                                │
└─────────────────────────────────────────────────────────┘
```

---

## FAQ

### Can a sheet with children NOT be a template?

**Yes.** If all its properties are "this sheet only", children inherit nothing. The sheet is just an organizational container with its own content.

### Can any sheet become a template?

**Yes.** The moment you add a property with "this sheet and children" scope, that sheet starts defining inheritance. It's emergent, not configured.

### What if I change a property type in the parent?

Children that haven't detached will see the type change. Values that don't match the new type could be:
- Cleared with a warning
- Preserved but marked as "incompatible"
- Converted if possible (e.g., number "42" → string "42")

### Can I re-attach a detached property?

**Yes.** Show an action to "Re-sync with parent" that would reset the property to match the parent's definition.

### What about default values?

Parent can define default values for inherited properties. Children inherit the default but can override with their own value.

---

## Implementation Notes

### Database

- Properties stored as JSONB on sheets
- Add `inherited_schema` field or compute dynamically from ancestors
- Consider caching resolved inheritance for performance

### UI Components

- `InheritedPropertiesSection` - Shows properties from parent with link icon
- `OwnPropertiesSection` - Shows local properties
- `PropertyScopeSelector` - Radio buttons for scope selection
- `PropagationModal` - Tree view with checkboxes for existing children

### Performance

- Cache resolved inheritance per sheet
- Invalidate cache when ancestor properties change
- Consider background job for large propagation operations

---

## Open Questions

1. **Property ordering** - Can children reorder inherited properties?
2. **Required vs optional** - Should inheritance respect required flag?
3. **Validation** - How to handle validation rules on inherited properties?
4. **Bulk operations** - UI for propagating to many children efficiently?
5. **Conflict resolution** - What if child has property with same name as new inherited one?
