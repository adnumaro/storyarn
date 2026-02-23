# Performance N+1 Fixes (Tier 2 Audit Findings)

## Overview

Fix 5 critical N+1 query patterns identified in `.claude/audit/reports/perf-audit.md`.
Ordered from easiest/lowest-risk to most complex.

---

## Phase 1: C5 — `progress_by_language` single GROUP BY

**File:** `lib/storyarn/localization/reports.ex`
**Test:** `test/storyarn/localization/reports_test.exs`

### Current (N+1)
Loads all languages, then calls `status_counts(project_id, locale_code)` per language — one query per language.

### Fix
Single query with JOIN between `project_languages` and `localized_texts`, GROUP BY `locale_code, status`. Then pivot in Elixir.

```elixir
def progress_by_language(project_id) do
  languages =
    from(l in ProjectLanguage,
      where: l.project_id == ^project_id and l.is_source == false,
      order_by: [asc: l.position, asc: l.name]
    )
    |> Repo.all()

  # Single query: count texts per locale_code + status
  counts =
    from(t in LocalizedText,
      where: t.project_id == ^project_id,
      group_by: [t.locale_code, t.status],
      select: {t.locale_code, t.status, count(t.id)}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), fn {_locale, status, count} -> {status, count} end)
    |> Map.new(fn {locale, pairs} -> {locale, Map.new(pairs)} end)

  Enum.map(languages, fn lang ->
    stats = Map.get(counts, lang.locale_code, %{})
    total = stats |> Map.values() |> Enum.sum()
    final = Map.get(stats, "final", 0)

    %{
      locale_code: lang.locale_code,
      name: lang.name,
      total: total,
      final: final,
      percentage: if(total > 0, do: Float.round(final / total * 100, 1), else: 0.0)
    }
  end)
end
```

Delete `defp status_counts/2` (now unused).

- [ ] Replace `progress_by_language/1` with single-query version
- [ ] Delete `status_counts/2`
- [ ] Run existing tests: `mix test test/storyarn/localization/reports_test.exs`

---

## Phase 2: C4 — `list_sheets_tree` in-memory build

**File:** `lib/storyarn/sheets/sheet_queries.ex`
**Test:** `test/storyarn/sheets_test.exs`

### Current (O(N) queries)
`list_sheets_tree` loads root sheets, then `preload_children_recursive` fires one query per node to load children + avatar_asset.

### Fix
Copy FlowCrud pattern: single query for all non-deleted sheets with preload, then in-memory tree build with `Enum.group_by`.

```elixir
def list_sheets_tree(project_id) do
  all_sheets =
    from(s in Sheet,
      where: s.project_id == ^project_id and is_nil(s.deleted_at),
      order_by: [asc: s.position, asc: s.name],
      preload: [:avatar_asset]
    )
    |> Repo.all()

  build_tree(all_sheets, nil)
end

defp build_tree(all_sheets, root_parent_id) do
  grouped = Enum.group_by(all_sheets, & &1.parent_id)
  build_subtree(grouped, root_parent_id)
end

defp build_subtree(grouped, parent_id) do
  (Map.get(grouped, parent_id) || [])
  |> Enum.map(fn sheet ->
    %{sheet | children: build_subtree(grouped, sheet.id)}
  end)
end
```

Also update `get_sheet_with_descendants` to use the same pattern (filtered to subtree).

- [ ] Replace `list_sheets_tree/1` with single-query + in-memory build
- [ ] Update `get_sheet_with_descendants/2` to use same pattern
- [ ] Delete `preload_children_recursive/1`
- [ ] Run existing tests: `mix test test/storyarn/sheets_test.exs`

---

## Phase 3: C2 — Ancestor chain via recursive CTE

**Files:**
- `lib/storyarn/sheets/property_inheritance.ex` (`build_ancestor_list/1`)
- `lib/storyarn/sheets/sheet_queries.ex` (`build_ancestor_chain/2`)

### Current (O(depth) queries)
Both walk up the tree one `Repo.get` at a time.

### Fix
Shared recursive CTE that walks parent_id upward. Returns all ancestors in one query.

Add to `sheet_queries.ex`:
```elixir
@doc "Returns ancestors of a sheet (closest-first), excluding the sheet itself."
def list_ancestors(sheet_id) do
  # Recursive CTE: start from sheet, walk parent_id upward
  cte_query =
    Sheet
    |> where([s], s.id == ^sheet_id)
    |> select([s], %{id: s.id, parent_id: s.parent_id, depth: 0})
    |> union_all(^(
      from(s in Sheet,
        join: a in "ancestors_cte", on: s.id == a.parent_id,
        where: is_nil(s.deleted_at),
        select: %{id: s.id, parent_id: s.parent_id, depth: a.depth + 1}
      )
    ))

  ancestor_ids =
    {"ancestors_cte", Sheet}
    |> recursive_ctes(true)
    |> with_cte("ancestors_cte", as: ^cte_query)
    |> where([a], a.depth > 0)  # Exclude the sheet itself
    |> select([a], a.id)
    |> Repo.all()

  # Load full sheets in order (nearest ancestor first = highest depth)
  if ancestor_ids == [] do
    []
  else
    sheets_map =
      from(s in Sheet, where: s.id in ^ancestor_ids, preload: [:avatar_asset])
      |> Repo.all()
      |> Map.new(&{&1.id, &1})

    # Reconstruct order by walking parent_id from the original sheet
    build_ordered_ancestors(sheets_map, sheet_id)
  end
end
```

**Update `build_ancestor_chain`** (in SheetQueries) to use `list_ancestors` then reverse for root-first order.

**Update `build_ancestor_list`** (in PropertyInheritance) to call `SheetQueries.list_ancestors/1` (which returns nearest-first, matching current behavior).

- [ ] Add `list_ancestors/1` recursive CTE to SheetQueries
- [ ] Replace `build_ancestor_chain/2` to use `list_ancestors`
- [ ] Replace `build_ancestor_list/1` in PropertyInheritance to use `SheetQueries.list_ancestors`
- [ ] Run existing tests: `mix test test/storyarn/sheets_test.exs`

---

## Phase 4: C1 — `get_descendant_sheet_ids` via recursive CTE

**File:** `lib/storyarn/sheets/property_inheritance.ex`

### Current (O(N) recursive queries)
One query per tree level per branch. 5 levels deep with 20 children/level = 100+ queries.

### Fix
Recursive CTE that walks `parent_id` downward.

```elixir
def get_descendant_sheet_ids(sheet_id) do
  cte_query =
    Sheet
    |> where([s], s.parent_id == ^sheet_id and is_nil(s.deleted_at))
    |> select([s], %{id: s.id})
    |> union_all(^(
      from(s in Sheet,
        join: d in "descendants_cte", on: s.parent_id == d.id,
        where: is_nil(s.deleted_at),
        select: %{id: s.id}
      )
    ))

  {"descendants_cte", Sheet}
  |> recursive_ctes(true)
  |> with_cte("descendants_cte", as: ^cte_query)
  |> select([d], d.id)
  |> Repo.all()
end
```

- [ ] Replace `get_descendant_sheet_ids/1` with recursive CTE
- [ ] Run existing tests: `mix test test/storyarn/sheets_test.exs`

---

## Phase 5: C3 — TableCrud bulk JSONB operations

**File:** `lib/storyarn/sheets/table_crud.ex`

### Current (N updates per operation)
`add_cell_to_all_rows`, `remove_cell_from_all_rows`, `migrate_cells_key`, `reset_cells_for_column` — each loads all rows then updates one-by-one with changeset.

### Fix
Use `Repo.update_all` with PostgreSQL JSONB operators via `fragment`.

```elixir
# Add cell: cells || '{"column_slug": null}'::jsonb WHERE NOT cells ? 'column_slug'
defp add_cell_to_all_rows(block_id, column_slug) do
  from(r in TableRow,
    where: r.block_id == ^block_id and not fragment("? \\? ?", r.cells, ^column_slug)
  )
  |> Repo.update_all(
    set: [cells: fragment("? || jsonb_build_object(?, null)", r.cells, ^column_slug)]
  )
end

# Remove cell: cells - 'column_slug'
defp remove_cell_from_all_rows(block_id, column_slug) do
  from(r in TableRow, where: r.block_id == ^block_id)
  |> Repo.update_all(
    set: [cells: fragment("? - ?", r.cells, ^column_slug)]
  )
end

# Rename key: (cells - old_slug) || jsonb_build_object(new_slug, cells->old_slug)
defp migrate_cells_key(block_id, old_slug, new_slug) do
  from(r in TableRow, where: r.block_id == ^block_id)
  |> Repo.update_all(
    set: [cells: fragment(
      "(? - ?) || jsonb_build_object(?, ? -> ?)",
      r.cells, ^old_slug, ^new_slug, r.cells, ^old_slug
    )]
  )
  {:ok, :done}
end

# Reset cell value to null: cells || '{"column_slug": null}'::jsonb
defp reset_cells_for_column(block_id, column_slug) do
  from(r in TableRow, where: r.block_id == ^block_id)
  |> Repo.update_all(
    set: [cells: fragment("? || jsonb_build_object(?, null)", r.cells, ^column_slug)]
  )
  {:ok, :done}
end
```

Also update `migrate_cells_key_for_instances` and `reset_cells_for_instances` to batch across all instance block_ids at once instead of looping.

- [ ] Replace `add_cell_to_all_rows/2` with JSONB `update_all`
- [ ] Replace `remove_cell_from_all_rows/2` with JSONB `update_all`
- [ ] Replace `migrate_cells_key/3` with JSONB `update_all`
- [ ] Replace `reset_cells_for_column/2` with JSONB `update_all`
- [ ] Update `migrate_cells_key_for_instances` to batch across all instance IDs
- [ ] Update `reset_cells_for_instances` to batch across all instance IDs
- [ ] Run existing tests: `mix test test/storyarn/sheets`

---

## Verification

After all phases: `mix compile --warnings-as-errors && mix format --check-formatted && mix credo --strict && mix test`
