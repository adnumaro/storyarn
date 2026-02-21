# Phase 4 — Variable Generation + Evaluator

> **Status:** Pending
> **Depends on:** [Phase 1 — Domain Model](./01_DOMAIN_MODEL.md) (can run in parallel with Phases 2-3-6 after Phase 1)
> **Next:** [Phase 5 — Expression System UI](./05_EXPRESSION_UI.md)

> **Problem:** Table data exists but is invisible to the expression system. Flows cannot read or write table cell values.
>
> **Goal:** Table cells generate variables. The evaluator includes them in the flat variable map. Existing features (conditions, instructions, debugger) work with table variables.
>
> **Principle:** Backend only. No UI changes in builders or expression editor. Just data pipeline.

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

### Variable reference paths (4 levels)

All table variable references use exactly 4 levels: `sheet.table.row.column`. No short-path, no default column — every reference is explicit and unambiguous.

- `nameless_one.attributes.strength.value` → `18`
- `nameless_one.attributes.strength.description` → **not a variable** (constant column)

Regular block variables remain 2 levels: `nameless_one.health`.

### Variable generation

Each non-constant cell (row × column) generates a variable entry in `list_project_variables`:

```elixir
%{
  sheet_shortcut: "nameless_one",
  variable_name: "attributes.strength.value",    # composite: table.row.column
  block_type: "number",                           # column type
  table_name: "attributes",                       # for UI grouping
  row_name: "strength",                           # for UI grouping
  column_name: "value"                            # for UI grouping
}
```

A table with only constant columns generates no variables (valid — purely reference data).

### Evaluator flat map

Key format: `"sheet_shortcut.variable_name"`:
- Regular blocks: `"nameless_one.health"`
- Table variables: `"nameless_one.attributes.strength.value"`

No changes to the evaluator engine — it receives a pre-built flat map as always.

---

## Key Files

| File                                                          | Action                                                            |
|---------------------------------------------------------------|-------------------------------------------------------------------|
| `lib/storyarn/sheets/sheet_queries.ex`                        | Modified — extend `list_project_variables` to include table cells |
| `lib/storyarn_web/live/flow_live/helpers/variable_helpers.ex` | Modified — handle composite variable names                        |
| `test/storyarn/sheets/sheet_queries_test.exs`                 | Modified — test table variable generation                         |
| `test/storyarn/flows/evaluator/engine_test.exs`               | Modified — test evaluator with table variables                    |

---

## Task 4.1 — Extend `list_project_variables`

Add a second query for table variables and merge with existing results.

**New function in `sheet_queries.ex`:**

```elixir
defp list_table_variables(project_id) do
  variable_column_types = ~w(number text boolean select multi_select date)

  from(tc in TableColumn,
    join: b in Block, on: tc.block_id == b.id,
    join: s in Sheet, on: b.sheet_id == s.id,
    join: tr in TableRow, on: tr.block_id == b.id,
    where: s.project_id == ^project_id,
    where: is_nil(s.deleted_at) and is_nil(b.deleted_at),
    where: b.type == "table",
    where: tc.is_constant == false,
    where: tc.type in ^variable_column_types,
    select: %{
      sheet_id: s.id,
      sheet_name: s.name,
      sheet_shortcut: coalesce(s.shortcut, fragment("CAST(? AS TEXT)", s.id)),
      block_id: b.id,
      variable_name: fragment("? || '.' || ? || '.' || ?", b.variable_name, tr.slug, tc.slug),
      block_type: tc.type,
      config: tc.config,
      table_name: b.variable_name,
      row_name: tr.slug,
      column_name: tc.slug
    },
    order_by: [asc: s.name, asc: b.position, asc: tr.position, asc: tc.position]
  )
  |> Repo.all()
  |> Enum.map(&extract_variable_options/1)
end
```

**Modify `list_project_variables/1`:**

```elixir
def list_project_variables(project_id) do
  block_vars = list_block_variables(project_id)   # renamed from current implementation
  table_vars = list_table_variables(project_id)
  block_vars ++ table_vars
end
```

**CRITICAL: Regular block variables need nil table fields.**

The existing `list_block_variables` (renamed from current `list_project_variables`) must add `table_name: nil, row_name: nil, column_name: nil` to each result so that all variables share the same map shape. Otherwise JS consumers (groupVariablesBySheet, condition builders) would crash on `v.table_name`:

```elixir
defp list_block_variables(project_id) do
  # ... existing query ...
  |> Repo.all()
  |> Enum.map(&extract_variable_options/1)
  |> Enum.map(&Map.merge(&1, %{table_name: nil, row_name: nil, column_name: nil}))  # ← ADD THIS
end
```

**Tests:**
- Table with 2 non-constant columns × 3 rows → 6 variables
- Constant columns generate no variables
- All-constant table generates 0 variables
- Variable names are composite: `"table_slug.row_slug.column_slug"`
- Regular block variables still work alongside table variables
- Regular block variables have `table_name: nil, row_name: nil, column_name: nil`

---

## Task 4.2 — Variable Helpers Update

Update `build_variables/1` to handle composite variable names.

**`variable_helpers.ex`:** No structural change needed — the key format `"#{var.sheet_shortcut}.#{var.variable_name}"` already produces the correct 4-level path because `variable_name` is already `"attributes.strength.value"` from the query.

However, `default_value/1` needs to handle all column types. Verify it covers: `number`, `text`, `boolean`, `select`, `multi_select`, `date`.

**Tests:**
- `build_variables/1` includes table variables with 4-level keys
- Default values correct for each column type
- Mix of regular + table variables in the same map

---

## Task 4.3 — Evaluator Integration Test

Verify that the evaluator can evaluate conditions and execute instructions on table variables.

**No code changes to the evaluator** — it works with the flat map as-is. This task is purely tests.

**Tests (engine_test.exs):**
- Condition node: `mc.jaime.attributes.strength.value > 10` → evaluates correctly
- Instruction node: `mc.jaime.attributes.strength.value += 5` → variable updated
- Mixed: regular variable condition + table variable instruction (and vice versa)
- Variable reference in instruction: `set mc.jaime.attributes.charisma.value to mc.morte.attributes.charisma.value`

---

## Phase 4 — Post-phase Audit

```
□ Run `just quality` — all green
□ Security: SQL query parameterized, no injection
□ Dead code: no unused query functions
□ Duplication: extract_variable_options reused for both block and table vars
□ Potential bugs: nil sheet shortcut handled by coalesce, nil cells use default_value
□ SOLID: query logic in SheetQueries, building logic in VariableHelpers — clean separation
□ KISS: single SQL query per source (blocks, tables), merged in Elixir
□ YAGNI: no caching, no pagination for variables — not needed at current scale
```

---

[← Phase 6 — Inheritance](./06_INHERITANCE.md) | [Phase 5 — Expression System UI →](./05_EXPRESSION_UI.md)
