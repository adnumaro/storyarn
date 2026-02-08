# Page Property Inheritance

> **Goal:** Enable organic property inheritance between parent and child pages (sheets), so parent-defined properties cascade to children with visual clarity and flexible override/detach/hide controls.
>
> **Proposal:** [PAGE_INHERITANCE_PROPOSAL.md](../proposals/PAGE_INHERITANCE_PROPOSAL.md)
>
> **Priority:** After Phase 7.5 (Sheets Enhancement) - builds on blocks, shortcuts, and tree system
>
> **Last Updated:** February 8, 2026

---

## Overview

When adding a block (property) to a sheet, users can choose its **scope**:
- **"This page only"** (`self`) - block exists only on this sheet
- **"This page and children"** (`children`) - block definition cascades to all descendant sheets

Children see inherited properties in a visually distinct section, can fill in their own values, and can **detach** (make local), **hide for children** (stop cascading), or **navigate to source**.

---

## Architecture Approach

### Key Design Decision: Eager Instance Creation

When a child sheet is created (or a new inheritable block is added to a parent), we **copy the block definition** (type, config) as a new block on each child with a reference back to the source. This means:

- Each child has its own `blocks` rows for inherited properties (with own values)
- The `inherited_from_block_id` field links back to the parent's defining block
- Changes to parent definition (type, config) propagate to non-detached children
- Values are always local to each child - no shared state

**Why not virtual resolution?** Virtual resolution (computing inheritance at query time) avoids data duplication but creates complexity around value storage, ordering, and performance for deeply nested trees. Eager instances are more predictable, easier to query, and integrate cleanly with the existing block system (variables, references, versioning).

---

## Data Model Changes

### Block Schema (modified)

```
blocks (existing table)
├── ...existing fields...
├── scope           # NEW: "self" (default) | "children"
├── inherited_from_block_id  # NEW: FK to blocks (source definition block)
├── detached        # NEW: boolean, default false (was inherited, now local)
└── required        # NEW: boolean, default false (parent marks as required)
```

### Sheet Schema (modified)

```
sheets (existing table)
├── ...existing fields...
└── hidden_inherited_block_ids  # NEW: JSONB array of ancestor block IDs hidden for children
```

### Inheritance Resolution (at query time)

When rendering a sheet's content:

1. Load the sheet's own blocks (where `inherited_from_block_id IS NULL` or `detached = true`)
2. Load inherited blocks (where `inherited_from_block_id IS NOT NULL` and `detached = false`)
3. Group inherited blocks by source sheet (using the FK chain)
4. Check `hidden_inherited_block_ids` on intermediate ancestors to filter
5. Display inherited blocks grouped by source, then own blocks

---

## Implementation Tasks

### PI.1 Database Migration & Schema

#### PI.1.1 Migration: Add inheritance fields to blocks
- [ ] Add `scope` column (string, default `"self"`)
- [ ] Add `inherited_from_block_id` column (FK to blocks, nullable, `on_delete: :nilify_all`)
- [ ] Add `detached` column (boolean, default `false`)
- [ ] Add `required` column (boolean, default `false`)
- [ ] Add index on `inherited_from_block_id`
- [ ] Add index on `(sheet_id, inherited_from_block_id)` for efficient lookups

#### PI.1.2 Migration: Add inheritance fields to sheets
- [ ] Add `hidden_inherited_block_ids` column (JSONB, default `[]`)

#### PI.1.3 Update Block schema
- [ ] Add `scope` field (`:string`, default `"self"`)
- [ ] Add `inherited_from_block_id` field (`belongs_to :inherited_from_block, Block`)
- [ ] Add `detached` field (`:boolean`, default `false`)
- [ ] Add `required` field (`:boolean`, default `false`)
- [ ] Add `inherited_instances` association (`has_many :inherited_instances, Block, foreign_key: :inherited_from_block_id`)
- [ ] Update `create_changeset/2` and `update_changeset/2` to cast new fields
- [ ] Validate `scope` inclusion in `["self", "children"]`
- [ ] Add `inherited?/1` helper: `not is_nil(block.inherited_from_block_id) and not block.detached`

#### PI.1.4 Update Sheet schema
- [ ] Add `hidden_inherited_block_ids` field (`{:array, :integer}`, default `[]`)
- [ ] Update changesets to cast new field

---

### PI.2 Core Inheritance Logic

#### PI.2.1 New module: `Sheets.PropertyInheritance`
- [ ] `resolve_inherited_blocks/1` (sheet_id) - Returns inherited blocks for a sheet:
  1. Walk ancestors (using existing `get_sheet_with_ancestors/2`)
  2. Collect all blocks with `scope: "children"` from each ancestor
  3. Filter out blocks whose IDs appear in any intermediate sheet's `hidden_inherited_block_ids`
  4. Return as `[%{source_sheet: sheet, blocks: [block, ...]}]` grouped by source
- [ ] `create_inherited_instances/2` (parent_block, child_sheet_ids) - Creates block copies:
  1. For each child sheet, create a new block with:
     - Same `type`, `config`, `required` as parent block
     - Default `value` for the type
     - `inherited_from_block_id` pointing to parent block
     - `scope: "self"` (instances don't cascade by default)
  2. Return `{:ok, created_count}`
- [ ] `propagate_to_descendants/2` (parent_block, selected_sheet_ids) - Bulk create instances for selected existing children
- [ ] `sync_definition_change/1` (parent_block) - When parent block config/type changes, update all non-detached instances:
  1. Find all blocks with `inherited_from_block_id == parent_block.id` and `detached == false`
  2. Update their `type` and `config` to match parent
  3. Handle type incompatibility (clear value if type changed)
- [ ] `detach_block/1` (inherited_block) - Convert inherited to local:
  1. Set `detached: true`
  2. Keep `inherited_from_block_id` for provenance (allows re-attach)
- [ ] `reattach_block/1` (detached_block) - Re-sync with parent:
  1. Fetch source block via `inherited_from_block_id`
  2. Update type, config to match source
  3. Set `detached: false`
- [ ] `hide_for_children/2` (sheet, ancestor_block_id) - Add block ID to sheet's `hidden_inherited_block_ids`
- [ ] `unhide_for_children/2` (sheet, ancestor_block_id) - Remove from list
- [ ] `delete_inherited_instances/1` (parent_block) - When parent block with `scope: "children"` is deleted, soft-delete all instances
- [ ] `get_source_sheet/1` (inherited_block) - Navigate to the sheet that owns the source block

#### PI.2.2 Update `Sheets.BlockCrud`
- [ ] On `create_block/2`: If `scope: "children"`, auto-create instances on all descendant sheets (unless this is itself an instance)
- [ ] On `update_block_config/2`: If block has `scope: "children"`, call `sync_definition_change`
- [ ] On `delete_block/1`: If block has `scope: "children"`, call `delete_inherited_instances`
- [ ] On `update_block/2`: If `scope` changes from `"self"` to `"children"`, show propagation flow; if `"children"` to `"self"`, remove instances (with confirmation)

#### PI.2.3 Update `Sheets.SheetCrud`
- [ ] On `create_sheet/2`: After creating the sheet, auto-create inherited block instances from all ancestors
- [ ] On `move_sheet/3`: When moving to a new parent, recalculate inherited blocks:
  1. Remove inherited instances from old ancestor chain
  2. Create inherited instances from new ancestor chain
  3. Preserve detached blocks (they stay local)

#### PI.2.4 Update `Sheets.SheetQueries`
- [ ] `get_sheet_with_inherited_blocks/1` - Load sheet with both own and inherited blocks, grouped
- [ ] `list_inheritable_blocks/1` (sheet_id) - List all blocks with `scope: "children"` for a sheet
- [ ] `list_inherited_instances/1` (parent_block_id) - List all instance blocks

---

### PI.3 Property Scope UI

#### PI.3.1 Scope selector in block creation
- [ ] When adding a block (via `block_menu`), show scope radio buttons:
  - "This page only" (default)
  - "This page and all children"
- [ ] Pass `scope` parameter to `create_block`
- [ ] Only show scope selector if sheet has children OR is likely to have children (always show - it's lightweight)

#### PI.3.2 Scope selector in block config panel
- [ ] Add scope field to `config_panel` component
- [ ] Radio buttons: "This page only" / "This page and children"
- [ ] Warning when changing scope from "children" to "self": "This will remove this property from X child pages. Proceed?"
- [ ] Warning when changing scope from "self" to "children": Show propagation modal (PI.5)

#### PI.3.3 Required toggle for inheritable blocks
- [ ] Add "Required" checkbox in config panel (only visible when `scope: "children"`)
- [ ] Visual indicator on required inherited blocks (asterisk or badge)

#### PI.3.4 Visual indicators on blocks with `scope: "children"`
- [ ] Badge/icon on parent blocks indicating they cascade (e.g., down-arrow icon or "Inherited by children" label)
- [ ] Show count of children using this property

---

### PI.4 Inherited Properties Display

#### PI.4.1 Update `ContentTab` component
- [ ] Split blocks into two sections:
  1. **Inherited Properties** - grouped by source sheet, with visual distinction
  2. **Own Properties** - existing block list
- [ ] Inherited section header: "Inherited from {SheetName}" with link to source
- [ ] Each inherited block shows a `link-up` icon (click navigates to source sheet)
- [ ] Inherited blocks use slightly different styling (e.g., subtle background tint, left border accent)

#### PI.4.2 New component: `InheritedBlockComponent`
- [ ] Renders an inherited block with:
  - Same editing capabilities as own blocks (fill in values)
  - Source indicator icon (`link-up` or `arrow-up`)
  - Context menu trigger (`...` or right-click)
- [ ] Context menu actions:
  - "Go to source" - navigate to parent sheet
  - "Detach property" - make local copy
  - "Hide for children" - stop cascading to this sheet's children

#### PI.4.3 Inherited section header component
- [ ] "Inherited from {SheetName}" with sheet avatar and link
- [ ] Collapse/expand toggle for each source group
- [ ] Badge showing property count per source

#### PI.4.4 Empty state for inherited properties
- [ ] When sheet is a child but has no inherited properties: no section shown (clean)
- [ ] When sheet has children but no inheritable blocks: subtle hint in config panel

---

### PI.5 Propagation Modal

#### PI.5.1 PropagationModal LiveComponent
- [ ] Triggered when:
  - Adding a new block with `scope: "children"` to a sheet that already has descendants
  - Changing an existing block's scope from "self" to "children"
- [ ] Shows tree view of descendants with checkboxes:
  - "Select all (N pages)" toggle
  - Expandable tree showing child hierarchy
  - Each child has a checkbox (default: checked)
- [ ] Info text: "New child pages will automatically inherit this property"
- [ ] Actions: "Cancel" and "Propagate"
- [ ] On confirm: calls `propagate_to_descendants/2` with selected sheet IDs

#### PI.5.2 Propagation events in ContentTab
- [ ] Handle `"open_propagation_modal"` event
- [ ] Handle `"propagate_property"` event with selected sheet IDs
- [ ] Handle `"cancel_propagation"` event
- [ ] Show loading state during propagation (for large trees)

---

### PI.6 Detach, Hide, and Context Actions

#### PI.6.1 Detach property
- [ ] LiveView event: `"detach_inherited_block"` with block ID
- [ ] Calls `PropertyInheritance.detach_block/1`
- [ ] Block moves from "Inherited" section to "Own Properties" section
- [ ] Show flash: "Property detached. Changes to {SourceSheet} won't affect this copy."
- [ ] Detached blocks show a subtle "detached" indicator (optional)

#### PI.6.2 Re-attach property
- [ ] Show "Re-sync with {SourceSheet}" option on detached blocks (in config panel)
- [ ] Warning: "This will reset the property definition to match {SourceSheet}. Your value will be preserved."
- [ ] Calls `PropertyInheritance.reattach_block/1`

#### PI.6.3 Hide for children
- [ ] LiveView event: `"hide_inherited_for_children"` with ancestor block ID
- [ ] Calls `PropertyInheritance.hide_for_children/2`
- [ ] Visual change: block shows "Hidden from children" indicator
- [ ] Option to unhide: `"unhide_inherited_for_children"`

#### PI.6.4 Go to source
- [ ] LiveView event: `"navigate_to_source"` with block ID
- [ ] Resolves source sheet via `inherited_from_block_id` chain
- [ ] Navigates to source sheet (using `push_navigate`)

---

### PI.7 Integration with Existing Systems

#### PI.7.1 Variable system integration
- [ ] Inherited blocks ARE variables (same rules apply: `is_constant`, `variable_name`)
- [ ] Variable path uses child's shortcut: `child_shortcut.variable_name` (not parent's)
- [ ] `list_project_variables/1` includes inherited block instances
- [ ] Ensure `variable_name` uniqueness still works per-sheet (inherited instances get own variable names)

#### PI.7.2 Version control integration
- [ ] Inherited block instances are included in version snapshots (they're real blocks)
- [ ] Version diff shows inherited vs own distinction
- [ ] Restoring a version preserves inheritance relationships

#### PI.7.3 Reference tracking integration
- [ ] Inherited block instances tracked in `entity_references` (same as own blocks)
- [ ] Backlinks work for inherited properties

#### PI.7.4 Soft delete integration
- [ ] Soft-deleting a parent block with `scope: "children"` soft-deletes all instances
- [ ] Restoring parent block restores instances
- [ ] Soft-deleting a sheet preserves inherited block data (for restore)

#### PI.7.5 Tree operations integration
- [ ] Moving a sheet recalculates inherited blocks
- [ ] Duplicating a sheet copies inherited instances (with new `inherited_from_block_id` if parent is same)

---

## Database Migrations

### Migration 1: Block inheritance fields

```elixir
alter table(:blocks) do
  add :scope, :string, default: "self"
  add :inherited_from_block_id, references(:blocks, on_delete: :nilify_all)
  add :detached, :boolean, default: false
  add :required, :boolean, default: false
end

create index(:blocks, [:inherited_from_block_id])
create index(:blocks, [:sheet_id, :inherited_from_block_id])
create index(:blocks, [:scope], where: "scope = 'children'")
```

### Migration 2: Sheet hidden inherited block IDs

```elixir
alter table(:sheets) do
  add :hidden_inherited_block_ids, {:array, :integer}, default: []
end
```

---

## UI/UX Specifications

### Child Page View

```
┌─────────────────────────────────────────────────────────┐
│ [Banner]                                                │
│ [Avatar]  Jaime                          [Content ▼]    │
│           #mc.jaime                                     │
├─────────────────────────────────────────────────────────┤
│                                                         │
│ ┌─ Inherited from Characters ──────────── [▼ Collapse] ┐│
│ │ [≡] Portrait  [Select image...]    [↑ source] [⋮]   ││
│ │ [≡] Age       [32              ]   [↑ source] [⋮]   ││
│ │ [≡] Backstory [Rich text...    ]   [↑ source] [⋮]   ││
│ └──────────────────────────────────────────────────────┘│
│                                                         │
│ ┌─ Own Properties ─────────────────────────────────────┐│
│ │ [≡] Weapon    [Sword           ]        [⚙] [🗑]    ││
│ │ [≡] Faction   [House Lannister ]        [⚙] [🗑]    ││
│ │                                                      ││
│ │ Type / to add a block...                             ││
│ └──────────────────────────────────────────────────────┘│
│                                                         │
│ ─── Subsheets ──────────────────────────────────────    │
│ [Avatar] Child Sheet 1                                  │
│ [Avatar] Child Sheet 2                                  │
└─────────────────────────────────────────────────────────┘
```

### Context Menu on Inherited Block

```
┌────────────────────────┐
│ ↑ Go to source         │
│ ✂ Detach property      │
│ 🚫 Hide for children   │
└────────────────────────┘
```

### Block Creation with Scope

```
┌─ Add Block ─────────────────────────────────┐
│ [text] [number] [select] [boolean] [...]    │
│                                              │
│ Scope:                                       │
│ ○ This page only                             │
│ ● This page and all children                 │
│                                              │
│ [Cancel]                        [Add]        │
└──────────────────────────────────────────────┘
```

### Propagation Modal

```
┌─ Propagate "Faction" to existing children? ──────────┐
│                                                       │
│ This property will automatically appear in all        │
│ NEW children. For existing children:                  │
│                                                       │
│ [☑] Select all (12 pages)                             │
│                                                       │
│ ▼ Characters                                          │
│   [☑] Jaime                                           │
│   [☑] Cersei                                          │
│   [☑] Tyrion                                          │
│   ▼ Nobles                                            │
│     [☑] Duke                                          │
│     [☐] Baron                                         │
│                                                       │
│ ℹ Unselected pages won't get this property but can    │
│   add it manually later.                              │
│                                                       │
│ [Cancel]                           [Propagate]        │
└───────────────────────────────────────────────────────┘
```

---

## Implementation Order

| Order | Task | Dependencies | Testable Outcome |
|-------|------|-------------|------------------|
| 1 | PI.1 - Migration & Schema | None | Fields exist, changesets work |
| 2 | PI.2.1 - PropertyInheritance module | PI.1 | Core logic works in tests |
| 3 | PI.2.2 - BlockCrud integration | PI.2.1 | Creating `scope: "children"` block creates instances |
| 4 | PI.2.3 - SheetCrud integration | PI.2.1 | New child sheets get inherited blocks |
| 5 | PI.3 - Scope selector UI | PI.1 | Can set scope when creating/configuring blocks |
| 6 | PI.4 - Inherited display | PI.2 | Child pages show inherited section |
| 7 | PI.5 - Propagation modal | PI.2 | Can propagate to existing children |
| 8 | PI.6 - Detach/Hide/Actions | PI.2, PI.4 | Context menu works |
| 9 | PI.7 - System integration | PI.2 | Variables, versions, refs work with inheritance |

---

## Open Questions (from proposal)

1. **Property ordering** - Can children reorder inherited properties?
   - Recommendation: No in Phase 1. Inherited blocks keep parent's order. Children can only reorder own blocks.

2. **Required vs optional** - Should inheritance respect required flag?
   - Recommendation: Yes. Parent can mark as required, UI shows asterisk. No hard validation in Phase 1 (just visual).

3. **Validation** - How to handle validation rules on inherited properties?
   - Recommendation: Defer to future. Type + config is enough for Phase 1.

4. **Bulk operations** - UI for propagating to many children efficiently?
   - Recommendation: Propagation modal with tree checkboxes. Background job for 50+ children.

5. **Conflict resolution** - What if child has property with same name as new inherited one?
   - Recommendation: Show warning in propagation modal. Skip conflicting children and list them. User can manually detach the local property.

6. **Type change in parent** - What happens to child values?
   - Recommendation: Clear value with warning on incompatible type change. Convert where possible (number "42" to text "42").

---

## Testing Strategy

### Unit Tests
- [ ] Block scope validation ("self", "children")
- [ ] `resolve_inherited_blocks/1` with single level
- [ ] `resolve_inherited_blocks/1` with multi-level (grandparent → parent → child)
- [ ] `resolve_inherited_blocks/1` with hidden blocks
- [ ] `create_inherited_instances/2` creates correct copies
- [ ] `sync_definition_change/1` updates non-detached instances
- [ ] `sync_definition_change/1` skips detached instances
- [ ] `detach_block/1` sets flags correctly
- [ ] `reattach_block/1` resets to parent definition
- [ ] `hide_for_children/2` updates sheet's hidden list
- [ ] Variable names unique per child sheet
- [ ] Moving sheet recalculates inheritance

### Integration Tests
- [ ] Create parent with inheritable block → create child → child has instance
- [ ] Update parent block config → child instance syncs
- [ ] Detach inherited block → parent changes don't propagate
- [ ] Hide for children → grandchildren don't inherit
- [ ] Delete parent block → child instances soft-deleted
- [ ] Move sheet to different parent → inheritance recalculated

### LiveView Tests
- [ ] Content tab shows inherited section
- [ ] Context menu actions work (detach, hide, go to source)
- [ ] Scope selector in block menu
- [ ] Propagation modal opens and propagates

---

## Performance Considerations

- **Ancestor walk**: `get_sheet_with_ancestors` already exists and uses recursive query. Bounded by tree depth (typically < 10 levels).
- **Instance creation**: For large propagation (100+ children), use `Repo.insert_all/2` instead of individual inserts.
- **Config sync**: When parent block config changes, batch-update all instances with `Repo.update_all/2`.
- **Hidden block filtering**: JSONB `@>` operator for efficient array containment checks.
- **Index strategy**: Index on `inherited_from_block_id` covers most inheritance queries.

---

## Success Criteria

- [ ] Blocks can be created with "children" scope
- [ ] Child sheets automatically inherit parent's "children" blocks
- [ ] Inherited blocks display in visually distinct section
- [ ] Users can fill values on inherited blocks
- [ ] Detach converts inherited to local
- [ ] Hide for children stops cascading
- [ ] Multi-level inheritance works (grandparent → parent → child)
- [ ] Propagation modal works for existing children
- [ ] Variable system works with inherited blocks
- [ ] Moving sheets recalculates inheritance

---

*This plan will be incorporated into IMPLEMENTATION_PLAN.md once approved and implementation begins.*
