# Plan 9: Required Field Validation

> **Scope:** Implement the `required` flag as a completeness linter for inherited blocks.
>
> **Depends on:** Plans 0-7 (toolbar + popovers), Plan 8 (cleanup)

---

## Context

The `required` flag on blocks (`blocks.required`) already exists in the DB and can be toggled via the Advanced section in the config popover (only visible when `scope = "children"`). However, the flag is currently **purely decorative** — nothing checks or enforces it.

This plan implements the full feature: visual indicators on child sheets, default value inheritance, and a completeness summary.

---

## Design Decisions

- **`required` only applies to `scope = "children"`** — it's a template rule: "all child sheets must fill in this field."
- **Non-blocking** — required fields show warnings, never prevent saving. It's a narrative linter, not a hard constraint.
- **Default values** — the parent can set a value that children inherit as a starting point, but children can override it.

---

## Implementation

### 1. Visual indicator on child sheets

When a child sheet has an inherited block with `required = true` and the block's value is empty/default:

- Show a visual indicator (colored left border, asterisk, or subtle badge) on the block
- Tooltip: "This field is required by the parent template"

**Files:**
- `lib/storyarn_web/live/sheet_live/components/inherited_block_components.ex` — add required indicator to `inherited_block_wrapper`

### 2. Empty value detection

Define what "empty" means per block type:

| Type | Empty when |
|------|-----------|
| `text` | `""` or `nil` |
| `rich_text` | `""`, `nil`, or `"<p></p>"` |
| `number` | `nil` |
| `select` | `nil` |
| `multi_select` | `[]` or `nil` |
| `boolean` | `nil` (false is a valid value) |
| `date` | `nil` |

**Files:**
- `lib/storyarn/sheets/block.ex` — add `value_empty?(block)` function

### 3. Completeness summary per sheet

A small indicator showing required field completion status, e.g., "3/5 required fields completed."

**Where:** Sheet header or content tab header area.

**Files:**
- `lib/storyarn/sheets.ex` (or submodule) — `required_fields_status(sheet_id)` returning `{filled, total}`
- `lib/storyarn_web/live/sheet_live/components/content_tab.ex` — render completeness badge

### 4. Default value inheritance

When a parent block has `scope = "children"` and a non-empty value, child sheets should inherit that value as a default when the inherited block is first created via `resolve_inherited_blocks`.

**Files:**
- `lib/storyarn/sheets/property_inheritance.ex` — copy parent block value to inherited block on creation

---

## Out of Scope

- Blocking save on missing required fields (explicitly not wanted)
- Project-wide completeness reports (future feature)
- Required for `scope = "self"` blocks (no clear use case)

---

## Verification

```bash
mix compile --warnings-as-errors
mix format --check-formatted
mix credo --strict
MIX_TEST_PORT=4042 mix test
```

Manual: Create parent sheet with required children-scoped block → create child sheet → verify indicator shows on empty required block → fill in value → indicator disappears → check completeness summary updates.
