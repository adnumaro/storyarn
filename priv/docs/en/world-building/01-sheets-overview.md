%{
  title: "Sheets Overview",
  category_label: "World Building",
  order: 1,
  description: "Understand how sheets organize your game data into a living database."
}
---

Sheets are {accent}structured data containers{/accent} for your project's world data. Character profiles, item catalogs, location details, faction rosters -- anything you need to define and track across your narrative.

Each sheet holds a set of **blocks** (typed fields like text, number, select, boolean) that define its structure. Blocks that aren't marked as constants automatically become **variables** that flows can read and modify at runtime.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  A character sheet showing blocks like Name (text), Health (number), Class (select), and a banner image.
</div>

---

## Shortcuts

Every sheet has a {accent}shortcut{/accent} -- a dot-notation identifier that flows, conditions, and instructions use to reference it.

Shortcuts are auto-generated from the sheet name but can be edited manually. The format is lowercase alphanumeric with dots and hyphens (e.g., `mc.jaime`). Use prefixes to organize by domain:

- `mc.jaime` -- main character
- `item.healing-potion` -- an item
- `loc.tavern` -- a location
- `faction.guild` -- a faction

Shortcuts must be unique within a project. If a sheet already has variables referenced in flows, renaming it won't change the shortcut to avoid breaking references.

---

## Variable references

Blocks on a sheet become variables with the pattern:

```
{sheet_shortcut}.{variable_name}
```

The variable name is auto-generated from the block label using underscore notation. For example, a block labeled "Health Points" on sheet `mc.jaime` becomes:

```
mc.jaime.health_points
```

These references are what flows use in conditions ("Is `mc.jaime.health_points` greater than 50?") and instructions ("Set `mc.jaime.health_points` to 100").

---

## Organizing with folders

Sheets support a {accent}tree structure{/accent}. Drag and drop to reorder, nest sheets inside other sheets for organization.

```
Main Characters/
  mc.jaime
  mc.elena
  mc.kai
Items/
  Weapons/
    item.iron-sword
    item.fire-staff
  Potions/
    item.healing-potion
```

Any sheet can have both children and its own blocks. Parent sheets can also define inherited properties that cascade to their children (see [Property Inheritance](#property-inheritance) below).

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  The sidebar sheet tree showing nested sheets with drag handles and folder-like hierarchy.
</div>

---

## Property inheritance

Blocks have a {accent}scope{/accent} setting that controls whether they stay local or cascade to child sheets:

- **Self** (default) -- the block exists only on this sheet.
- **Children** -- the block definition propagates to all descendant sheets. Each child gets its own instance with local values but the same type, label, and configuration.

This lets you create template-like parent sheets. A "Character Base" sheet with children-scoped blocks (health, level, faction) automatically gives every child sheet those same fields, each with their own independent values.

Child instances stay synced with the parent definition: if you change the label, type, or options on the parent block, all non-detached instances update. You can **detach** an instance to make it fully independent, or **re-attach** it to sync again.

Sheets can also **hide** specific inherited blocks, preventing them from cascading further down to their own children.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  A parent sheet with scope set to "Children" on a Health block, and a child sheet showing the inherited Health block with its own local value.
</div>

---

## Sheet customization

Each sheet supports additional metadata:

- **Color** -- a hex color for visual identification in the sidebar and references.
- **Avatar** -- an uploaded image shown as the sheet's icon.
- **Banner** -- a header image displayed at the top of the sheet.
- **Description** -- rich text for notes and annotations (not exposed as a variable).

---

## Versioning

Storyarn tracks the history of each sheet through {accent}version snapshots{/accent}.

- **Auto-versioning** -- a snapshot is automatically created when you edit a sheet, with a minimum interval of 5 minutes between snapshots to avoid noise.
- **Manual snapshots** -- you can create a named version with a title and description at any time to mark a meaningful milestone.
- **Restore** -- roll back to any previous version. This restores the sheet's name, shortcut, avatar, banner, and all block types, configurations, and values.

Each version records who made the change and generates a summary of what changed (blocks added, removed, or modified).

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  The version history panel showing a list of snapshots with timestamps, change summaries, and a restore button.
</div>
