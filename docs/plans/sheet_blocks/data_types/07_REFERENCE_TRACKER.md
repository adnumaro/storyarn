# Phase 7 — Variable Reference Tracker Adaptation

> **Status:** Pending
> **Depends on:** [Phase 4 — Variable Generation](./04_VARIABLE_GENERATION.md)
> **Next:** None (terminal phase)

> **Problem:** The Variable Reference Tracker can't resolve table variable paths. When a node references `mc.jaime.attributes.strength.value`, the tracker can't find the corresponding block + column + row.
>
> **Goal:** `resolve_block` handles composite paths. Staleness detection works for table variables. Repair logic works.
>
> **Principle:** Minimal changes. No schema changes to `variable_references` table. Store composite path in existing `source_variable` field.

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

### Variable Reference Tracker integration

No schema changes to `variable_references` table. `source_variable` stores the full composite path (`"attributes.strength.value"`). The `resolve_block` function detects dots in `source_variable` to determine if it's a table variable and resolves against `table_rows` + `table_columns` instead of `blocks`.

### Known limitations

**Rename breakage:** Renaming a table block, row, or column regenerates the slug and breaks existing expressions. The tracker detects this as staleness and offers repair. This is the same limitation as renaming regular block labels — repair is user-triggered, not automatic.

> **TODO (future):** Auto-rename variable references across all flows when a block/row/column is renamed. System-wide improvement, not table-specific. Planned separately.

**Path ambiguity (theoretical):** `mc.jaime.attributes.strength` could be ambiguous if a sheet has shortcut `mc.jaime.attributes`. In practice, the parser resolves by matching against the known variable list, and uniqueness constraints prevent collisions. Edge case documented in `docs/plans/pending/SHORTCUT_COLLISION_VALIDATION.md`.

---

## Key Files

| File                                                      | Action                                         |
|-----------------------------------------------------------|------------------------------------------------|
| `lib/storyarn/flows/variable_reference_tracker.ex`        | Modified — `resolve_block` handles table paths |
| `test/storyarn/flows/variable_reference_tracker_test.exs` | Modified — table variable tests                |

---

## Task 7.1 — `resolve_block` for Table Paths

Update `resolve_block/3` to handle composite variable names.

**Current:** `resolve_block(project_id, "mc.jaime", "health")` → finds block by `sheet.shortcut == "mc.jaime" AND block.variable_name == "health"`.

**New:** `resolve_block(project_id, "mc.jaime", "attributes.strength.value")` → detects dots in `source_variable`, splits into `table_name.row_slug.column_slug`, finds block by:

```elixir
defp resolve_block(project_id, sheet_shortcut, source_variable)
     when is_binary(sheet_shortcut) and sheet_shortcut != "" and
            is_binary(source_variable) and source_variable != "" do
  case String.split(source_variable, ".", parts: 3) do
    [table_name, row_slug, column_slug] ->
      resolve_table_variable(project_id, sheet_shortcut, table_name, row_slug, column_slug)
    _ ->
      resolve_regular_block(project_id, sheet_shortcut, source_variable)
  end
end
```

**`resolve_table_variable/5`:** Query joins `blocks` → `table_rows` → `table_columns` to verify the variable exists. Returns the `block.id` (the table block — consistent with how references point to blocks).

**Note on split safety:** The split is on `source_variable` only, never on the full path. Sheet shortcuts with dots (e.g., `"mc.jaime"`) are not affected because `sheet_shortcut` and `source_variable` are already separate parameters.

**Tests:**
- Regular variable → resolves to block_id as before
- Table variable → resolves to table block_id
- Non-existent table variable → returns nil
- Renamed table/row/column → detected as stale

---

## Task 7.2 — Staleness Detection for Table Variables

Verify that the existing staleness query works with composite paths.

**Current staleness check** (line ~125 in tracker): compares `vr.source_sheet != s.shortcut OR vr.source_variable != b.variable_name`.

For table variables, `source_variable` is `"attributes.strength.value"` and `block.variable_name` is `"attributes"` — they won't match directly. The staleness query needs to handle this.

**Problem:** For table variable references, `source_variable` is `"attributes.strength.value"` but `block.variable_name` is `"attributes"`. The current staleness check (`vr.source_variable != b.variable_name`) will ALWAYS flag table vars as stale.

**Solution:** Split the staleness query into two:

1. **Regular block references** (source_variable has no dots): existing query unchanged
2. **Table variable references** (source_variable has dots): new query that uses `NOT EXISTS` subquery to check if the composite path still matches:

```elixir
# Table variable staleness: a reference is stale when the reconstructed path
# (block.variable_name || '.' || row.slug || '.' || column.slug) doesn't match
# the stored source_variable, OR when the row/column no longer exists.

defp list_stale_table_references(flow_id) do
  from(vr in VariableReference,
    join: fn_ in FlowNode, on: fn_.id == vr.flow_node_id,
    join: b in Block, on: b.id == vr.block_id,
    join: s in Sheet, on: s.id == b.sheet_id,
    where: fn_.flow_id == ^flow_id,
    where: b.type == "table",
    where: like(vr.source_variable, "%.%.%"),  # has dots = table variable
    where: is_nil(s.deleted_at) and is_nil(b.deleted_at),
    # Stale when: sheet shortcut changed, OR path doesn't match any current combo
    where: vr.source_sheet != s.shortcut
      or fragment(
        "NOT EXISTS (
          SELECT 1 FROM table_rows tr2
          JOIN table_columns tc2 ON tc2.block_id = tr2.block_id
          WHERE tr2.block_id = ? AND ? = ? || '.' || tr2.slug || '.' || tc2.slug
        )", b.id, vr.source_variable, b.variable_name
      ),
    distinct: vr.id,
    preload: [flow_node: [], block: []]
  )
  |> Repo.all()
end
```

**Note:** No unnecessary left joins in this query. The `NOT EXISTS` subquery handles the row/column existence check directly, which is more efficient than left joining `table_rows` and `table_columns` in the outer query.

Merge results from both queries in `list_stale_references/1`.

**Tests:**
- Rename table block label → reference becomes stale
- Rename row → reference becomes stale
- Rename column → reference becomes stale
- Delete row → reference becomes stale
- No rename → reference is fresh
- Regular block references → NOT affected by new query

---

## Task 7.3 — Repair Logic for Table Variables

Update `repair_node_data` to handle composite paths.

**Current repair:** Replaces `sheet` and `variable` fields in condition rules and instruction assignments with current values from the block.

**For table variables:** After resolving via block_id, reconstruct the current composite path:
```elixir
current_variable = "#{block.variable_name}.#{row.slug}.#{column.slug}"
```

Replace the old `variable` field with the new composite path.

**Tests:**
- Rename table → repair updates variable field in condition rule
- Rename row → repair updates variable field in instruction assignment
- Mixed regular + table variables → both repaired correctly

---

## Phase 7 — Post-phase Audit

```
□ Run `just quality` — all green
□ Security: no SQL injection in dynamic path splitting
□ Dead code: old resolve_block is refactored, not duplicated
□ Duplication: resolve_table_variable shares query patterns with resolve_regular_block
□ Potential bugs: dots in sheet shortcut (e.g., "mc.jaime") don't confuse path splitting — split is on source_variable only, not full path
□ SOLID: resolve logic handles dispatch, individual resolvers handle specifics
□ KISS: string split with parts: 3, not regex
□ YAGNI: no batch repair, no auto-repair on rename — user-triggered only (same as blocks)
```

---

[← Phase 5 — Expression System UI](./05_EXPRESSION_UI.md)
