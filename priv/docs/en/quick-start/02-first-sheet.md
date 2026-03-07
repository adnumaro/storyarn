%{
  title: "Your First Sheet",
  category_label: "Quick Start",
  order: 2,
  description: "Create a character sheet and understand how variables work."
}
---

Sheets are the data backbone of your project. Every field you add to a sheet can become a {accent}variable{/accent} that your flows read and modify at runtime.

## Create the sheet

Open your project and select **Sheets** in the sidebar. Click the **New Sheet** button at the top of the sheet tree.

A new sheet is created with a default name. Click on the title to rename it -- for example, "Jaime". The {accent}shortcut{/accent} (shown below the name) auto-generates from the sheet name. You can edit it manually -- for a character, something like `mc.jaime` works well because it creates a readable namespace for all variables on this sheet.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  A new sheet with the title "Jaime" and the shortcut "mc.jaime" visible below the name
</div>

## Add blocks

Click the **+** button at the bottom of the sheet to open the block menu. Blocks are organized into two categories:

**Basic Blocks** -- Text, Rich Text, Number, Select, Multi Select, Date, Boolean, Reference

**Structured Data** -- Table, Gallery

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  The block type menu showing Basic Blocks and Structured Data categories
</div>

Try adding these blocks to your character sheet:

1. Choose **Number** and label it "Health". Set the default value to `100`. This creates the variable `mc.jaime.health`.

2. Choose **Select** and label it "Class". Add options like Warrior, Mage, and Rogue using the block's config popover. This creates `mc.jaime.class`.

3. Choose **Boolean** and label it "Is Alive". Toggle it on. This creates `mc.jaime.is_alive`.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  The sheet with Health (number), Class (select), and Is Alive (boolean) blocks filled in
</div>

## Constants vs. variables

By default, every block becomes a variable -- except for {accent}Reference{/accent} and {accent}Gallery{/accent} blocks, which never expose variables.

If you want a block to hold display-only data that flows cannot read, mark it as a **constant** in the block's config popover. Constants are useful for labels, descriptions, or lore text that does not need to participate in game logic.

## How variables work

Every non-constant block becomes a variable with the format `{sheet_shortcut}.{variable_name}`:

| Block | Variable | Type |
|---|---|---|
| Health | `mc.jaime.health` | number |
| Class | `mc.jaime.class` | select |
| Is Alive | `mc.jaime.is_alive` | boolean |

The {accent}variable name{/accent} auto-generates from the block label (lowercased, spaces become underscores). You can customize it in the block's advanced config.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  The block config popover showing the variable name field and the "is constant" toggle
</div>

In the next guide, you will use `mc.jaime.health` to create branching dialogue in a flow.
