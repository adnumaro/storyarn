%{
  title: "Tables",
  category_label: "World Building",
  order: 3,
  description: "Spreadsheet-like grids within sheets for inventories, stat matrices, and structured lists."
}
---

Tables are a block type that embeds a {accent}spreadsheet grid{/accent} inside a sheet. Each table has typed columns, named rows, and cell-level variable references. Use them for inventories, stat tables, relationship matrices, skill trees, or shop catalogs.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  A table block showing an inventory grid with columns for Item (text), Quantity (number), Equipped (boolean), and a formula column calculating weight.
</div>

---

## Structure

A table is made of:

- **Columns** -- typed fields that define the table's structure. Each column has a name, a type, and a slug (auto-generated from the name).
- **Rows** -- named records. Each row has a name and a slug. Row names should be descriptive: "Healing Potion", "Iron Sword", "Strength".
- **Cells** -- the intersection of a row and a column. Cell values are stored as a JSON map keyed by column slug.

---

## Column types

Table columns support {accent}8 types{/accent}:

| Type | Description |
|------|-------------|
| **Number** | Numeric values (default column type) |
| **Text** | Plain text (no rich text in tables) |
| **Boolean** | True/false toggle |
| **Select** | Single choice from defined options |
| **Multi Select** | Multiple choices from defined options |
| **Date** | Date value |
| **Reference** | Link to a sheet or flow (not a variable) |
| **Formula** | Computed value from a math expression with bindings |

These mirror the regular block types, except tables use plain text instead of rich text and add the formula column type.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  The column type selector showing all 8 available types.
</div>

---

## Cell-level variables

Every non-constant, non-reference cell becomes a variable using {accent}extended dot notation{/accent}:

```
{sheet_shortcut}.{table_variable}.{row_slug}.{column_slug}
```

For example, on sheet `mc.jaime` with a table block labeled "Inventory" (variable name `inventory`), a row named "Healing Potion" and a column named "Quantity":

```
mc.jaime.inventory.healing_potion.quantity
```

This means flows can read and modify individual cells. A condition can check "Does `mc.jaime.inventory.healing_potion.quantity` > 0?" and an instruction can set it to a new value.

Slugs are auto-generated from names using underscore notation, just like block variable names.

---

## Formula columns

Formula columns let you define {accent}computed values{/accent} using math expressions. Each cell in a formula column stores its own expression and variable bindings.

### Syntax

Formulas support standard math operations and functions:

| Category | Syntax |
|----------|--------|
| **Operators** | `+`, `-`, `*`, `/`, `^` (power) |
| **Unary minus** | `-a` |
| **Parentheses** | `(a + b) * c` |
| **Literals** | `42`, `3.14` |
| **Functions** | `sqrt(x)`, `abs(x)`, `floor(x)`, `ceil(x)`, `round(x)`, `min(a, b)`, `max(a, b)` |

Expressions use single-letter or named symbols (`a`, `b`, `con_value`) that are bound to actual data sources.

### Binding types

Each symbol in a formula is bound to a data source. There are two binding types:

- **Same-row** -- references another column in the same row. For example, binding `a` to the "Base" column means `a` resolves to that row's Base value.
- **Cross-sheet variable** -- references any variable in the project by its full path. For example, binding `b` to `mc.jaime.level` pulls the character's level into the formula.

### Example

A "Modifier" formula column on a stats table with the expression `floor((a - 10) / 2)`, where `a` is bound to the same-row "Value" column:

| Stat | Value | Modifier |
|------|-------|----------|
| Strength | 16 | 3 |
| Dexterity | 12 | 1 |
| Constitution | 8 | -1 |

The modifier is recomputed whenever the bound values change.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  A formula column configuration showing the expression editor with symbol bindings: "a" bound to same-row "Value" column, and the rendered LaTeX preview of the formula.
</div>

---

## Column configuration

Columns have the same configuration options as their equivalent block types:

- **Select / Multi Select** columns get a list of options.
- **Columns can be marked as constant** -- their cells won't be exposed as variables.
- **Columns can be marked as required** -- empty cells will be flagged.

---

## Inheritance

When a table block has scope set to "children", the entire table structure (columns and rows) is {accent}copied to child sheets{/accent}. Each child gets its own table with the same columns and rows but independent cell values.

Formula bindings that reference the parent sheet are automatically rewritten to point to the child sheet. For example, if a parent sheet `main` has a formula binding to `main.combat.attack`, the child sheet `seven` gets the binding rewritten to `seven.combat.attack` (assuming the `combat` block was also inherited).

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  A parent sheet's inherited table block and a child sheet's instance of the same table, showing identical structure but different cell values.
</div>
