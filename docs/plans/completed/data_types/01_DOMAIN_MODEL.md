# Phase 1 — Table Block Domain Model

> **Status:** Pending
> **Depends on:** None (foundation phase)
> **Next:** [Phase 2 — Table Block UI](02_TABLE_BLOCK_UI.md)

> **Problem:** No structured data type exists in the system. Designers must create individual flat blocks for every attribute.
>
> **Goal:** Table blocks exist in the database with columns, rows, and cells. Full CRUD. No UI yet.
>
> **Principle:** Pure domain logic. No LiveView, no JS, no components. Everything testable with `DataCase`.

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

## Context

### Current sheet model

```
Sheet (shortcut: "nameless_one")
├── Block "str" (number)           → nameless_one.str
├── Block "wis" (number)           → nameless_one.wis
├── Block "health" (number)        → nameless_one.health
├── Block "quest_started" (boolean)→ nameless_one.quest_started
└── ... all flat, no grouping
```

### Problems with flat blocks for structured data

1. **No structure** — stats, quest flags, and misc variables are all mixed together
2. **No shared schema** — 50 characters each need the same 6 stat blocks created manually
3. **No enforcement** — nothing guarantees "Annah" has the same attributes as "Morte"
4. **Poor mental model** — designers think in terms of "character attributes" as a group, not individual variables

### What competitors do

- **articy:draft** — Templates define property groups. Entities inherit from templates. Properties are typed and grouped.
- **Notion** — Databases define columns (schema). Each page/row inherits the schema. Cells are typed per column.

### Existing Storyarn features to build on

- **Sheet inheritance** — sheets can inherit from parent sheets with default values per block
- **Block types** — number, text, select, boolean (already typed)
- **Variable references** — `sheet_shortcut.variable_name` (2-level path)
- **Expression System** — already implemented (04_EXPRESSION_SYSTEM), Lezer grammar supports arbitrary-depth paths

---

## Design Decisions

### 1. Multi-column tables

Each table has typed columns. Even the simplest use case (stat list) benefits from at least two columns: a variable column (`value`) and a constant column (`description` — designer reference explaining what each attribute does in the game).

Each column has:
- A **type** (number, text, boolean, select, multi_select, date — reuses existing block types; **`rich_text` is explicitly excluded** from column types — tables use plain text only)
- An **is_constant** flag — constant columns are designer-only reference data, invisible to the expression system

### 2. Variable reference paths (always 4 levels)

All table variable references use exactly 4 levels: `sheet.table.row.column`. No short-path, no default column — every reference is explicit and unambiguous.

- `nameless_one.attributes.strength.value` → `18`
- `nameless_one.attributes.strength.description` → **not a variable** (constant column)

Regular block variables remain 2 levels: `nameless_one.health`.

**DSL examples:**

```
nameless_one.attributes.wisdom.value >= 15
nameless_one.attributes.charisma.value += 1
```

### 3. Tables are blocks

A table is just another block type (`type: "table"`). It follows the same rules as every other block: it can appear in any sheet regardless of whether the sheet has children or a parent. Same `scope` / `inherited_from_block_id` / `detached` mechanics. No special-casing.

### 4. Row ordering is visual only

Rows have a `position` field for display order. Users can reorder via drag & drop. The expression system references rows by name, never by position.

### 5. DB model

The block with `type: "table"` owns its schema via two new tables:

- **`table_columns`** — `block_id`, `name`, `slug` (slugified from name, used as 4th path level), `type`, `is_constant`, `position`, `config` (JSONB — for select options, column width, etc.)
- **`table_rows`** — `block_id`, `name`, `slug` (slugified from name, used as 3rd path level), `position`, `cells` (JSONB map of `column_slug → value`)

The Block schema gains two associations: `has_many :table_columns` and `has_many :table_rows` (only meaningful when `type == "table"`).

### 6. Minimum table size

A table always has at least **1 data column + 1 data row**. Visually this means 2 columns (row name + data) × 2 rows (header + data):

```
| [row name]  | value  |    ← header row (column names = 4th path level)
| strength    | 10     |    ← first data row (row name = 3rd path level)
```

The first column is structural (row label) — always present, not a configurable data column. When a table is created, it initializes with 1 data column ("value", type `number`) + 1 data row ("Row 1").

### 7. Rename breakage (known limitation)

Renaming a table block, row, or column regenerates the slug and breaks existing expressions. The Variable Reference Tracker (Phase 7) detects staleness and offers repair. Same limitation as renaming regular block labels.

> **TODO (future):** Auto-rename variable references across all flows when a block/row/column is renamed. System-wide improvement, not table-specific. Planned separately.

---

## Key Files

| File                                                               | Action                                                         |
|--------------------------------------------------------------------|----------------------------------------------------------------|
| `priv/repo/migrations/TIMESTAMP_create_table_columns_and_rows.exs` | **New**                                                        |
| `lib/storyarn/sheets/table_column.ex`                              | **New** — Ecto schema                                          |
| `lib/storyarn/sheets/table_row.ex`                                 | **New** — Ecto schema                                          |
| `lib/storyarn/sheets/block.ex`                                     | Modified — add `"table"` to types, defaults, non-variable list |
| `lib/storyarn/sheets/table_crud.ex`                                | **New** — CRUD operations for table columns/rows/cells         |
| `lib/storyarn/sheets.ex`                                           | Modified — add defdelegate for table operations                |
| `test/storyarn/sheets/table_crud_test.exs`                         | **New**                                                        |
| `test/support/fixtures/sheets_fixtures.ex`                         | Modified — add table fixtures                                  |

---

## Task 1.1 — Migration + Ecto Schemas

Create the `table_columns` and `table_rows` database tables and their Ecto schemas.

**Migration:**

```sql
CREATE TABLE table_columns (
  id BIGSERIAL PRIMARY KEY,
  block_id BIGINT NOT NULL REFERENCES blocks(id) ON DELETE CASCADE,
  name VARCHAR NOT NULL,            -- display label (e.g., "Value", "Description")
  slug VARCHAR NOT NULL,            -- slugified name, used in variable paths (4th level)
  type VARCHAR NOT NULL DEFAULT 'number',
  is_constant BOOLEAN NOT NULL DEFAULT false,
  position INTEGER NOT NULL DEFAULT 0,
  config JSONB NOT NULL DEFAULT '{}',
  inserted_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

CREATE INDEX table_columns_block_id_idx ON table_columns(block_id);
CREATE INDEX table_columns_block_position_idx ON table_columns(block_id, position);
CREATE UNIQUE INDEX table_columns_block_slug_unique ON table_columns(block_id, slug);

CREATE TABLE table_rows (
  id BIGSERIAL PRIMARY KEY,
  block_id BIGINT NOT NULL REFERENCES blocks(id) ON DELETE CASCADE,
  name VARCHAR NOT NULL,            -- display label (e.g., "Strength", "Wisdom")
  slug VARCHAR NOT NULL,            -- slugified name, used in variable paths (3rd level)
  position INTEGER NOT NULL DEFAULT 0,
  cells JSONB NOT NULL DEFAULT '{}',  -- map of column_slug → value
  inserted_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

CREATE INDEX table_rows_block_id_idx ON table_rows(block_id);
CREATE INDEX table_rows_block_position_idx ON table_rows(block_id, position);
CREATE UNIQUE INDEX table_rows_block_slug_unique ON table_rows(block_id, slug);
```

**Ecto schemas:**

- `TableColumn` — `belongs_to :block`, fields: `name`, `slug`, `type`, `is_constant`, `position`, `config`
  - Reuses `Block.slugify/1` for slug generation
  - `type` validates against: `~w(number text boolean select multi_select date)` — **`rich_text` is explicitly excluded**
  - `create_changeset/2`, `update_changeset/2`, `position_changeset/2`

- `TableRow` — `belongs_to :block`, fields: `name`, `slug`, `position`, `cells`
  - Reuses `Block.slugify/1` for slug generation
  - `create_changeset/2`, `update_changeset/2`, `position_changeset/2`, `cells_changeset/2`

**Block schema changes (`block.ex`):**

Add associations (only used by table blocks):
```elixir
has_many :table_columns, Storyarn.Sheets.TableColumn, foreign_key: :block_id
has_many :table_rows, Storyarn.Sheets.TableRow, foreign_key: :block_id
```

**Tests:**
- Changeset validation (valid attrs, missing required fields, invalid type)
- Slug generation from name
- Unique constraint on `(block_id, slug)`
- Block preload: `Repo.preload(block, [:table_columns, :table_rows])` works

---

## Task 1.2 — Block Schema Extension

Add `"table"` as a recognized block type.

**Changes to `block.ex`:**

- Add `"table"` to `@block_types` list
- Add to `@default_configs`: `"table" => %{"label" => "Label", "collapsed" => false}`
- Add to `@default_values`: `"table" => %{}` — **note:** table data lives in `table_rows.cells`, not in `block.value`. The `%{}` default is just a placeholder to satisfy the schema; actual data is always read from `table_rows`.
- Add `"table"` to the non-variable types list (table blocks themselves are NOT variables — their cells are, via `list_project_variables`)

**Changes to `block_crud.ex`:**

- In `create_block/2`: when `type == "table"`, after inserting the block, auto-create:
  - 1 default column: `%{name: "Value", slug: "value", type: "number", is_constant: false, position: 0}`
  - 1 default row: `%{name: "Row 1", slug: "row_1", position: 0, cells: %{"value" => nil}}`
- In `delete_block/1`: cascade handled by DB `ON DELETE CASCADE` — no extra code needed

**Tests:**
- Creating a table block auto-creates 1 column + 1 row
- Table block is not listed as a variable type
- Default config and value are correct

---

## Task 1.3 — Table Column CRUD

New module `table_crud.ex` with column operations.

**Functions:**

```elixir
# Columns
list_columns(block_id)                          # ordered by position
get_column!(column_id)
create_column(block, attrs)                     # auto-slug, auto-position, add empty cell to all rows
update_column(column, attrs)                    # rename → re-slug, type change → reset cells
delete_column(column)                           # prevent if last column, remove cells from all rows
reorder_columns(block_id, [column_id])          # update positions
```

**Slug uniqueness:** `ensure_unique_variable_name/3` in `BlockCrud` is private — reimplement the same `_2`, `_3` deduplication pattern in `table_crud.ex` as a private function (e.g., `ensure_unique_slug/3`) scoped to the block's columns.

**Column rename → JSONB key migration (critical detail):**

When a column is renamed (slug changes from `old_slug` to `new_slug`), ALL rows for that block need their `cells` JSONB updated atomically. Use Ecto.Multi:

```elixir
# For each row in the block:
# 1. Read current cells map
# 2. Remove old_slug key, add new_slug key with the same value
# 3. Update the row
defp migrate_cells_key(block_id, old_slug, new_slug) do
  rows = Repo.all(from(r in TableRow, where: r.block_id == ^block_id))

  Multi.new()
  |> then(fn multi ->
    Enum.reduce(rows, multi, fn row, multi ->
      {value, rest} = Map.pop(row.cells, old_slug)
      new_cells = Map.put(rest, new_slug, value)
      Multi.update(multi, {:row, row.id}, TableRow.cells_changeset(row, %{cells: new_cells}))
    end)
  end)
  |> Repo.transaction()
end
```

**Type change:** When column type changes, iterate all rows and set `cells[column_slug]` to `nil` (type default applied at read time). Same batch pattern.

**Delete column:** Remove `column_slug` key from all rows' `cells` JSONB. Same batch pattern. Prevent deletion of the last column.

**Tests:**
- Create column → slug generated, cells added to existing rows
- Rename column → slug updated, cells JSONB key migrated in ALL rows (old key gone, new key present, value preserved)
- Change type → cells reset to nil for that column in all rows
- Delete column → cells key removed from all rows, last column protected
- Slug uniqueness enforced with `_2` suffix
- Rename with 100 rows → all rows updated atomically (transaction)

---

## Task 1.4 — Table Row CRUD

Row operations in the same `table_crud.ex` module.

**Functions:**

```elixir
# Rows
list_rows(block_id)                             # ordered by position
get_row!(row_id)
create_row(block, attrs)                        # auto-slug, auto-position, init cells for all columns
update_row(row, attrs)                          # rename → re-slug
delete_row(row)                                 # prevent if last row
reorder_rows(block_id, [row_id])                # update positions
update_cell(row, column_slug, value)            # update single cell value
update_cells(row, cells_map)                    # batch update multiple cells
```

**Row creation:** Initialize `cells` map with all current column slugs → `nil`.

**Slug uniqueness:** Same dedup pattern within the block's rows (row name uniqueness enforced with `_2`, `_3` deduplication, same as block `variable_name`).

**Tests:**
- Create row → slug generated, cells initialized for all columns
- Rename row → slug updated
- Delete row → last row protected
- Reorder rows → positions updated
- Update cell → single cell value changed
- Update cells → batch update works
- Slug uniqueness enforced

---

## Task 1.5 — Context Facade + Fixtures

Wire everything through `sheets.ex` and add test fixtures.

**`sheets.ex` additions:**

```elixir
# Table columns
defdelegate list_table_columns(block_id), to: TableCrud
defdelegate get_table_column!(id), to: TableCrud
defdelegate create_table_column(block, attrs), to: TableCrud
defdelegate update_table_column(column, attrs), to: TableCrud
defdelegate delete_table_column(column), to: TableCrud
defdelegate reorder_table_columns(block_id, ids), to: TableCrud

# Table rows
defdelegate list_table_rows(block_id), to: TableCrud
defdelegate get_table_row!(id), to: TableCrud
defdelegate create_table_row(block, attrs), to: TableCrud
defdelegate update_table_row(row, attrs), to: TableCrud
defdelegate delete_table_row(row), to: TableCrud
defdelegate reorder_table_rows(block_id, ids), to: TableCrud
defdelegate update_table_cell(row, column_slug, value), to: TableCrud
defdelegate update_table_cells(row, cells_map), to: TableCrud
```

**Fixtures (`sheets_fixtures.ex`):**

```elixir
def table_block_fixture(sheet, attrs \\ %{})
# Returns block preloaded with :table_columns and :table_rows
# Since create_block auto-creates 1 default column + 1 default row,
# the returned block already has these preloaded.

def table_column_fixture(block, attrs \\ %{})
# Creates an additional column on the block. Auto-adds cell key to all existing rows.

def table_row_fixture(block, attrs \\ %{})
# Creates an additional row on the block. Auto-initializes cells for all existing columns.
```

**Tests:**
- Integration test: create table block → add columns → add rows → update cells → verify full structure
- Verify cascade delete: delete block → columns and rows gone
- `table_block_fixture` returns block with preloaded default column and row

---

## Phase 1 — Post-phase Audit

```
□ Run `just quality` — all green
□ Security: parameterized queries only, no raw SQL with user input
□ Dead code: no unused CRUD functions
□ Duplication: slug logic reused from Block.slugify/1
□ SOLID: TableCrud is single-responsibility (table structure ops)
□ KISS: no abstractions beyond what's needed
□ YAGNI: no inheritance logic yet, no UI, no variable generation
```

---

[Phase 2 — Table Block UI →](02_TABLE_BLOCK_UI.md)
