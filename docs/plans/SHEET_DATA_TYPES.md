# Sheet Data Types — Table Block

> **Goal:** Extend the Sheet block system with a structured table block type that supports professional game design workflows: attribute tables (like D&D stats, skill trees, equipment properties).
>
> **Motivation:** Games like Planescape: Torment use structured attribute systems (STR, INT, WIS, CHA, DEX, CON) shared across characters. Flat blocks can model this but lack structure, schema enforcement, and the mental model designers expect from a professional tool.
>
> **Note:** Image gallery is a separate, unrelated block type — it provides static visual references for designers (concept art, 3D references, sprites) and does not interact with the expression system or variable references. To be planned independently.
>
> **Depends on:** Expression System (Gap 5 from `COMPLEX_NARRATIVE_STRESS_TEST.md`) for DSL path resolution
>
> **Status:** Draft — needs detailed design discussion

---

## Context

### Current sheet model

```
Sheet (shortcut: "nameless_one")
├── Block "str" (number)           → nameless_one.str
├── Block "wis" (number)           → nameless_one.wis
├── Block "health" (number)        → nameless_one.health
├── Block "quest_started" (boolean)→ nameless_one.quest_started
└── ... all flat, no grouping
```

### Problems with flat blocks for structured data

1. **No structure** — stats, quest flags, and misc variables are all mixed together
2. **No shared schema** — 50 characters each need the same 6 stat blocks created manually
3. **No enforcement** — nothing guarantees "Annah" has the same attributes as "Morte"
4. **Poor mental model** — designers and programmers think in terms of "character attributes" as a group, not individual variables

### What competitors do

- **articy:draft** — Templates define property groups. Entities inherit from templates. Properties are typed and grouped.
- **Notion** — Databases define columns (schema). Each page/row inherits the schema. Cells are typed per column.

### Existing Storyarn features to build on

- **Sheet inheritance** — sheets can inherit from parent sheets with default values per block
- **Block types** — number, text, select, boolean (already typed)
- **Variable references** — `sheet_shortcut.variable_name` (2-level path)

---

## Proposed Features

### 1. Table Block

A new block type that represents a structured table within a sheet.

**Concept:**

```
Sheet "nameless_one" (inherits from "character_template")
├── Block "name" (text, constant)
├── Table "attributes"                    ← NEW
│   ├── Column "value" (number, default: 10)
│   ├── Row "strength"     → value: 18
│   ├── Row "dexterity"    → value: 12
│   ├── Row "constitution" → value: 14
│   ├── Row "intelligence" → value: 9
│   ├── Row "wisdom"       → value: 15
│   └── Row "charisma"     → value: 16
├── Block "health" (number)
└── Block "quest_started" (boolean)
```

**Variable reference:** `nameless_one.attributes.wisdom` → resolves to the `value` column of the `wisdom` row.

If the table has multiple columns: `nameless_one.attributes.wisdom.value`, `nameless_one.attributes.wisdom.modifier`.

**DSL integration (Expression System):**

```
nameless_one.attributes.wisdom >= 15
nameless_one.attributes.charisma += 1
```

The Lezer grammar from Gap 5 needs to support 3+ level paths. If designed with extensible path resolution, this is adding one more segment.

**Schema inheritance:**

```
Sheet "character_template"
└── Table "attributes" (columns: value(number))
    ├── Row "strength"     → value: 10 (default)
    ├── Row "dexterity"    → value: 10
    └── ...

Sheet "nameless_one" (inherits: character_template)
└── Table "attributes" (inherited, rows + columns from parent)
    ├── Row "strength"     → value: 18 (overridden)
    ├── Row "dexterity"    → value: 12 (overridden)
    └── ...
```

Child sheets inherit the table schema (columns + rows) from the parent. Values can be overridden per instance.

---

## Open Questions

1. **Single vs multi-column tables?** Single column (just rows with one value) is simpler and covers 90% of cases (stat lists). Multi-column (rows × columns, like a spreadsheet) is more powerful but significantly more complex UI and data model.

2. **Path depth in DSL:** If single-column: `sheet.table.row` (3 levels). If multi-column: `sheet.table.row.column` (4 levels). How deep should the expression parser support?

3. **Table schema definition:** Where is the schema defined — in the parent template sheet? Can standalone sheets (no parent) have tables?

4. **Row ordering:** Are rows ordered? Can users reorder? Does order matter for the expression system?

5. **UI for table editing:** Inline table in the sheet editor? Expandable block? Separate table view?

6. **Data model:** New DB table for table rows/cells, or store as JSONB within the block?

---

## Effort Estimate

**High.** This touches:
- Sheet domain model (new block type, table schema, row/cell storage)
- Sheet UI (table editor component)
- Variable resolution (3+ level paths)
- Expression system DSL (Lezer grammar, parser, autocomplete)
- Sheet inheritance (table schema inheritance)
- Evaluator engine (resolve table cell values)

---

## Implementation Notes

- Design the Expression System (Gap 5) with extensible path resolution from the start, so adding table paths later is natural
- The import script for the stress test uses flat blocks — no blocker
- This plan should be detailed after the stress test plan's Phase A is complete
