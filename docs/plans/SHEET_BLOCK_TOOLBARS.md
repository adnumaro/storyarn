# Sheet Block Toolbars — Replace Config Sidebar with Inline Toolbars

> **Goal:** Eliminate the sheet config sidebar (`config_panel.ex`) by migrating all block configuration to inline hover toolbars + floating popovers, consistent with the Scenes and Flows pattern.
>
> **Parent Epic:** [FOCUS_MODE_REDESIGN.md](completed/FOCUS_MODE_REDESIGN.md)
>
> **Priority:** Medium — can be implemented independently before the full layout redesign
>
> **Last Updated:** February 23, 2026

---

## Table of Contents

1. [Motivation](#1-motivation)
2. [Current State Analysis](#2-current-state-analysis)
3. [Target Design](#3-target-design)
4. [Per-Block-Type Toolbar Specs](#4-per-block-type-toolbar-specs)
5. [Wireframes](#5-wireframes)
6. [Implementation Plan](#6-implementation-plan)
7. [Files Affected](#7-files-affected)
8. [Migration Strategy](#8-migration-strategy)

---

## 1. Motivation

### Current Problems

1. **Context switch.** To configure a block, the user must: click "⋮" → click "Configure" → shift eyes to the right sidebar panel → make changes → close panel. The eyes leave the block being edited.

2. **The "⋮" menu is unclear.** Three dots don't communicate what actions are available. Users must click to discover. The menu only has two items: Configure and Delete.

3. **Sidebar occupies permanent space.** The config panel is `fixed inset-y-0 right-0 w-80` — it takes 320px and overlays content with a backdrop that blocks interaction with the sheet.

4. **Inconsistency with other editors.** Scenes and Flows already use inline floating toolbars for element configuration (zones, pins, nodes). Sheets is the only editor still using a sidebar panel.

### Reference Patterns (Already in App)

**Map zone toolbar** — appears on selection, contains: action type dropdown, name input, color picker, line style, layers, lock, and "⋯" menu expanding to tooltip/assignments popover.

**Flow node toolbar** — appears on selection, contains: node-type-specific actions inline + expandable popovers for conditions, instructions, etc.

**Table column header menu** — already inline: click column header → popover with Value/Constant/Required/Change type/Constraints/Delete column. This pattern already works for tables.

---

## 2. Current State Analysis

### Config Sidebar Content Inventory

The config panel (`lib/storyarn_web/components/block_components/config_panel.ex`) renders these fields based on block type:

#### Universal Fields (all block types)

| Field           | Control           | Notes                                             |
|-----------------|-------------------|---------------------------------------------------|
| Type            | Badge (read-only) | Shows block type + Inherited/Detached tag         |
| Scope           | Radio buttons (2) | "This sheet only" / "This sheet and all children" |
| Required        | Toggle            | Only when scope = "children"                      |
| Re-attach       | Button            | Only for detached inherited blocks                |
| Use as constant | Toggle            | Only for variable-capable types                   |
| Label           | Text input        | Block label/name                                  |
| Variable Name   | Code (read-only)  | Derived from label                                |

#### Type-Specific Fields

| Block Type     | Extra Fields                                                       | Complexity   |
|----------------|--------------------------------------------------------------------|--------------|
| `text`         | Placeholder, Max Length                                            | Low          |
| `rich_text`    | Placeholder, Max Length                                            | Low          |
| `number`       | Placeholder, Min, Max, Step                                        | Low          |
| `boolean`      | Mode (two/tri-state), Custom Labels (true/false/neutral)           | Medium       |
| `select`       | Placeholder, Max Selections*, Options list (key+label, add/remove) | Medium       |
| `multi_select` | Placeholder, Max Selections, Options list                          | Medium       |
| `date`         | Min Date, Max Date                                                 | Low          |
| `reference`    | Allowed Types (sheet/flow checkboxes)                              | Low          |
| `table`        | (nothing extra — columns managed inline already)                   | **None**     |

### Current Interaction Flow

```
User action:                                       UI response:
─────────────                                      ────────────
1. See "⋮" icon on block                           Hover state
2. Click "⋮"                                       Dropdown: [Configure] [Delete]
3. Click "Configure"                                Config sidebar slides in from right
4. Eyes shift to sidebar ← context switch           Full config panel with backdrop
5. Edit fields in sidebar                           Auto-save on change
6. Click ✕ or backdrop to close                     Sidebar slides out
7. Eyes return to block ← context switch back
```

**Total: 3 clicks + 2 context switches for any config change**

---

## 3. Target Design

### New Interaction Flow

```
User action:                                       UI response:
─────────────                                      ────────────
1. Hover over block                                 Toolbar appears above/near block
2. See all quick actions inline                     Type icon, label, toggles, delete
3. Click config icon or type-specific area          Popover appears anchored to block
4. Edit fields in popover (near the block)          Auto-save on change
5. Click outside to dismiss                         Popover closes
```

**Total: 1-2 clicks, 0 context switches. Eyes never leave the block.**

### Core Principle

- **Quick actions** (delete, move, change type, toggle constant) → directly in toolbar
- **Detailed config** (constraints, options list, scope) → popover expanding from toolbar
- **No sidebar** — all config happens near the block via floating-ui popovers

---

## 4. Per-Block-Type Toolbar Specs

### 4.1 Universal Toolbar (All Types)

Every block's hover toolbar contains these base elements:

```
┌───────────────────────────────────────────────────────────────────┐
│ ⠿ │ # │ "Label" ────────── │ 🔒 │ 📋 │ ⬆ │ ⬇ │ 📄 │ 🗑 │ ⚙ │
└───────────────────────────────────────────────────────────────────┘
  │    │       │                 │     │    │    │    │    │    │
  │    │       │                 │     │    │    │    │    │    └─ Config popover (type-specific)
  │    │       │                 │     │    │    │    │    └─ Delete block
  │    │       │                 │     │    │    │    └─ Duplicate block
  │    │       │                 │     │    │    └─ Move down
  │    │       │                 │     │    └─ Move up
  │    │       │                 │     └─ Copy variable reference
  │    │       │                 └─ Toggle constant (lock icon)
  │    │       └─ Inline label edit (click to edit)
  │    └─ Type icon/badge (click → change type submenu)
  └─ Drag handle
```

**Which items show conditionally:**
- 🔒 Constant toggle: only for variable-capable types
- 📋 Copy reference: only when not constant
- ⬆⬇ Move: always (existing reorder functionality)
- ⚙ Config: only for types with extra config (not table)

### 4.2 Number Block

```
Toolbar:
┌───────────────────────────────────────────────────────┐
│ ⠿ │ # │ "Health Points" │ 🔒 │ 📋 │ ⬆⬇ │ 📄 │ 🗑 │ ⚙ │
└───────────────────────────────────────────────────────┘

⚙ Config popover:
┌─────────────────────────────┐
│ Constraints                 │
│ ┌─────────┐  ┌─────────┐   │
│ │ Min: 0  │  │ Max: 100│   │
│ └─────────┘  └─────────┘   │
│ ┌─────────────────────┐    │
│ │ Step: 1             │    │
│ └─────────────────────┘    │
│                             │
│ Placeholder                 │
│ ┌─────────────────────┐    │
│ │ Enter value...      │    │
│ └─────────────────────┘    │
│                             │
│ ─── Advanced ───            │
│ Scope: ○ Self  ● Children  │
│ □ Required                  │
│                             │
│ Variable: health_points     │
└─────────────────────────────┘
```

### 4.3 Select / Multi-Select Block

```
Toolbar:
┌───────────────────────────────────────────────────────────┐
│ ⠿ │ ▾ │ "Current Class" │ 🔒 │ 📋 │ ⬆⬇ │ 📄 │ 🗑 │ ⚙ │
└───────────────────────────────────────────────────────────┘

⚙ Config popover:
┌─────────────────────────────────┐
│ Options                         │
│ ┌────────┬──────────────┬───┐   │
│ │ fighter│ Fighter       │ ✕ │   │
│ │ mage   │ Mage          │ ✕ │   │
│ │ thief  │ Thief         │ ✕ │   │
│ │ ranger │ Ranger        │ ✕ │   │
│ └────────┴──────────────┴───┘   │
│ [+ Add option]                  │
│                                 │
│ Placeholder                     │
│ ┌─────────────────────────┐     │
│ │ Select class...         │     │
│ └─────────────────────────┘     │
│                                 │
│ Max Selections: [ ] (multi only)│
│                                 │
│ ─── Advanced ───                │
│ Scope: ○ Self  ● Children      │
│ □ Required                      │
│                                 │
│ Variable: current_class         │
└─────────────────────────────────┘
```

### 4.4 Boolean Block

```
Toolbar:
┌──────────────────────────────────────────────────────────────┐
│ ⠿ │ ☑ │ "Secret Revealed" │ 🔒 │ 📋 │ ⬆⬇ │ 📄 │ 🗑 │ ⚙ │
└──────────────────────────────────────────────────────────────┘

⚙ Config popover:
┌─────────────────────────────────┐
│ Mode                            │
│ ○ Two states (Yes/No)           │
│ ○ Three states (Yes/Neutral/No) │
│                                 │
│ Custom Labels                   │
│ ┌───────────┐  ┌────────────┐  │
│ │ True: Yes │  │ False: No  │  │
│ └───────────┘  └────────────┘  │
│ ┌───────────────────────────┐  │
│ │ Neutral: Unknown          │  │ ← only if tri-state
│ └───────────────────────────┘  │
│                                 │
│ ─── Advanced ───                │
│ Scope: ○ Self  ● Children      │
│ □ Required                      │
│                                 │
│ Variable: secret_revealed       │
└─────────────────────────────────┘
```

### 4.5 Text / Rich Text Block

```
Toolbar:
┌──────────────────────────────────────────────────────────┐
│ ⠿ │ T │ "Description" │ 🔒 │ 📋 │ ⬆⬇ │ 📄 │ 🗑 │ ⚙ │
└──────────────────────────────────────────────────────────┘

⚙ Config popover:
┌─────────────────────────────┐
│ Placeholder                 │
│ ┌─────────────────────┐    │
│ │ Enter description...│    │
│ └─────────────────────┘    │
│                             │
│ Max Length                   │
│ ┌─────────────────────┐    │
│ │ (no limit)          │    │
│ └─────────────────────┘    │
│                             │
│ ─── Advanced ───            │
│ Scope: ○ Self  ● Children  │
│ □ Required                  │
│                             │
│ Variable: description       │
└─────────────────────────────┘
```

### 4.6 Date Block

```
⚙ Config popover:
┌─────────────────────────────────┐
│ Date Range                      │
│ ┌─────────────┐ ┌─────────────┐│
│ │ Min: ______ │ │ Max: ______ ││
│ └─────────────┘ └─────────────┘│
│                                 │
│ ─── Advanced ───                │
│ Scope: ○ Self  ● Children      │
│ Variable: birth_date            │
└─────────────────────────────────┘
```

### 4.7 Reference Block

```
⚙ Config popover:
┌─────────────────────────────────┐
│ Allowed Types                   │
│ ☑ Sheets                       │
│ ☑ Flows                        │
│                                 │
│ ─── Advanced ───                │
│ Scope: ○ Self  ● Children      │
│ Variable: related_npc           │
└─────────────────────────────────┘
```

### 4.8 Table Block — No Toolbar Config

Table blocks have **no config popover**. All configuration is already inline:
- Column headers → click opens column menu (type, constraints, delete)
- Row names → inline editable
- Cells → inline editable
- Add row → "+" button below table
- Add column → "+" button on right edge

The hover toolbar for table only shows: drag handle, type badge, label edit, move, duplicate, delete. No ⚙.

---

## 5. Wireframes

### 5.1 Sheet with Hover Toolbar (No Block Selected)

```
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│  🛡 The Nameless One                                         │
│  # the-nameless-one                                          │
│                                                              │
│  Content │ References │ Audio │ History                      │
│                                                              │
│  ┌─ Stats ──────────────────────────────────────────────┐   │
│  │                                                       │   │
│  │ Strength ............. 18                              │   │
│  │ Dexterity ............ 9                               │   │
│  │ Constitution ......... 9                               │   │
│  │                                                       │   │
│  └───────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌─ Description ────────────────────────────────────────┐   │
│  │                                                       │   │
│  │ A scarred, immortal being who has died countless      │   │
│  │ times, each death erasing his memories...             │   │
│  │                                                       │   │
│  └───────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌─ Current Class ──────────────────────────────────────┐   │
│  │                                                       │   │
│  │ [ Fighter ▾ ]                                         │   │
│  │                                                       │   │
│  └───────────────────────────────────────────────────────┘   │
│                                                              │
│  Type / to add a block                                       │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### 5.2 Hovering Over "Current Class" Block

```
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│  ┌─ Description ────────────────────────────────────────┐   │
│  │ A scarred, immortal being who has died countless      │   │
│  │ times, each death erasing his memories...             │   │
│  └───────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ ⠿ │▾│"Current Class"│ 🔒 │ 📋 │ ⬆ │ ⬇ │ 📄 │ 🗑 │⚙│   │
│  ├──────────────────────────────────────────────────────┤   │
│  │                                                       │   │
│  │ [ Fighter ▾ ]                                    ◄─── hover highlight
│  │                                                       │   │
│  └───────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌─ Secret Revealed ───────────────────────────────────┐   │
│  │ [ ] No                                                │   │
│  └───────────────────────────────────────────────────────┘   │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### 5.3 Config Popover Open on "Current Class"

```
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ ⠿ │▾│"Current Class"│ 🔒 │ 📋 │ ⬆ │ ⬇ │ 📄 │ 🗑 │⚙│   │
│  ├──────────────────────────────────────┬───────────────┤   │
│  │                                      │ Options       │   │
│  │ [ Fighter ▾ ]                        │               │   │
│  │                                      │ fighter  Fighter│  │
│  │                                      │ mage     Mage   │  │
│  │                                      │ thief    Thief  │  │
│  │                                      │ ranger   Ranger │  │
│  │                                      │ [+ Add option]  │  │
│  │                                      │               │   │
│  └──────────────────────────────────────│ Placeholder   │   │
│                                         │ Select class..│   │
│  ┌─ Secret Revealed ───────────────┐   │               │   │
│  │ [ ] No                           │   │ ── Advanced ──│   │
│  └──────────────────────────────────┘   │ Scope: ●Self  │   │
│                                         │ Variable:     │   │
│                                         │ current_class │   │
│                                         └───────────────┘   │
│                                                              │
└──────────────────────────────────────────────────────────────┘

         block content                    floating popover
         (still visible)                  (anchored to ⚙ icon)
```

### 5.4 Table Block with Column Menu (Already Inline — No Change)

```
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ ⠿ │ 📊 │ "Stats" │ ⬆ │ ⬇ │ 📄 │ 🗑 │               │  │
│  ├───────────────────┬────────────────────────────────┬───┤  │
│  │                   │ # Value ▾                      │   │  │
│  │                   │ ┌─────────────────────────┐    │ + │  │
│  ├───────────────────┤ │ # Value                 │    │   │  │
│  │ Strength     str  │ │ 🔒 Constant              │    │   │  │
│  │ Dexterity    dex  │ │ * Required               │    │   │  │
│  │ Constitution con  │ │ ⇋ Change type          ▸ │    │   │  │
│  │ Intelligence int  │ │ ⚙ Constraints          ▸ │    │   │  │
│  │ Wisdom       wis  │ │ 🗑 Delete column          │    │   │  │
│  │ Charisma     cha  │ └─────────────────────────┘    │   │  │
│  ├───────────────────┴────────────────────────────────┤   │  │
│  │                      [+]                            │   │  │
│  └─────────────────────────────────────────────────────┘──┘  │
│                                                              │
│  Type / to add a block                                       │
│                                                              │
└──────────────────────────────────────────────────────────────┘

      Table already manages everything inline — no sidebar needed
```

### 5.5 Inherited Block (Detached State)

```
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ ⠿ │ # │ "Health" │ ⚠ Detached │ 🔒 │ 📋 │ ⬆⬇│ 🗑 │⚙│   │
│  ├──────────────────────────────────────────────────────┤   │
│  │                                                       │   │
│  │ [ 100 ]                                               │   │
│  │                                                       │   │
│  └───────────────────────────────────────────────────────┘   │
│                                                              │
│  ⚙ Popover when detached:                                    │
│  ┌─────────────────────────────┐                             │
│  │ ⚠ This block is detached   │                             │
│  │ from its parent definition  │                             │
│  │                             │                             │
│  │ [🔗 Re-sync with source]   │                             │
│  │ Resets definition to match  │                             │
│  │ parent. Value preserved.    │                             │
│  │                             │                             │
│  │ Constraints                 │                             │
│  │ Min: [0]  Max: [999]        │                             │
│  │ Step: [1]                   │                             │
│  │                             │                             │
│  │ Variable: health            │                             │
│  └─────────────────────────────┘                             │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

---

## 6. Implementation Plan

### Phase 1: Hover Toolbar Component

- [ ] Create `StoryarnWeb.Components.BlockComponents.BlockToolbar` function component
- [ ] Toolbar appears on block hover (CSS hover or JS-managed, TBD)
- [ ] Universal actions: drag handle, type badge, label edit, move up/down, duplicate, delete
- [ ] Conditional actions: constant toggle, copy variable reference
- [ ] Wire existing events: `move_block_up`, `move_block_down`, `duplicate_block`, `delete_block`, `toggle_constant`
- [ ] Remove the current "⋮" menu dropdown

### Phase 2: Config Popovers (Per Type)

- [ ] Create popover component using `floating_popover.js` pattern
- [ ] `number` popover: min/max/step/placeholder
- [ ] `text` / `rich_text` popover: placeholder, max length
- [ ] `select` / `multi_select` popover: options list (key+label, add/remove), placeholder, max selections
- [ ] `boolean` popover: mode selector, custom labels
- [ ] `date` popover: min/max date
- [ ] `reference` popover: allowed types checkboxes
- [ ] Each popover includes "Advanced" section: scope, required, variable name

### Phase 3: Wire Config Save Events

- [ ] Route `save_block_config` events from new popovers
- [ ] Route `change_block_scope`, `toggle_required`, `toggle_constant` from new locations
- [ ] Route `add_select_option`, `remove_select_option`, `update_select_option` from popover
- [ ] Ensure undo/redo integration works with new event sources
- [ ] Verify auto-save behavior matches current sidebar behavior

### Phase 4: Remove Old Config Sidebar

- [ ] Remove `config_panel.ex` component
- [ ] Remove `config_panel_handlers.ex` (merge events into block toolbar handler)
- [ ] Remove `configuring_block` assign from ContentTab
- [ ] Remove `configure_block` and `close_config_panel` events
- [ ] Remove backdrop overlay
- [ ] Clean up `config_helpers.ex` if no longer needed

### Phase 5: Polish

- [ ] Keyboard navigation: Tab through toolbar items
- [ ] Escape to close popover
- [ ] Popover auto-repositions on scroll (floating-ui autoUpdate)
- [ ] Animation: subtle fade/scale on popover open
- [ ] Accessibility: ARIA roles for toolbar and popover

---

## 7. Files Affected

### Components (Modify/Create)

| File                                           | Action     | Notes                                             |
|------------------------------------------------|------------|---------------------------------------------------|
| `components/block_components/config_panel.ex`  | **DELETE** | Entire file removed in Phase 4                    |
| `components/block_components/block_toolbar.ex` | **CREATE** | New hover toolbar component                       |
| `components/block_components.ex`               | Modify     | Remove `config_panel` import, add `block_toolbar` |
| `components/block_components/*.ex` (per type)  | Modify     | Add toolbar trigger integration                   |

### LiveView Handlers

| File                                             | Action     | Notes                                                |
|--------------------------------------------------|------------|------------------------------------------------------|
| `sheet_live/handlers/config_panel_handlers.ex`   | **DELETE** | Events move to block toolbar handler                 |
| `sheet_live/handlers/block_toolbar_handlers.ex`  | **CREATE** | New handler for toolbar+popover events               |
| `sheet_live/components/content_tab.ex`           | Modify     | Remove `configuring_block` assign, `show_block_menu` |
| `sheet_live/components/own_blocks_components.ex` | Modify     | Replace "⋮" menu with toolbar trigger                |

### JS / Hooks

| File                                  | Action     | Notes                                                 |
|---------------------------------------|------------|-------------------------------------------------------|
| `assets/js/hooks/block_toolbar.js`    | **CREATE** | Hook for toolbar + popover management via floating-ui |
| `assets/js/utils/floating_popover.js` | Reuse      | Existing utility for body-appended popovers           |

### Helpers

| File                                   | Action   | Notes                               |
|----------------------------------------|----------|-------------------------------------|
| `sheet_live/helpers/config_helpers.ex` | Evaluate | May be deletable or reduced         |
| `sheet_live/helpers/block_helpers.ex`  | Modify   | Remove `show_block_menu` references |

---

## 8. Migration Strategy

### Approach: Parallel Then Switch

1. **Build new toolbar + popovers alongside existing sidebar** (Phases 1-3)
2. **Both coexist temporarily** — toolbar for quick actions, sidebar still accessible
3. **User testing** — verify all config flows work via toolbar
4. **Remove sidebar** (Phase 4) only after toolbar is verified complete

This avoids a risky big-bang replacement. At any point during development, the existing sidebar remains functional.

### Testing Checklist

For each block type, verify:
- [ ] All config fields accessible via toolbar/popover
- [ ] Config changes save correctly (auto-save on change)
- [ ] Undo/redo works for config changes made via toolbar
- [ ] Inherited blocks show correct state (inherited badge, detached warning)
- [ ] Scope changes propagate to children
- [ ] Variable name updates when label changes
- [ ] Select/multi-select option management (add, edit, remove, reorder)
- [ ] Popover positioning works inside scrollable sheet content
- [ ] Popover doesn't clip at viewport edges

---

## Related Documents

- [FOCUS_MODE_REDESIGN.md](completed/FOCUS_MODE_REDESIGN.md) — Parent epic for the full layout redesign
- [PHASE_7_5_SHEETS_ENHANCEMENT.md](./PHASE_7_5_SHEETS_ENHANCEMENT.md) — Sheet editor improvements
- [UNIFIED_UNDO_REDO.md](completed/UNIFIED_UNDO_REDO.md) — Undo/redo system (must remain compatible)
