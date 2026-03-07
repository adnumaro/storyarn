%{
  title: "Blocks & Variables",
  category_label: "World Building",
  order: 2,
  description: "How blocks define your data structure and become variables for flows."
}
---

Blocks are the **fields** on a sheet. Each block has a type and a label. Unless marked as constant, it automatically becomes a **variable** that flows can read and modify.

---

## Block types

- **Text** and **Rich Text** — short or formatted text fields
- **Number** — numeric values with optional min/max
- **Boolean** — true/false toggles (is_alive, has_key)
- **Select** — single choice from a list of options
- **Multi Select** — multiple choices from a list
- **Date** — date values
- **Table** — a spreadsheet grid within the sheet
- **Formula** — computed from other variables (read-only)
- **Reference** — link to another sheet (not a variable)

---

## Variable naming

Variables follow the pattern `{sheet_shortcut}.{block_variable_name}`.

The variable name is auto-generated from the label: "Health Points" becomes `health_points`. So a Health block on `mc.jaime` becomes `mc.jaime.health`.

---

## Constants

Mark a block as **constant** to exclude it from the variable system. Use constants for character descriptions, flavor text, lore — anything flows never need to check.

---

## Property inheritance

Blocks can have different scopes:

- **Local** — only on this sheet
- **Inherited** — passed down to child sheets, with overridable values
- **Global** — available to all sheets in the project

This lets you create base templates. A "Character Base" sheet with inherited blocks (health, level, faction) passes them to all child sheets automatically.
