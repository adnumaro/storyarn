# Plan 7: Table & Divider Toolbar Variants

> **Scope:** Toolbar adjustments for `table` and `divider` block types (no config popover).
>
> **Depends on:** Plan 0 (Universal Toolbar)

---

## Goal

### Table Block

Table blocks already have full inline configuration via column header menus. The toolbar shows:
- **[Duplicate]** — duplicates the table block (with columns and rows)
- **[⋮ → Delete]** — overflow menu with Delete action
- **No config gear** — inline column menus handle config
- **No constant toggle** — tables can't be variables

Drag handle stays ON the block (not in toolbar). No new popover needed.

### Divider Block

Divider blocks are purely visual separators. The toolbar shows:
- **[Duplicate]** — duplicates the divider
- **[⋮ → Delete]** — overflow menu with Delete action
- **No config gear** — nothing to configure
- **No constant toggle** — dividers can't be variables

Drag handle stays ON the block (not in toolbar).

---

## Files to Modify

### 1. `block_toolbar.ex`

Verify that conditional rendering works:
- Table: `show_config=false`, `show_constant=false`. Only Duplicate + [⋮] rendered.
- Divider: `show_config=false`, `show_constant=false`. Only Duplicate + [⋮] rendered.

### 2. Verify inherited table toolbar

Inherited table blocks should show:
- Duplicate + [⋮] with Go to source, Detach, Hide for children, Delete
- Schema-locked indicator (columns can't be modified)

---

## Implementation Notes

This plan is primarily **verification and testing** — the universal toolbar from Plan 0 should already handle these cases via conditional rendering flags (`show_constant`, `show_config`). The implementation here is:

1. Verify the flags work correctly in `block_toolbar.ex`
2. Add specific component tests for these edge cases
3. Verify table column header menus still work after toolbar migration

---

## Tests

### Unit: Table Toolbar

**File:** `test/storyarn_web/components/block_toolbar_table_divider_test.exs`

```elixir
describe "block_toolbar for table" do
  test "renders duplicate and [⋮] menu"
  test "does not render config gear"
  test "does not render constant toggle"
  test "renders inherited actions in [⋮] for inherited tables"
end

describe "block_toolbar for divider" do
  test "renders duplicate and [⋮] menu"
  test "does not render config gear"
  test "does not render constant toggle"
end
```

### Integration: Table Column Menus Still Work

**File:** `test/storyarn_web/live/sheet_live/handlers/table_toolbar_integration_test.exs`

```elixir
describe "table block with toolbar" do
  test "column header menu still opens after toolbar migration"
  test "add column still works"
  test "delete column still works"
  test "rename column still works"
  test "table block move up/down works"
  test "table block duplicate creates copy with columns and rows"
end

describe "divider block with toolbar" do
  test "divider block move up/down works"
  test "divider block delete works"
end
```

---

## Post-Implementation Audit

- [ ] All tests pass
- [ ] Manual: table block toolbar shows only Duplicate + [⋮]
- [ ] Manual: table column header menus still work
- [ ] Manual: table add/delete column still works
- [ ] Manual: divider toolbar shows only Duplicate + [⋮]
- [ ] Manual: no regressions in table inline editing
- [ ] Manual: inherited table shows correct actions in [⋮]
