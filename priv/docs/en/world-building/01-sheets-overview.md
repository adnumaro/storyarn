%{
  title: "Sheets Overview",
  category_label: "World Building",
  order: 1,
  description: "Understand how sheets organize your game data into a living database."
}
---

Sheets are **structured data containers** — think database records designed for game narrative. Character profiles, item catalogs, location details, quest trackers.

---

## Shortcuts

Every sheet has a **shortcut** — a dot-notation identifier used to reference it throughout your project.

Shortcuts are auto-generated from the name but can be customized. Use prefixes to organize by domain:

- `mc.jaime` — main character
- `item.healing-potion` — an item
- `loc.tavern` — a location

---

## Organizing with folders

Sheets support a tree structure. Drag and drop to reorder, nest sheets inside folders for organization.

```
Main Characters/
├── mc.jaime
├── mc.elena
└── mc.kai
Items/
├── Weapons/
│   ├── item.iron-sword
│   └── item.fire-staff
└── Potions/
    └── item.healing-potion
```

Folders are purely organizational — they don't affect shortcuts.

---

## Versioning

Each save creates a snapshot you can review later. This lets you track how data evolves without fear of losing previous states.
