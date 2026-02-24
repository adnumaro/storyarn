# Phase 2 — Table Block UI: Rendering + Cell Editing

> **Status:** Pending
> **Depends on:** [Phase 1 — Domain Model](01_DOMAIN_MODEL.md)
> **Next:** [Phase 3 — Column & Row Management](03_COLUMN_ROW_MANAGEMENT.md)

> **Problem:** Table blocks exist in the database but are invisible in the sheet editor.
>
> **Goal:** Tables render inline as grids. Users can view and edit cell values. Collapse/expand works. Tables participate in block layout (drag among blocks, full-width).
>
> **Principle:** UI only. No expression system changes, no inheritance changes.

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

### Inline collapsible UI, expanded by default

The table renders as a grid directly within the sheet editor. Starts expanded. The user can collapse it to a summary line: `[table icon] attributes (6 rows, 2 columns)`. No separate modal or panel.

### Cell editing

- **Always-visible inputs** — each cell renders as a permanent input matching the column type (text field, number input, select dropdown, checkbox). No click-to-edit mode. Consistent with how regular blocks work.
- **Empty/null cells allowed** — evaluator uses the column type's default (0 for number, "" for text, false for boolean, nil for select).

### Visual design

| Aspect               | Style                                                     |
|----------------------|-----------------------------------------------------------|
| **Header row**       | Subtle background (`bg-base-200`), column names as labels |
| **Row label column** | `font-medium`, sticky on horizontal scroll                |
| **Row backgrounds**  | Alternating for legibility (even rows `bg-base-200/30`)   |
| **Borders**          | Thin borders between cells (`border-base-300`)            |
| **Collapsed state**  | Table icon + label + `(N rows, N columns)`                |

### Table in block layout

- Tables can be **reordered among other blocks** via drag & drop (drag handle in table header).
- Tables are **always full-width** — cannot be placed inside column groups.
- **No conflict** between block drag (table header) and row drag (table body) — separate Sortable groups.

---

## Key Files

| File                                                               | Action                                          |
|--------------------------------------------------------------------|-------------------------------------------------|
| `lib/storyarn_web/components/block_components/table_blocks.ex`     | **New** — table block component                 |
| `lib/storyarn_web/components/block_components.ex`                  | Modified — add `"table"` dispatch               |
| `lib/storyarn_web/live/sheet_live/components/content_tab.ex`       | Modified — load table data, handle table events |
| `lib/storyarn_web/live/sheet_live/handlers/block_crud_handlers.ex` | Modified — table cell update events             |
| `priv/gettext/en/LC_MESSAGES/sheets.po`                            | Modified — table-related strings                |
| `priv/gettext/es/LC_MESSAGES/sheets.po`                            | Modified — translations                         |

---

## Mockup — Table Block: Expanded Edit Mode

The primary state. Shows all columns, rows, inline inputs, and management controls.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ [::] ← drag-handle (block reorder, grip-vertical size-4)                    │
│                                                                     [⋮] ←── context menu
│  ┌─ label: text-sm text-base-content/70 mb-1 ───────────────────────────┐   │
│  │  Attributes                                                          │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─ table container: border border-base-300 rounded-lg overflow-x-auto ─┐   │
│  │                                                                      │   │
│  │  ┌─ HEADER ROW: bg-base-200 border-b border-base-300 ──────────┬───┐ │   │
│  │  │              │ value ▾        │ description ▾   │ max ▾     │[+]│ │   │
│  │  │  (row label) │ ← click opens  │ ← click opens   │ ← click   │   │ │   │
│  │  │  sticky      │   dropdown     │   dropdown      │  dropdown │   │ │   │
│  │  └──────────────┴────────────────┴─────────────────┴───────────┴───┘ │   │
│  │                                                                      │   │
│  │  ┌─ DATA ROW 1: border-b border-base-300 ──────────────────────┐     │   │
│  │  │ [::] strength │ [    18     ] │ Physical power  │ [   20   ] │    │   │
│  │  │  ↑drag handle │ ↑number input │ ↑text input     │ ↑number   │     │   │
│  │  │  ↑row label   │  phx-blur     │  phx-blur       │  phx-blur │     │   │
│  │  │  click=rename │               │ (is_constant:   │           │     │   │
│  │  │               │               │  editable but   │           │     │   │
│  │  │               │               │  not a variable)│           │     │   │
│  │  └───────────────┴───────────────┴─────────────────┴───────────┘     │   │
│  │                                                                      │   │
│  │  ┌─ DATA ROW 2: bg-base-200/30 (alternating) ──────────────────┐     │   │
│  │  │ [::] wisdom   │ [    15     ] │ Mental acuity   │ [   25  ] │     │   │
│  │  └───────────────┴───────────────┴─────────────────┴───────────┘     │   │
│  │                                                                      │   │
│  │  ┌─ DATA ROW 3 ────────────────────────────────────────────────┐     │   │
│  │  │ [::] charisma │ [    12     ] │ Social influence │ [   20 ] │     │   │
│  │  └───────────────┴───────────────┴──────────────────┴──────────┘     │   │
│  │                                                                      │   │
│  │  ┌─ ADD ROW: text-base-content/50 hover:text-base-content ────┐      │   │
│  │  │  [+] + New                                                  │     │   │
│  │  └─────────────────────────────────────────────────────────────┘     │   │
│  │                                                                      │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Key elements:**
- Row label column is **sticky** on horizontal scroll (`sticky left-0 z-10 bg-base-100`)
- Each row has a **drag handle** (`[::] grip-vertical`) for row reorder (separate Sortable group from block reorder)
- **Row label** is clickable → inline rename input (phx-blur saves, slugify auto-generates)
- The `[+]` in the header row adds a new column
- The `[+ New]` at the bottom adds a new row
- **Alternating row backgrounds:** even rows `bg-base-200/30`

---

## Mockup — Table Block: Read-Only Mode (can_edit: false)

When the user has viewer role, no inputs, no management controls.

```
┌────────────────────────────────────────────────────────────────────────┐
│  ┌─ label ─────────────────────────────────────────────────────────┐   │
│  │  Attributes                                                     │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                        │
│  ┌─ table container: border border-base-300 rounded-lg ─────────────┐  │
│  │                                                                  │  │
│  │  ┌─ HEADER ROW: bg-base-200 ────────────────────────────────┐    │  │
│  │  │              │ value          │ description   │ max      │    │  │
│  │  └──────────────┴────────────────┴───────────────┴──────────┘    │  │
│  │                                                                  │  │
│  │  ┌─ DATA ROW 1 ─────────────────────────────────────────────┐    │  │
│  │  │    strength   │ 18             │ Physical power │ 20     │    │  │
│  │  │               │ ↑ plain text   │ ↑ plain text   │        │    │  │
│  │  └───────────────┴────────────────┴────────────────┴────────┘    │  │
│  │                                                                  │  │
│  │  ┌─ DATA ROW 2: bg-base-200/30 ─────────────────────────────┐    │  │
│  │  │    wisdom     │ 15             │ Mental acuity  │ 25     │    │  │
│  │  └───────────────┴────────────────┴────────────────┴────────┘    │  │
│  │                                                                  │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                                                        │
│  NO drag handle, NO context menu, NO [+] buttons, NO [+ New]           │
│  NO column ▾ dropdowns, NO row drag handles                            │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

**Key:** All cell values displayed as plain text (`<span>` not `<input>`). Empty/nil cells show `—` in `text-base-content/40`. Boolean cells show badge (same as read-only boolean block).

---

## Mockup — Cell Inputs by Column Type

Each column type renders a specific always-visible input inside the cell.

```
Column type: number
┌─────────────────┐
│ [    18     ]   │  ← input input-bordered input-sm w-full
│                 │    type="number", phx-blur="update_table_cell"
└─────────────────┘

Column type: text
┌─────────────────┐
│ [Physical power]│  ← input input-bordered input-sm w-full
│                 │    type="text", phx-blur="update_table_cell"
└─────────────────┘

Column type: boolean
┌─────────────────┐
│    [✓]          │  ← checkbox checkbox-sm checkbox-primary
│                 │    phx-click="update_table_cell"
└─────────────────┘

Column type: select
┌─────────────────┐
│ [Warrior    ▾]  │  ← select select-bordered select-sm w-full
│                 │    options from column.config["options"]
└─────────────────┘

Column type: multi_select
┌─────────────────┐
│ [Fire ✕][Ice ✕] │  ← badge badge-sm badge-primary
│ [Add...      ]  │    + input for adding
└─────────────────┘

Column type: date
┌─────────────────┐
│ [2025-02-01  ]  │  ← input input-bordered input-sm w-full
│                 │    type="date"
└─────────────────┘
```

**CSS pattern for all cell inputs:** `input-sm` (smaller than regular block inputs since cells are compact).

---

## Mockup — Collapsed State

The table collapses to a single summary line.

```
┌──────────────────────────────────────────────────────────────────┐
│ [::] ← drag handle                                       [⋮]     │
│                                                                  │
│  ┌─ collapsed line: flex items-center gap-2 cursor-pointer ──┐   │
│  │                                                           │   │
│  │  [⊞] Attributes (6 rows, 3 columns)           [▸]         │   │
│  │   ↑                ↑                            ↑         │   │
│  │   table-2 icon     label + summary count        chevron   │   │
│  │   size-4           text-sm                      -right    │   │
│  │   text-base-       text-base-content/70         size-4    │   │
│  │   content/50                                              │   │
│  │                                                           │   │
│  │  Click anywhere → expands to full table                   │   │
│  │                                                           │   │
│  └───────────────────────────────────────────────────────────┘   │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

**Expanded header** (when table is expanded, toggle to collapse):

```
┌─ label + collapse toggle ────────────────────────────────────────┐
│  Attributes                                            [▾]       │
│   ↑ label                                              ↑         │
│                                                   chevron-down   │
│                                                   click=collapse │
└──────────────────────────────────────────────────────────────────┘
```

---

## Mockup — Add Block Menu (with Table Option)

The existing block type menu gets a new entry.

```
┌────────────────────────────────────────┐
│  SCOPE                                 │
│  ─────────────────────────────────     │
│  (○) This sheet only                   │
│  (◉) This sheet and all children       │
│                                        │
│  BASIC BLOCKS                          │
│  ─────────────────────────────────     │
│  [T]   Text                            │
│  [T]   Rich Text                       │
│  [#]   Number                          │
│  [▾]   Select                          │
│  [☑]   Multi Select                    │
│  [📅]  Date                            │
│  [⊙]   Boolean                         │
│  [🔗]  Reference                       │
│                                        │
│  STRUCTURED DATA                ← NEW  │
│  ─────────────────────────────────     │
│  [⊞]   Table                   ← NEW   │
│                                        │
│  LAYOUT                                │
│  ─────────────────────────────────     │
│  [─]   Divider                         │
│                                        │
│  ─────────────────────────────────     │
│  Cancel                                │
└────────────────────────────────────────┘
```

**Icon:** `table-2` from Lucide (matches the collapsed state icon).

---

## Mockup — Horizontal Scroll with Sticky Row Labels

When a table has many columns and overflows horizontally.

```
┌─ table container: overflow-x-auto ───────────────────────────────────┐
│                                                                      │
│  ┌─ sticky ──┐ ┌─ scrollable area ──────────────────────────── ▸     │
│  │           │ │                                                     │
│  │ (labels)  │ │ value  │ desc.  │ max  │ min  │ mod  │ xp  │ ...    │
│  │───────────│ │────────┼────────┼──────┼──────┼──────┼─────┼────    │
│  │ strength  │ │  18    │ Phys.. │  20  │  3   │  +2  │ 500 │ ...    │
│  │ wisdom    │ │  15    │ Ment.. │  25  │  3   │  +1  │ 300 │ ...    │
│  │ charisma  │ │  12    │ Soci.. │  20  │  3   │   0  │ 200 │ ...    │
│  │           │ │                                                     │
│  └───────────┘ └──────────────────────────────────────────── ▸       │
│                                                                      │
│  ← horizontal scrollbar →                                            │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

**CSS:** Row label column: `sticky left-0 z-10 bg-base-100` (stays visible while scrolling).

---

## Task 2.1 — Table Block Component (Read-Only Rendering)

Create `table_blocks.ex` that renders the table grid.

**Component: `table_block/1`**

Receives: `block`, `columns` (list), `rows` (list), `can_edit` (boolean), `target` (LiveComponent pid)

Renders:
- **Collapsed state:** Table icon + `config["label"]` + `(N rows, N columns)` — click to expand
- **Expanded state:**
  - Header row: row label column header ("") + column names with `bg-base-200`
  - Data rows: row name (sticky `sticky left-0 z-10 bg-base-100`, `font-medium`) + cell values per column
  - Alternating row backgrounds (even rows `bg-base-200/30`)
  - Thin borders (`border-base-300`)

Cell rendering by column type (read-only display — used when `can_edit: false`):
- `number` → plain text value or "0"
- `text` → plain text value or `—` (`text-base-content/40`)
- `boolean` → badge: `badge-success` "Yes" / `badge-error` "No" / `badge-neutral` "—"
- `select` → plain text of selected option label or `—`
- `multi_select` → `badge badge-sm badge-primary` tags or `—`
- `date` → formatted date string or `—`

When `can_edit: true`, each cell renders the always-visible input (see Cell Inputs mockup above).

**Collapse/expand in expanded mode:** The label row includes a chevron-down icon (`size-4`) on the right that toggles collapse. When collapsed, the entire table body is hidden and the summary line is shown instead (see Collapsed State mockup above).

**Tests:**
- Component renders with correct number of rows and columns
- Collapsed state shows summary text with correct counts
- Expanded state shows collapse toggle button
- Column types render appropriate display values (read-only mode)
- Column types render appropriate inputs (edit mode)

---

## Task 2.2 — Block Component Dispatch + Data Loading + Add Block Menu

Wire the table block into the sheet editor.

**`block_components.ex`:**
- Add `"table"` case to `block_component/1` dispatcher
- Add optional assign `table_data` (default `%{}`)
- Inside table case: extract `columns = table_data[block.id][:columns] || []` and `rows = table_data[block.id][:rows] || []`

**`content_tab.ex`:**
- In `update/2`: batch-load table data for ALL table blocks in the sheet in a single pass to avoid N+1:
  ```elixir
  table_block_ids = blocks |> Enum.filter(&(&1.type == "table")) |> Enum.map(& &1.id)
  table_data = if table_block_ids != [],
    do: TableCrud.batch_load_table_data(table_block_ids),
    else: %{}
  ```
  Returns: `%{block_id => %{columns: [...], rows: [...]}}`
- Pass `table_data={@table_data}` to `block_component`
- **`table_data` threading path:** `content_tab` → `blocks_container` → `block_component` → `table_block`. Ensure each intermediate component passes `table_data` through as an assign.
- Tables are always `:full_width` in layout — add guard in `group_blocks_for_layout/1` to never place table blocks in column groups

**`table_crud.ex` addition:**
```elixir
def batch_load_table_data(block_ids) do
  columns = Repo.all(from(c in TableColumn, where: c.block_id in ^block_ids, order_by: [asc: c.position]))
  rows = Repo.all(from(r in TableRow, where: r.block_id in ^block_ids, order_by: [asc: r.position]))

  block_ids
  |> Enum.map(fn id ->
    {id, %{
      columns: Enum.filter(columns, &(&1.block_id == id)),
      rows: Enum.filter(rows, &(&1.block_id == id))
    }}
  end)
  |> Map.new()
end
```

**Add block menu (`block_menu.ex`):**
- Add "STRUCTURED DATA" section with "Table" option to the block type menu (see Add Block Menu mockup above)
- Icon: `table-2` from Lucide
- Creates block with `type: "table"` via existing `add_block` event

**Authorization:** All table mutation events must use `with_authorization/2`, not manual `can_edit` checks.

**Tests:**
- Sheet with a table block renders the table
- Table block appears as full-width (not in column groups)
- Add block menu shows "Table" option under "Structured Data"
- Clicking "Table" creates a table block with default column + row

---

## Task 2.3 — Cell Editing (Inline Inputs)

Make cells editable with always-visible inputs.

**Events in `content_tab.ex`:**

```elixir
handle_event("update_table_cell", %{"row_id" => row_id, "column_slug" => slug, "value" => value}, socket)
```

**Authorization:** All table mutation events must use `with_authorization/2`, not manual `can_edit` checks.

**Cell input components** (in `table_blocks.ex`):
- `number` → `<input type="number" phx-blur="update_table_cell" ...>`
- `text` → `<input type="text" phx-blur="update_table_cell" ...>`
- `boolean` → `<input type="checkbox" phx-click="update_table_cell" ...>`
- `select` → `<select phx-change="update_table_cell" ...>` with column config options
- `multi_select` → multi-select component (reuse pattern from `SelectBlocks`)
- `date` → `<input type="date" phx-blur="update_table_cell" ...>`

**Read-only for inherited tables:** If block has `inherited_from_block_id` and is not `detached`, cells are editable (values overridable) but structure is locked.

**Tests:**
- Updating a number cell persists the value
- Updating a boolean cell toggles the value
- Select cell shows column-level options

---

## Task 2.4 — Collapse/Expand + Block Layout Integration

Collapse/expand toggle and block ordering.

**Collapse state:** Stored in `block.config["collapsed"]`. Toggle via:

```elixir
handle_event("toggle_table_collapse", %{"block_id" => block_id}, socket)
```

Updates `block.config["collapsed"]` via `BlockCrud.update_block/2` (note: `Sheets.update_block_config/2` does not exist — use the standard `update_block` path).

**Block layout:**
- Table blocks get a drag handle in the table header (same Sortable group as other blocks)
- Guard in `create_column_group`: reject table blocks from column groups
- If a table block is somehow in a column group (shouldn't happen), dissolve it

**Tests:**
- Toggle collapse persists state
- Table block cannot be added to column groups
- Table block can be reordered among other blocks

---

## Task 2.5 — Gettext (Phase 2)

Add all user-facing strings from this phase.

**English (`sheets.po`):**
- `"%{count} rows, %{count_columns} columns"` — collapsed summary
- `"Value"` — default column name
- `"Row %{n}"` — default row name

**Spanish (`sheets.po`):** Corresponding translations.

Run `mix gettext.extract --merge`.

---

## Phase 2 — Post-phase Audit

```
□ Run `just quality` — all green
□ Security: cell values sanitized before display (Phoenix auto-escapes in HEEx)
□ Dead code: no unused component functions
□ Componentization: table_blocks.ex is self-contained, no logic leaking into content_tab
□ Duplication: cell rendering per type uses shared helper, not copy-paste per column
□ Potential bugs: nil cells handled gracefully (display default, not crash)
□ SOLID: table_blocks.ex renders, content_tab.ex orchestrates — separation clean
□ KISS: no fancy state management, just server round-trips
□ YAGNI: no column management UI yet, no row add/delete yet
```

---

[← Phase 1 — Domain Model](01_DOMAIN_MODEL.md) | [Phase 3 — Column & Row Management →](03_COLUMN_ROW_MANAGEMENT.md)
