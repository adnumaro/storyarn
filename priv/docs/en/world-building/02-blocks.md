%{
  title: "Blocks & Variables",
  category_label: "World Building",
  order: 2,
  description: "How blocks define your data structure and become variables for flows."
}
---

Blocks are the {accent}fields{/accent} on a sheet. Each block has a type and a label. Unless marked as a constant or using a non-variable type, a block automatically becomes a **variable** that flows can read and modify.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  A sheet with several blocks of different types: text, number, select, boolean, showing their labels and current values.
</div>

---

## Block types

Storyarn supports {accent}10 block types{/accent}:

| Type | Description | Variable? | Value example |
|------|-------------|-----------|---------------|
| **Text** | Single-line or short text input with optional placeholder | Yes | `"Jaime"` |
| **Rich Text** | Formatted text with bold, italic, lists, links | Yes | `"<p>A brave warrior...</p>"` |
| **Number** | Numeric input with optional min, max, and step constraints | Yes | `42` |
| **Boolean** | Toggle switch. Supports two-state (true/false) or tri-state (true/false/nil) modes | Yes | `true` |
| **Select** | Single choice from a defined list of options | Yes | `"warrior"` |
| **Multi Select** | Multiple choices from a defined list (tags) | Yes | `["fire", "ice"]` |
| **Date** | Date picker | Yes | `"2024-03-15"` |
| **Table** | Spreadsheet grid with typed columns and named rows | Yes (cell-level) | See [Tables](/en/world-building/tables) |
| **Reference** | Link to another sheet or flow | **No** | -- |
| **Gallery** | Image collection from uploaded assets | **No** | -- |

Reference and gallery blocks are excluded from the variable system because they don't carry a meaningful runtime value.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  The block type selector menu showing all 10 types with their icons.
</div>

---

## Variable naming

Variables follow the pattern `{sheet_shortcut}.{variable_name}`.

The variable name is {accent}auto-generated{/accent} from the block's label: spaces become underscores, accented characters are transliterated to ASCII, and everything is lowercased.

| Label | Variable name | Full reference (on `mc.jaime`) |
|-------|---------------|-------------------------------|
| Health Points | `health_points` | `mc.jaime.health_points` |
| Clase Social | `clase_social` | `mc.jaime.clase_social` |
| Is Alive | `is_alive` | `mc.jaime.is_alive` |

You can customize the variable name after creation. If a sheet already has a variable with the same name (e.g., from inheritance), Storyarn appends a numeric suffix to keep names unique.

---

## Constants

Mark a block as {accent}constant{/accent} to exclude it from the variable system. Constants are for static data that flows never need to check or modify: character descriptions, flavor text, lore entries, reference images.

A constant block still displays on the sheet and is included in version snapshots -- it just won't appear in the variable picker when building conditions or instructions in flows.

---

## Block configuration

Each block type has its own configuration options:

- **Text** -- placeholder text.
- **Number** -- placeholder, min, max, and step values for input validation.
- **Boolean** -- two-state (true/false) or tri-state (true/false/unset) mode.
- **Select / Multi Select** -- a list of options, each with a key and display value.
- **Table** -- collapsible display, plus column and row definitions (see [Tables](/en/world-building/tables)).
- **Reference** -- allowed target types (sheet, flow).

---

## Property scope

Every block has a {accent}scope{/accent} that controls inheritance:

- **Self** -- the block lives only on this sheet. This is the default.
- **Children** -- the block definition cascades to all descendant sheets. Each child gets an instance with the same type, label, and configuration but its own independent value.

When a parent block with "children" scope is updated (label, type, options), all non-detached child instances sync automatically. If the type changes, child values are reset to the default for the new type.

You can **detach** an inherited instance to stop it from syncing with the parent. A detached block keeps its current configuration and can be edited independently. You can **re-attach** it later to resync with the parent definition.

---

## Required blocks

Marking a block as {accent}required{/accent} flags it for completeness tracking. Required blocks that are empty will be highlighted, helping you identify incomplete sheets at a glance.

The required flag is also inherited: when a parent block with "children" scope is required, all child instances inherit that requirement.

---

## Column layout

Blocks can be arranged in a {accent}multi-column layout{/accent} using column groups. Within a group, blocks can be placed in column positions 0, 1, or 2, allowing up to three blocks side-by-side for more compact sheet layouts.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  A sheet with blocks arranged in a two-column layout, showing Name and Class side-by-side, with Health and Level below them.
</div>
