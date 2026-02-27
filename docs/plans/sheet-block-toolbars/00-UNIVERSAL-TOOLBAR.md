# Plan 0: Universal Block Toolbar

> **Scope:** Replace the "..." DaisyUI dropdown on blocks with a minimal hover toolbar. Foundation for Plans 1-7 (per-type config popovers) and Plan 8 (sidebar cleanup).
>
> **Depends on:** Nothing (foundation plan)
>
> **Blocked by:** Plans 1-7 depend on this

---

## Terminology

- **Toolbar** = horizontal bar of buttons above the block (hover-visible). Contains: Duplicate, Constant toggle, Config gear, [⋮] menu.
- **Config Popover** = floating panel that opens FROM the Config gear button. Contains type-specific configuration fields. Built in Plans 1-7 using `ToolbarPopover` hook.
- **[⋮] Menu** = dropdown within the toolbar for less frequent actions (Delete, inherited actions).
- **Block-level elements** = drag handle, label, value, scope indicator — stay ON the block, not in toolbar.

---

## Goal

Every block (own and inherited) shows a hover toolbar above the block with minimal actions. Block selection via click enables keyboard shortcuts for frequent operations.

**Toolbar contains ONLY:**
- Duplicate
- Constant toggle (variable-capable types only)
- Config gear (opens existing sidebar temporarily, until Plans 1-7)
- [⋮] overflow menu (Delete + inherited actions)

**NOT in toolbar (stays on block):**
- Drag handle (stays in current position on block)
- Type icon
- Label edit (EditableBlockLabel hook, stays inline)
- Move buttons (keyboard shortcuts instead: Shift+arrows)
- Delete button (keyboard shortcut + [⋮] menu fallback)
- Copy reference
- Scope indicator

**NEW: Block selection (`selected_block_id`):**
- Click/focus sets `selected_block_id`
- Visual highlight on selected block (`ring-2 ring-primary/30`)
- Enables keyboard shortcuts (Delete, Cmd+D, Shift+arrows, Escape)

---

## Design Decisions

### What Flow/Scene toolbars DO:
- Appear on **element selection** (click)
- Contain **type-specific inline configuration** (dropdowns, color pickers, toggles)
- **Do NOT contain**: delete, duplicate, move — those are keyboard shortcuts + context menu

### Adaptation for Sheets (Notion-like, no canvas):

| Concern | Decision | Rationale |
|---------|----------|-----------|
| Toolbar trigger | **Hover** (CSS `group-hover`) | Replaces existing "..." hover pattern. No server roundtrip. |
| Block selection | **Click/focus** sets `selected_block_id` | Required for keyboard shortcuts. Visual highlight on selected. |
| Toolbar content | **Duplicate + Constant toggle + Config gear + [⋮]** | Minimal. Non-inline actions only. |
| Delete | **Keyboard shortcut** (Delete/Backspace) + [⋮] menu | Not a standalone toolbar button. |
| Move | **Keyboard shortcuts** (Shift+arrows) | Not in toolbar. Drag handle stays on block. |
| Config gear | **Temporarily opens existing sidebar** | Until Plans 1-7 replace with popovers. |
| Inherited actions | **In toolbar [⋮] submenu** | Go to source, Detach, Hide for children. |

---

## Toolbar Layout Per Block Type

```
Own block (variable-capable):
┌─────────────────────────────────────────────────────┐
│ [Duplicate 📋] [Constant 🔒/🔓] [Config ⚙] [⋮]    │
└─────────────────────────────────────────────────────┘


Own block (table):
┌──────────────────┐
│ [Duplicate] [⋮]  │
└──────────────────┘

Own block (reference — non-variable but has config):
┌───────────────────────────┐
│ [Duplicate] [Config ⚙] [⋮]│
└───────────────────────────┘

Inherited block (variable-capable):
┌────────────────────────────────────────────────────────────────────┐
│ [Duplicate] [Constant 🔒/🔓] [Config ⚙] [⋮ → Source, Detach, Hide, Delete] │
└────────────────────────────────────────────────────────────────────┘
```

**[⋮] dropdown always contains:** Delete
**[⋮] for inherited blocks also contains:** Go to source, Detach, Hide for children

**Conditional rendering flags:**
- `show_constant` = type not in `["reference", "table"]`
- `show_config` = type not in `["table"]`

---

## Reusable Components

| Component | Source | Reuse Strategy |
|-----------|--------|----------------|
| `ToolbarPopover` JS hook | `assets/js/hooks/toolbar_popover.js` | Used by config gear popover (Plans 1-7) |
| `createFloatingPopover` | `assets/js/utils/floating_popover.js` | Not needed for toolbar — it's CSS-positioned |
| `<.block_advanced_config>` | **NEW** shared sub-component | Created in this plan, used in Plans 1-7 |

### Boundary Compliance

No cross-context imports. All reused assets are in shared locations:
- `ToolbarPopover` JS hook → `assets/js/hooks/` (global, registered in `app.js`)
- New Elixir components → `lib/storyarn_web/components/block_components/` (web layer)
- New handlers → `lib/storyarn_web/live/sheet_live/handlers/` (sheet-specific)

---

## Phase 1: Domain Layer — New BlockCrud Functions

### `duplicate_block/1` in `lib/storyarn/sheets/block_crud.ex`

- Shift subsequent blocks' positions by +1
- Call existing `create_block/2` (handles auto variable_name, table structure, inheritance)
- Copy: type, config, value, scope, is_constant, position+1, column_group_id, column_index
- Do NOT copy: inherited_from_block_id (duplicate is always "own"), variable_name (auto-generated)

### `move_block_up/2` and `move_block_down/2` in `block_crud.ex`

- Load blocks via `list_blocks/1` (already ordered by position)
- Find block index, swap positions with adjacent block
- Return `{:ok, :already_first}` / `{:ok, :already_last}` for boundary cases
- Transaction for atomic swap

### Facade delegates in `lib/storyarn/sheets.ex`

```elixir
defdelegate duplicate_block(block), to: BlockCrud
defdelegate move_block_up(block_id, sheet_id), to: BlockCrud
defdelegate move_block_down(block_id, sheet_id), to: BlockCrud
```

---

## Phase 2: Toolbar Component

### `lib/storyarn_web/components/block_components/block_toolbar.ex` (CREATE)

**Function component:** `block_toolbar/1`

**Attrs:**
- `block` (map, required)
- `can_edit` (boolean)
- `is_inherited` (boolean)
- `target` (any) — for phx-target on events

**CSS positioning:** Inside block `group` div, absolute positioned above:
```css
absolute -top-9 left-0
flex items-center gap-0.5 px-1.5 py-1
bg-base-200 border border-base-300 rounded-lg shadow-sm
opacity-0 group-hover:opacity-100 transition-opacity z-10
pointer-events-none group-hover:pointer-events-auto
```

**Buttons (all use `phx-click` with `phx-value-id={@block.id}`):**
1. **Duplicate** — `phx-click="duplicate_block"`, icon: `copy`
2. **Constant toggle** — `phx-click="toolbar_toggle_constant"`, icon: `lock`/`unlock`, conditional on `show_constant`
3. **Config gear** — `phx-click="configure_block"` (reuses existing event), icon: `settings`, conditional on `show_config`
4. **[⋮] menu** — DaisyUI dropdown (temporary):
   - Delete — `phx-click="delete_block"`, icon: `trash-2`, red text
   - *Inherited only:* Go to source, Detach, Hide for children

**Read-only mode** (`can_edit=false`): toolbar hidden entirely.

### `lib/storyarn_web/components/block_components/block_advanced_config.ex` (CREATE)

Shared "Advanced" section for future config popovers (Plans 1-7). Renders:
- Scope selector (self/children)
- Required toggle (when scope=children)
- Variable name display (read-only)
- Re-attach button (detached blocks)

Uses `data-event`/`data-params` pattern since it will render inside ToolbarPopover (cloned outside LiveView DOM).

---

## Phase 3: Block Selection + Keyboard Shortcuts

### Selection State

- Add assign: `selected_block_id` (default: nil)
- Add events: `"select_block"`, `"deselect_block"`
- Visual feedback when selected: `ring-2 ring-primary/30` border
- `phx-click="select_block"` on block wrapper

### Keyboard Shortcuts — `assets/js/hooks/block_keyboard.js` (CREATE)

Attached to blocks container. Listens for keydown events.

| Shortcut | Event pushed | Condition |
|----------|-------------|-----------|
| `Delete` / `Backspace` | `delete_block` | Block selected, not editing text |
| `Cmd+D` / `Ctrl+D` | `duplicate_block` | Block selected |
| `Shift+ArrowUp` | `move_block_up` | Block selected |
| `Shift+ArrowDown` | `move_block_down` | Block selected |
| `Escape` | `deselect_block` | Block selected |

**Guard:** Ignores shortcuts when focus is inside `<input>`, `<select>`, `<textarea>`, or `[contenteditable]`.

### Server-side handlers — `block_toolbar_handlers.ex` (CREATE)

- `handle_duplicate_block/3`
- `handle_toggle_constant/3`
- `handle_move_block_up/3`
- `handle_move_block_down/3`

All look up block via `Sheets.get_block_in_project(block_id, project_id)`.

---

## Phase 4: Integration — Modify Existing Files

### `block_components.ex`

1. Add delegate: `defdelegate block_toolbar(assigns), to: BlockToolbar`
2. **Remove** `block_context_menu` div and function
3. **Add** `<.block_toolbar>` inside block group div
4. **Add** `phx-click="select_block"` on block wrapper
5. **Add** `selected_block_id` attr and conditional selection ring
6. **Keep** drag handle, scope indicator as-is

### `content_tab.ex`

1. Add alias: `BlockToolbarHandlers`
2. Add assign: `selected_block_id` (default: nil)
3. Add events: `duplicate_block`, `toolbar_toggle_constant`, `move_block_up`, `move_block_down`, `select_block`, `deselect_block`
4. Add `phx-hook="BlockKeyboard"` to blocks container
5. Pass `selected_block_id` down to blocks
6. **Keep** existing `configure_block`, `delete_block`, `toggle_constant` events

### `own_blocks_components.ex`

Pass `selected_block_id` attr through to `block_component`.

### `app.js`

Register `BlockKeyboard` hook.

---

## Phase 5: Undo/Redo Support

| Action | Undo type | Source |
|--------|-----------|--------|
| Duplicate | `{:create_block, snapshot}` | Reuse existing from `handle_add_block` |
| Toggle constant | `{:toggle_constant, block_id, prev, new}` | Reuse existing from `ConfigPanelHandlers` |
| Move up/down | `{:reorder_blocks, prev_order, new_order}` | Reuse existing from `handle_reorder` |

---

## Tests

### Domain — `test/storyarn/sheets/block_crud_test.exs`

```
describe "duplicate_block/1" (5 tests)
  - creates copy with same type, config, value, scope
  - position is original + 1
  - shifts subsequent block positions
  - generates unique variable_name
  - does NOT copy inherited_from_block_id

describe "move_block_up/2" (3 tests)
  - swaps with previous block
  - returns {:ok, :already_first} for first block
  - returns {:error, :not_found} for invalid id

describe "move_block_down/2" (3 tests)
  - swaps with next block
  - returns {:ok, :already_last} for last block
  - returns {:error, :not_found} for invalid id
```

### Component — `test/storyarn_web/components/block_toolbar_test.exs`

```
describe "block_toolbar/1" (~12 tests)
  - renders duplicate button for own blocks
  - renders constant toggle for variable-capable types
  - hides constant toggle for reference/table
  - renders config gear for configurable types
  - hides config gear for table
  - renders [⋮] menu with delete
  - renders inherited actions in [⋮] for inherited blocks
  - hides toolbar when can_edit=false
  - shows lock icon when is_constant=true
  - shows unlock icon when is_constant=false
  - renders duplicate for table (only action besides [⋮])
```

### Component — `test/storyarn_web/components/block_advanced_config_test.exs`

```
describe "block_advanced_config/1" (6 tests)
  - renders scope selector for own blocks
  - hides scope selector for inherited blocks
  - shows required toggle when scope=children
  - hides required toggle when scope=self
  - shows variable name for non-constant variable-capable
  - hides variable name for constant blocks
```

### Integration — `test/storyarn_web/live/sheet_live/handlers/block_toolbar_integration_test.exs`

```
describe "toolbar actions" (~8 tests)
  - duplicate_block creates copy at position+1
  - toolbar_toggle_constant toggles flag and reloads
  - move_block_up swaps with previous
  - move_block_down swaps with next
  - select_block sets selected_block_id
  - deselect_block clears selected_block_id
  - delete_block works via toolbar [⋮] menu
  - viewer cannot use toolbar actions (authorization)
```

**Total: ~37 tests**

---

## Critical Files

| File | Action |
|------|--------|
| `lib/storyarn/sheets/block_crud.ex` | Add `duplicate_block`, `move_block_up`, `move_block_down` |
| `lib/storyarn/sheets.ex` | Add 3 facade delegates |
| `lib/storyarn_web/components/block_components/block_toolbar.ex` | **CREATE** (~100 lines) |
| `lib/storyarn_web/components/block_components/block_advanced_config.ex` | **CREATE** (~80 lines) |
| `lib/storyarn_web/live/sheet_live/handlers/block_toolbar_handlers.ex` | **CREATE** (~80 lines) |
| `lib/storyarn_web/components/block_components.ex` | Replace context menu with toolbar, add selection |
| `lib/storyarn_web/live/sheet_live/components/content_tab.ex` | Wire new events, add selection + hook |
| `lib/storyarn_web/live/sheet_live/components/own_blocks_components.ex` | Pass selected_block_id |
| `assets/js/hooks/block_keyboard.js` | **CREATE** (~60 lines) |
| `assets/js/app.js` | Register BlockKeyboard hook |

---

## Post-Implementation Audit Checklist

- [ ] `mix compile --warnings-as-errors` — no warnings
- [ ] `mix format --check-formatted` — all formatted
- [ ] `mix credo --strict` — 0 issues
- [ ] `mix test` — all pass (existing + new)
- [ ] Manual: hover any block → toolbar appears above with correct buttons per type
- [ ] Manual: toolbar hides when mouse leaves block area
- [ ] Manual: click duplicate → new block appears below with unique variable name
- [ ] Manual: click constant toggle → lock/unlock icon toggles
- [ ] Manual: click config gear → existing config sidebar opens (temporary)
- [ ] Manual: click [⋮] → dropdown with Delete (+ inherited actions)
- [ ] Manual: click block → visual highlight (ring), keyboard shortcuts active
- [ ] Manual: Delete/Backspace → deletes selected block
- [ ] Manual: Cmd+D → duplicates selected block
- [ ] Manual: Shift+↑/↓ → moves selected block
- [ ] Manual: Escape → deselects
- [ ] Manual: inherited blocks show Source/Detach/Hide in [⋮]
- [ ] Manual: drag handle still works with ColumnSortable
- [ ] Manual: viewer role sees no toolbar
- [ ] No regressions in inline editing (label, value)
