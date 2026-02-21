# Shortcut Collision Validation

> **Priority:** Low | **Effort:** Trivial
> **Depends on:** Table Block (SHEET_DATA_TYPES.md)
> **Status:** Pending

---

## Problem

With the introduction of table blocks, variable paths become 4 levels deep: `sheet.table.row.column`. This creates a theoretical ambiguity: if a sheet has shortcut `mc.jaime.attributes` and a regular block `strength`, the path `mc.jaime.attributes.strength` could be confused with a table variable from sheet `mc.jaime` with table `attributes` and row `strength`.

In practice, the parser resolves by matching against the known variable list, so this is extremely unlikely. However, explicit validation would prevent the edge case entirely.

## Proposed Solution

When creating or updating a sheet shortcut, validate that the new shortcut does not collide with `existing_shortcut.table_block_variable_name` patterns from other sheets in the same project. This is a simple query at save time.

## Current Mitigation

The parser matches paths against the full variable list at parse time. Ambiguity only arises if two variables produce the exact same full path string, which is already prevented by the existing uniqueness constraints on sheet shortcuts and block variable names within a project.
