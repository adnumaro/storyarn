# Phase 6 — Table Block Inheritance

> **Status:** Pending
> **Depends on:** [Phase 1 — Domain Model](./01_DOMAIN_MODEL.md) + [Phase 3 — Column & Row Management](./03_COLUMN_ROW_MANAGEMENT.md)
> **Next:** [Phase 4 — Variable Generation](./04_VARIABLE_GENERATION.md)

> **Problem:** Tables can't be shared via the sheet inheritance system. A "Character Template" parent can't define an "attributes" table inherited by all character sheets.
>
> **Goal:** Table blocks with `scope: "children"` propagate to descendants. Schema locked in children, values overridable, whole-table detach.
>
> **Principle:** Follows existing inheritance patterns in `property_inheritance.ex`. No new concepts.

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

### Inheritance behavior

When a parent sheet has a table with `scope: "children"`:

| Aspect                        | Behavior                                                                                                                                           |
|-------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------|
| **Columns**                   | Inherited as-is. Children cannot add, delete, or modify columns.                                                                                   |
| **Rows**                      | Inherited with parent values as defaults. Children can override cell values but cannot add or delete rows.                                         |
| **Parent adds column/row**    | Auto-propagated to all non-detached children. New cells use type defaults.                                                                         |
| **Parent deletes column/row** | Cascade delete to non-detached children. Cell data lost.                                                                                           |
| **Detach**                    | Unlocks the table entirely — child gains full control over columns and rows. Whole-table only (no per-row detach).                                 |
| **Constant columns**          | Also overrideable by children (they are reference data, not variables). Explicitly: ALL cell values are overrideable, regardless of `is_constant`. |

---

## Key Files

| File                                                           | Action                                           |
|----------------------------------------------------------------|--------------------------------------------------|
| `lib/storyarn/sheets/property_inheritance.ex`                  | Modified — handle table block inheritance        |
| `lib/storyarn/sheets/table_crud.ex`                            | Modified — add column/row sync functions         |
| `lib/storyarn/sheets/block_crud.ex`                            | Modified — table-aware create/delete inheritance |
| `lib/storyarn_web/components/block_components/table_blocks.ex` | Modified — locked state for inherited tables     |
| `test/storyarn/sheets/table_inheritance_test.exs`              | **New**                                          |

---

## Mockup — Inherited Table (Locked State)

When a table is inherited via `scope: "children"` and NOT detached.

```
┌── border-l-2 border-info/30 (inherited indicator) ───────────────────────┐
│                                                                          │
│  ↗ INHERITED FROM Character Template (1)                           [⋮]   │
│    ↑ text-info, link to parent sheet                                     │
│                                                                          │
│  ┌─ label ──────────────────────────────────────────────────────────┐    │
│  │  Attributes                                                      │    │
│  └──────────────────────────────────────────────────────────────────┘    │
│                                                                          │
│  ┌─ table container ────────────────────────────────────────────────┐    │
│  │                                                                  │    │
│  │  ┌─ HEADER ROW ─── NO [+] button ────────────────────────────┐   │    │
│  │  │              │ value          │ description               │   │    │
│  │  │  (row label) │ (no ▾ dropdown)│ (no ▾ dropdown)           │   │    │
│  │  │  (no click)  │ ← locked      │ ← locked                   │   │    │
│  │  └──────────────┴────────────────┴───────────────────────────┘   │    │
│  │                                                                  │    │
│  │  ┌─ DATA ROW 1 ── NO drag handle, NO rename ─────────────────┐   │    │
│  │  │    strength   │ [    18     ]│ [Physical power         ]  │   │    │
│  │  │    ↑ static   │ ↑ EDITABLE!  │ ↑ EDITABLE!                │   │    │
│  │  │    text only  │ cell values  │ (even constant cols are    │   │    │
│  │  │    (can't     │ can be       │  overrideable by children) │   │    │
│  │  │     rename)   │ overridden   │                            │   │    │
│  │  └───────────────┴──────────────┴────────────────────────────┘   │    │
│  │                                                                  │    │
│  │  ┌─ DATA ROW 2 ──────────────────────────────────────────────┐   │    │
│  │  │    wisdom     │ [    15     ]│ [Mental acuity          ]  │   │    │
│  │  └───────────────┴──────────────┴────────────────────────────┘   │    │
│  │                                                                  │    │
│  │  NO [+ New] button ← can't add rows                              │    │
│  │                                                                  │    │
│  └──────────────────────────────────────────────────────────────────┘    │
│                                                                          │
│  Context menu: [Go to source] [Detach] (no Configure, no Delete)         │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

**Locked elements:** No `[+]` column button, no column dropdowns, no `[+ New]` row, no row drag handles, no row rename, no row context menu.

**Editable elements:** ALL cell input values — children can override the parent's defaults, including constant columns.

**Context menu:** Only "Go to source" (link to parent sheet) and "Detach". No "Configure", no "Delete".

---

## Task 6.1 — Inherit Table Structure on Child Sheet Creation

When a child sheet inherits a table block, also copy its columns and rows.

**`property_inheritance.ex` change in `create_inherited_instances/2`:**

After creating the inherited block instance, if `block.type == "table"`:
1. Copy all `table_columns` from parent block → new block (same attrs except `block_id`). Use `Repo.insert_all` with `returning: [:id, :block_id, :slug]` for efficiency.
2. Copy all `table_rows` from parent block → new block (same attrs except `block_id`, cells copied as defaults). Use `Repo.insert_all` with `returning: [:id, :block_id, :slug]` for efficiency.

**`inherit_blocks_for_new_sheet/1` and `propagate_to_descendants/2`:** Already delegate to `create_inherited_instances` — no changes needed.

**Tests:**
- Create parent table with 3 columns + 5 rows → create child sheet → child has inherited table with same 3 columns + 5 rows
- Cell values copied from parent as defaults
- Column slugs and row slugs identical

---

## Task 6.2 — Sync Schema Changes to Children

When a parent modifies table structure, propagate to non-detached children.

**New functions in `table_crud.ex`:**

```elixir
def sync_column_to_children(parent_column, action)  # action: :create, :update, :delete
def sync_row_to_children(parent_row, action)         # action: :create, :update, :delete
```

**Column sync:**
- `:create` → add column to all inherited table instances, add cell key to all rows
- `:update` → update column in all inherited instances (rename, type change, constant toggle). Type change → reset cells
- `:delete` → delete column from all inherited instances, remove cell key from all rows

**Row sync:**
- `:create` → add row to all inherited table instances
- `:update` → update row metadata (name, slug) in inherited instances. Cell values NOT overwritten (children may have overridden them)
- `:delete` → delete row from all inherited instances

**Integration with existing `sync_definition_change/1`:**

In `block_crud.ex`, when `update_block/2` is called on a table block with `scope: "children"`, after the existing sync, also sync table-level changes (if label changed → slug changed → all children's table_columns/rows reference updated).

**Tests:**
- Parent adds column → children gain column
- Parent deletes column → children lose column + cells
- Parent adds row → children gain row with default cells
- Parent deletes row → children lose row
- Parent renames column → children's column renamed, cell keys migrated
- Parent changes column type → children's cells reset
- Detached children unaffected by all above

---

## Task 6.3 — Detach/Reattach for Tables

Whole-table detach unlocks everything for the child.

**`property_inheritance.ex` changes:**

`detach_block/1`: When block type is "table", no extra work needed — the existing `detached: true` flag is enough. Children's table_columns and table_rows become independent (create/update/delete no longer check `inherited_from_block_id`).

`reattach_block/1`: When block type is "table":
1. Set `detached: false`
2. Delete all child's table_columns and table_rows
3. Re-copy from parent block (full reset to parent's schema + values)

**Tests:**
- Detach → child can add/delete columns and rows freely
- Reattach → child's custom columns/rows replaced by parent's current state
- Parent changes after detach → child unaffected

---

## Task 6.4 — UI: Locked State for Inherited Tables

Inherited (non-detached) tables show locked UI. See Inherited Table mockup above.

**`table_blocks.ex` changes:**

When `inherited_from_block_id != nil && !detached`:
- No "+" column button
- No column header dropdown (can't rename/delete/change type)
- No "+ New" row button
- No row delete/rename
- No row reorder
- Cells ARE editable (ALL values overridable — including constant columns)
- Visual indicator: `border-l-2 border-info/30` + "Inherited from [parent]" label with link

**Context menu for inherited tables:** Only "Go to source" (navigates to parent sheet) and "Detach". No "Configure", no "Delete".

**Tests:**
- Inherited table renders without management controls
- Cells remain editable (including constant column cells)
- Detached table shows full controls
- Context menu only shows "Go to source" and "Detach"

---

## Phase 6 — Post-phase Audit

```
□ Run `just quality` — all green
□ Security: inherited block operations verify parent-child relationship
□ Dead code: no unused sync functions
□ Duplication: sync_column_to_children/sync_row_to_children share iteration pattern
□ Potential bugs: reattach race condition if parent changed during reattach — acceptable (atomic transaction)
□ SOLID: inheritance logic in property_inheritance.ex, sync in table_crud.ex
□ KISS: reattach = full reset, not incremental diff
□ YAGNI: no per-row detach, no per-column detach — whole table only
```

---

[← Phase 3 — Column & Row Management](./03_COLUMN_ROW_MANAGEMENT.md) | [Phase 4 — Variable Generation →](./04_VARIABLE_GENERATION.md)
