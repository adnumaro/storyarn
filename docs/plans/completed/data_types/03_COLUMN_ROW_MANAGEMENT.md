# Phase 3 — Column & Row Management

> **Status:** Pending **Depends on:** [Phase 2 — Table Block UI](02_TABLE_BLOCK_UI.md) **Next:** [Phase 6 — Inheritance](06_INHERITANCE.md)

> **Problem:** Users can see tables but cannot modify their structure — no adding columns, rows, or changing types.
> 
> **Goal:** Full Notion-style column and row management: add, delete, rename, reorder, type change, select/multi_select options management.
> 
> **Principle:** Interactive UI. Uses existing confirm_modal pattern. No expression system changes.

---

## AI Implementation Protocol

> **MANDATORY:** Follow this protocol for EVERY task. Do not skip steps.

### Per-Task Checklist

```
□ Read all files the task touches BEFORE writing code
□ Write tests FIRST or alongside implementation (not after)
□ Run `just quality` after completing the task
□ Verify: no warnings, no test failures, no credo issues, no biome issues
□ If any check fails: fix before moving to the next task
```

### Per-Phase Audit

After completing ALL tasks in a phase, run a full audit:

```
□ Security: no SQL injection, no unescaped user input, no mass assignment
□ Dead code: no unused functions, no unreachable branches, no leftover debug code
□ Bad practices: no God modules, no deep nesting, no magic strings
□ Componentization: components are focused, reusable, no monolith templates
□ Duplication: no copy-paste code, shared logic extracted
□ Potential bugs: nil handling, race conditions, missing error branches
□ SOLID: single responsibility, open for extension, dependency inversion via contexts
□ KISS: simplest solution that works, no premature abstractions
□ YAGNI: nothing built "for later", only what this phase needs
```

### Quality Command

```bash
just quality   # runs: biome check --write, mix credo --strict, mix test, vitest
```

---

## Design Specs for This Phase

### Column management (Notion-style)

Columns are managed entirely inline from the table header row. The block's config panel only shows block-level settings (label, scope, collapse state).

Action

How

**Add column**

"+" button at the end of the header row. Default: name "Column N", type `number`.

**Configure column**

Click column header → dropdown menu (rename, change type, toggle constant, delete).

**Delete column**

Column header dropdown → "Delete column". Confirmation if data exists. Last data column cannot be deleted.

**Change type**

Resets all cell values in that column to the new type's default. Confirmation before applying.

**Resize column**

Drag the border between column headers. Widths stored in column `config`.

**No column limit**

Horizontal scroll when columns exceed available width. Row label column stays sticky.

**Select/multi_select columns:** options defined at column level (in `config` JSONB), shared across all rows. Managed from the column header dropdown (see Mockup — Select/Multi-Select Options). Options stored as `[%{"value" => "warrior", "label" => "Warrior"}, ...]`.

### Row management

Action

How

**Add row**

"+ New" button at bottom of table. Default name "Row N", cell values set to column type defaults.

**Rename row**

Click the row label. Label is free-form, system auto-generates slug via `slugify`.

**Delete row**

Row context menu → delete. Last data row cannot be deleted.

**Reorder rows**

Drag handle on the row label cell. Same Sortable mechanic as blocks.

**No row limit**

Table grows vertically. User can collapse if too long.

**Row name uniqueness:** within the table, enforced with `_2`, `_3` deduplication (same as block `variable_name`).

---

## Key Files

File

Action

`lib/storyarn_web/components/block_components/table_blocks.ex`

Modified — column header dropdown, row context menu, add buttons

`lib/storyarn_web/live/sheet_live/components/content_tab.ex`

Modified — handle column/row management events

`lib/storyarn_web/live/sheet_live/handlers/block_crud_handlers.ex`

Modified — table-specific event handlers

`assets/js/hooks/table_row_sortable.js`

**New** — Sortable.js hook for row drag & drop

`assets/js/hooks/table_column_resize.js`

**New** — Column resize drag hook

`assets/js/hooks/index.js` (or wherever hooks are registered)

Modified — register new hooks

---

## Mockup — Column Header Dropdown

Triggered by clicking a column name in the header row.

```
                    ┌─── Column: "value" ────────────────────┐
                    │                                        │
  value ▾  ←click   │  ┌─ Rename ─────────────────────────┐  │
                    │  │  [value                        ] │  │
                    │  │   ↑ input, auto-focused,         │  │
                    │  │    select-all                    │  │
                    │  │                                  │  │
                    │  └──────────────────────────────────┘  │
                    │                                        │
                    │  ─── Type ─────────────────────────────│
                    │  ( ) Number    ← current (checked)     │
                    │  ( ) Text                              │
                    │  ( ) Boolean                           │
                    │  ( ) Select                            │
                    │  ( ) Multi Select                      │
                    │  ( ) Date                              │
                    │                                        │
                    │  ─── Options ──────────────────────────│
                    │  [ ] Constant   ← checkbox             │
                    │      text-xs text-base-content/50:     │
                    │      "Won't generate a variable"       │
                    │                                        │
                    │  ──────────────────────────────────────│
                    │  [🗑 Delete column]  ← text-error      │
                    │    (disabled if last column,           │
                    │     tooltip: "Cannot delete the        │
                    │     last column")                      │
                    │                                        │
                    └────────────────────────────────────────┘
```

**CSS:** `dropdown-content z-50 menu p-2 shadow-lg bg-base-200 rounded-box w-56`

**Type change behavior:**

1.  User clicks a different type radio button
2.  **Confirmation modal appears** (see Confirmation Modals mockup below)
3.  On confirm: all cell values in that column reset to nil
4.  On cancel: radio reverts to current type

**Delete column behavior:**

1.  If rows have data in that column → **Confirmation modal**
2.  If last column → button disabled, tooltip: "Cannot delete the last column"

---

## Mockup — Select/Multi-Select Column Options Management

When a column has type `select` or `multi_select`, the column header dropdown includes an options section.

```
Column header dropdown for a "select" type column:
┌─── Column: "class" ─────────────────────────────┐
│                                                 │
│  ┌─ Rename ───────────────────────────────────┐ │
│  │  [class                                 ]  │ │
│  └────────────────────────────────────────────┘ │
│                                                 │
│  ─── Type ───────────────────────────────────── │
│  ( ) Number                                     │
│  ( ) Text                                       │
│  (●) Select    ← current                        │
│  ( ) Multi Select                               │
│  ( ) Boolean                                    │
│  ( ) Date                                       │
│                                                 │
│  ─── Options ─────────────────────────────────  │
│                                                 │
│  [Warrior                              ] [✕]    │
│  [Mage                                 ] [✕]    │
│  [Thief                                ] [✕]    │
│  [+ Add option                         ]        │
│   ↑ input, phx-keydown=Enter to add             │
│                                                 │
│  ─── Settings ───────────────────────────────── │
│  [ ] Constant                                   │
│                                                 │
│  ───────────────────────────────────────────────│
│  [🗑 Delete column]                             │
│                                                 │
└─────────────────────────────────────────────────┘
```

**Options section** only visible when column type is `select` or `multi_select`. Options stored in `column.config["options"]` as `[%{"value" => "warrior", "label" => "Warrior"}, ...]`.

---

## Mockup — Row Rename (Inline)

Triggered by clicking the row label.

```
BEFORE (display mode):
┌───────────────┬─────────────┬──────────────┐
│ [::] strength │ [    18   ] │ Physical...  │
└───────────────┴─────────────┴──────────────┘

DURING (edit mode — click on "strength"):
┌───────────────────────┬─────────────┬──────────────┐
│ [::] [strength     ]  │ [    18   ] │ Physical...  │
│       ↑ input         │             │              │
│       input-bordered  │             │              │
│       input-sm        │             │              │
│       auto-focused    │             │              │
│       phx-blur=rename │             │              │
│       phx-keydown=    │             │              │
│        Enter=save     │             │              │
│        Escape=cancel  │             │              │
└───────────────────────┴─────────────┴──────────────┘

AFTER (slug generated):
  Name: "Strength" → slug: "strength"
  Name: "Max Health" → slug: "max_health"
```

---

## Mockup — Row Context Menu

Triggered by right-click or `[⋮]` button on the row (appears on hover).

```
┌───────────────┬─────────────┬──────────────┐
│ [::] strength │ [    18   ] │ Physical...  │ [⋮] ← on hover
└───────────────┴─────────────┴──────────────┘
                                                │
                                    ┌───────────┴──────────┐
                                    │                      │
                                    │  [✎] Rename          │
                                    │  ─────────────────── │
                                    │  [🗑] Delete row     │
                                    │   ↑ text-error       │
                                    │   (disabled if last  │
                                    │    row in table)     │
                                    │                      │
                                    └──────────────────────┘
```

**CSS:** Same dropdown pattern as block context menu: `dropdown-content z-50 menu p-2 shadow-lg bg-base-200 rounded-box w-44`

---

## Mockup — Confirmation Modals

### Change Column Type

```
┌──── Change column type ─────────────────────────┐
│                                            [✕]  │
│                                                 │
│  [⚠]  Change column type?                       │
│                                                 │
│  Changing "value" from Number to Text will      │
│  reset all cell values in this column to the    │
│  new type's default.                            │
│                                                 │
│  This action cannot be undone.                  │
│                                                 │
│                      [Cancel]  [Change type]    │
│                       ↑ghost    ↑btn-warning    │
└─────────────────────────────────────────────────┘
```

### Delete Column

```
┌──── Delete column ──────────────────────────────┐
│                                            [✕]  │
│                                                 │
│  [⚠]  Delete column "description"?              │
│                                                 │
│  This will remove the column and all its data   │
│  from every row. This action cannot be undone.  │
│                                                 │
│                      [Cancel]  [Delete]         │
│                       ↑ghost    ↑btn-error      │
└─────────────────────────────────────────────────┘
```

### Delete Row

```
┌──── Delete row ─────────────────────────────────┐
│                                            [✕]  │
│                                                 │
│  [⚠]  Delete row "strength"?                    │
│                                                 │
│  This will remove the row and all its cell      │
│  data. This action cannot be undone.            │
│                                                 │
│                      [Cancel]  [Delete]         │
│                       ↑ghost    ↑btn-error      │
└─────────────────────────────────────────────────┘
```

---

## Task 3.1 — Add Column + Add Row

Basic structural additions.

**Add column:** "+" button at the end of the header row. On click:

```elixir
handle_event("add_table_column", %{"block_id" => block_id}, socket)
```

Creates column with default name "Column N", type `number`, position at end. Adds empty cell to all rows.

**Add row:** "+ New" button at the bottom of the table. On click:

```elixir
handle_event("add_table_row", %{"block_id" => block_id}, socket)
```

Creates row with default name "Row N", position at end. Initializes cells for all columns.

**Authorization:** All table mutation events must use `with_authorization/2`, not manual `can_edit` checks.

**Tests:**

-   Add column → appears in header, cells added to existing rows
-   Add row → appears at bottom, cells initialized for all columns
-   Default naming: "Column 2", "Column 3", "Row 2", "Row 3"

---

## Task 3.2 — Column Header Dropdown (Rename, Type, Constant, Delete)

Click column header → dropdown menu with actions. See Column Header Dropdown mockup above.

**UI:** Dropdown component (reuse existing dropdown pattern from the codebase). Actions:

1.  **Rename** — inline text input replacing column name. On blur/enter: `update_table_column(column, %{name: new_name})`. Slug regenerated.
2.  **Change type** — radio buttons with type options. On select: confirmation modal ("This will reset all values in this column. Continue?"), then `update_table_column(column, %{type: new_type})`.
3.  **Toggle constant** — checkbox. `update_table_column(column, %{is_constant: !column.is_constant})`.
4.  **Delete** — confirmation modal if rows have data. `delete_table_column(column)`. Disabled if last column (tooltip: "Cannot delete the last column").

**Events:**

```elixir
handle_event("rename_table_column", %{"column_id" => id, "name" => name}, socket)
handle_event("change_table_column_type", %{"column_id" => id, "type" => type}, socket)
handle_event("toggle_table_column_constant", %{"column_id" => id}, socket)
handle_event("delete_table_column", %{"column_id" => id}, socket)
```

**Authorization:** All events must use `with_authorization/2`.

**Tests:**

-   Rename column → slug changes, cells key migrated
-   Change type → confirmation required, cells reset
-   Toggle constant → is_constant flipped
-   Delete column → removed, cells cleaned. Last column: error/no-op
-   Dropdown renders all actions

---

## Task 3.3 — Row Management (Rename, Delete, Reorder)

Row context menu and drag handle. See Row Rename and Row Context Menu mockups above.

**Row rename:** Click row label → inline input. Keyboard: Enter=save, Escape=cancel. On blur: `update_table_row(row, %{name: new_name})`.

**Row context menu** (right-click or `[⋮]` button on row label):

1.  **Rename** — focuses the row label inline input
2.  **Delete** — confirmation modal. `delete_table_row(row)`. Disabled if last row.

**Row reorder:** Drag handle on the row label cell. Uses Sortable.js — same library and pattern as `ColumnSortable` hook used for block reorder.

**Implementation:** The table body (`<tbody>`) needs a `phx-hook="TableRowSortable"` (new hook, thin wrapper around Sortable). Config:

-   `handle: ".row-drag-handle"` — only the grip-vertical icon on the row label triggers drag
-   `animation: 150`
-   `onEnd`: pushEvent `"reorder_table_rows"` with `{block_id, row_ids: [ordered ids]}`
-   `data-block-id={block.id}` on the tbody element

This is a SEPARATE Sortable group from the block-level ColumnSortable. They don't interfere because they're on different DOM elements (`#blocks-container` vs `<tbody>`).

**Events:**

```elixir
handle_event("rename_table_row", %{"row_id" => id, "name" => name}, socket)
handle_event("delete_table_row", %{"row_id" => id}, socket)
handle_event("reorder_table_rows", %{"block_id" => id, "row_ids" => ids}, socket)
```

**Tests:**

-   Rename row → slug changes
-   Delete row → removed. Last row: error/no-op
-   Reorder rows → positions updated correctly

---

## Task 3.4 — Column Resize

Drag column header borders to resize.

**Implementation:** Requires a JS hook `TableColumnResize` on the table header row.

**Hook behavior:**

1.  On mount: find all `<th>` elements, add a 4px-wide invisible resize handle (`<div class="absolute right-0 top-0 h-full w-1 cursor-col-resize">`) to the right edge of each
2.  On mousedown on a resize handle: track `startX` and `startWidth`
3.  On mousemove: calculate `newWidth = startWidth + (e.clientX - startX)`, apply `min-width` to the `<th>` via inline style, apply matching `min-width` to all `<td>` in that column index
4.  On mouseup: push event `"resize_table_column"` with `{column_id, width: newWidth}`
5.  Apply saved widths from `column.config["width"]` on mount

**Storage:** Width in `column.config["width"]` (integer, pixels). Default: no key = auto width (CSS handles it).

**Event:**

```elixir
handle_event("resize_table_column", %{"column_id" => id, "width" => width}, socket)
```

Updates `column.config["width"]` via `update_table_column`.

**New file:** `assets/js/hooks/table_column_resize.js`

**Tests:**

-   Resize persists width in config
-   Default width is auto (no config key)
-   Saved width applied on page load

---

## Task 3.5 — Select/Multi-Select Options Management

Manage options for `select` and `multi_select` columns from the column header dropdown. See Select/Multi-Select Options mockup above.

**UI:** When column type is `select` or `multi_select`, the dropdown shows an "Options" section:

-   List of current options with `[✕]` delete button each
-   `[+ Add option]` input at the bottom — phx-keydown=Enter to add

**Events:**

```elixir
handle_event("add_table_column_option", %{"column_id" => id, "label" => label}, socket)
handle_event("remove_table_column_option", %{"column_id" => id, "value" => value}, socket)
```

**Storage:** Options in `column.config["options"]` as `[%{"value" => "warrior", "label" => "Warrior"}, ...]`. The `value` is auto-slugified from the label.

**Behavior on type change away from select/multi_select:** Options are preserved in config (no data loss if user changes type and changes back). Cell values still reset per type change rules.

**Tests:**

-   Add option → appears in config
-   Remove option → removed from config
-   Options section hidden when column type is not select/multi_select
-   Select cell dropdown shows column-level options

---

## Task 3.6 — Gettext (Phase 3)

Add column/row management strings.

**English:**

-   `"Column %{n}"` — default column name
-   `"Delete column"`, `"Rename"`, `"Change type"`, `"Constant"`
-   `"Won't generate a variable"` — constant checkbox hint
-   `"Cannot delete the last column"` — disabled tooltip
-   `"This will reset all values in this column."`, `"Delete this column?"`, `"Delete this row?"`
-   `"+ New"` — add row button
-   `"+ Add option"` — add select option

**Spanish:** Corresponding translations.

---

## Phase 3 — Post-phase Audit

```
□ Run `just quality` — all green
□ Security: user authorization checked via with_authorization/2 before all mutations
□ Dead code: no unused event handlers
□ Componentization: dropdown is reusable, not inline HTML
□ Duplication: column type rendering shared between header dropdown and cell inputs
□ Potential bugs: concurrent edits (slug rename while another user types) — acceptable for now (single-user)
□ SOLID: handlers delegate to context, no business logic in LiveView
□ KISS: standard dropdown + confirm modal, no complex state machines
□ YAGNI: no undo, no column reorder (just resize), no bulk operations
```

---

[← Phase 2 — Table Block UI](02_TABLE_BLOCK_UI.md) | [Phase 6 — Inheritance →](06_INHERITANCE.md)