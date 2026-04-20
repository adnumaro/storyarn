# Tables as Rule Engine — Future Roadmap

**Status:** vision doc, 2026-04-20. Not committed to a timeline. Serves as a backlog for elevating the table block from "data grid with simple formulas" to a full spreadsheet-style rule engine suitable for RPG-caliber mechanics (D&D 5e, CRPG stat systems, roguelike progression curves).

## Why this matters (product positioning)

After competitor verification (Articy Draft X 4.3.9, Yarn Spinner 3.0+, Ink, Pixel Crushers Dialogue System, Arcweave, Naninovel, Dialogic, StoryFlow, NarrativeFlow — April 2026), the defensible differentiator is:

> **No narrative design tool combines arbitrary user-defined tables with spreadsheet-style reactive formula columns.** Smart Variables (Yarn Spinner) are scalar; Templates (Articy) and Lua tables (Pixel Crushers) are imperative.

The current implementation already has the hard part: tables are first-class, every non-constant cell is a reactive variable, formulas recompute via Kahn's topological sort, cross-sheet bindings work end-to-end. What's missing is the authoring power that turns this from "cell math" into a rule engine.

## What's already in place (April 2026)

- Table block with row/column schema, 8 column types (`number`, `text`, `boolean`, `select`, `multi_select`, `date`, `reference`, `formula`).
- Per-column `is_constant` toggle (distinguishes balance tables from mutable state).
- Per-column constraints in schema (min/max for numbers, tri-state for boolean, max_options for multi_select). **Editor UI for constraints is missing.**
- Formula engine: `+ - * / ^`, functions `sqrt abs floor ceil round min max`, numeric only.
- Bindings: `same_row` + `variable` (any cross-sheet / cross-table ref by fully-qualified key). **The ref is hardcoded at authoring time — no dynamic row selection.**
- Cross-sheet formula binding picker in the formula side panel (`FormulaBindingSelect.vue` + `formula_helpers.ex:search_binding_variables`) surfaces every variable in the project with server-side pagination.
- Inheritance with binding rewrite when a table travels to a child sheet (`FormulaBindingRewriter`).
- Runtime: table cells behave as variables in flow conditions and instructions; formulas recompute after every mutation.

## Concrete gaps, prioritized

### Tier 1 — Quick wins (days each, unblock the most common complaints)

| #   | Feature                                              | Why                                                                                                                                                       | Where it lives                                                                                                       |
| --- | ---------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| 1   | **`if(cond, a, b)` in formula engine**               | Conditional modifiers (`if equipped('sword') then dmg + 2 else dmg`). Today this has to live in flow instruction nodes, forcing authors out of the table. | `lib/storyarn/shared/formula_engine.ex` — add ternary-like function, needs boolean operand support.                  |
| 2   | **Booleans and strings as formula operands**         | `is_alive && hp > 0`, `name ++ " the Brave"`. Today formulas coerce everything to number (missing operand = 0).                                           | `FormulaEngine` tokenizer + evaluator + `FormulaResolver.resolve_bindings` (stop `parse_to_number` for non-numeric). |
| 3   | **Dice functions: `d(sides)`, `dice(count, sides)`** | D&D credibility. Random but deterministic per debug step (seed via `state.step_count`?).                                                                  | `FormulaEngine` `@known_functions`.                                                                                  |
| 4   | **Column constraints editor UI**                     | Schema supports min/max/step on number columns; authors can't edit them today.                                                                            | `assets/app/modules/sheets/components/blocks/table/table-config.ts` + per-column config sidebar.                     |

### Tier 2 — Strategic differentiator (weeks)

| #   | Feature                                                         | Why                                                                                                                                                                                                       | Where                                                                                                  |
| --- | --------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| 5   | **Dynamic lookup: `lookup(table, key, column)`**                | The real gap. Level-up curves (`hp_max = base + lookup(level_table, current_level, "hp_bonus")`), stat-by-class tables, XP thresholds. Row is selected at evaluation time from a variable, not hardcoded. | New built-in in `FormulaEngine`; needs to call back into evaluator state to resolve by key.            |
| 6   | **Typed cross-table references with integrity**                 | `character.equipped_weapon` points to a row in `weapons` table; `damage = strength + equipped_weapon.damage_bonus` works via dot notation.                                                                | New column subtype extending `reference`; resolver extension; FormulaEngine needs dot access.          |
| 7   | **Per-row metadata: tags, `visible_if`, `available_if`**        | Skill prerequisites (`level >= 3`), class-locked items, conditional rows.                                                                                                                                 | New `TableRow` fields (`tags: [string]`, `visible_if: string`); runtime filter in variable extraction. |
| 8   | **Aggregations: `sum`, `count`, `avg`, `filter` over a column** | `total_weight = sum(inventory.items, "weight")`. Enables derived stats from collection.                                                                                                                   | `FormulaEngine` functions; requires "row collection" as a formula value type.                          |

### Tier 3 — Articy-level polish (when Tier 1/2 are in real use)

| #   | Feature                                     | Why                                                                                                                                                           | Where                                                     |
| --- | ------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------- |
| 9   | **Feature mixins (reusable column groups)** | Articy's killer pattern. Define "CombatStats" once (hp/mp/str/dex) and attach to Character/Enemy/NPC. Avoids copy-paste of stat definitions across templates. | New `ColumnGroup` schema + UI to attach groups to tables. |
| 10  | **Table presets / templates**               | Starter templates for D&D 5e ability scores, XP table by level, common equipment schemas. Ships with product to shortcut authoring.                           | New `TablePreset` domain + gallery UI.                    |
| 11  | **Runtime SDK for Unity / Godot**           | Designers ship the same typed data model to the engine. Codegen typed classes from table schemas.                                                             | Separate repo / plugin.                                   |

### Tier 4 — Maybe never (document the edges)

- Set-algebra lists (Ink's unique feature — `inventory ? sword`). Multi-select partially covers this today.
- Excel-style cell ranges (`sum(B2:B10)`). Overkill for narrative use cases.
- Custom user-defined functions in-table. Would slip into "programming language" territory; reject by design.

## Non-goals

- **Don't turn tables into a scripting language.** The power of "rules are data" comes from keeping formulas declarative. Lua/JS escape hatches (ChatMapper, SugarCube pattern) trade authoring accessibility for power. Storyarn should not follow that path.
- **Don't collapse constants and variables.** Balance tables (XP curves, item stats) should stay read-only at runtime; player/world state stays mutable. Keep `is_constant` structural, not advisory.

## Pitch (the one-liner, post-verification)

> "Spreadsheet-power rule engine inside a narrative design tool. Every table column can be a reactive formula. Variables, constants, and computed fields are the same primitive. Designers express D&D-level mechanics without leaving the authoring UI."

## Primary sources for the competitive landscape

- Articy: articy.com/help/adx/RecentChanges.html, articy.com/help/adx/Scripting_in_articy.html, articy.com/help/adx/Templates_Features.html (no reactive formulas, Boolean/Integer/String vars only — verified 2026-04-20).
- Yarn Spinner: docs.yarnspinner.dev/write-yarn-scripts/scripting-fundamentals/smart-variables (scalar reactive, no table context — verified 2026-04-20).
- Pixel Crushers DS: pixelcrushers.com/dialogue_system/manual2x/html/logic_and_lua.html (fixed-schema tables, imperative Lua).
- Ink: github.com/inkle/ink/blob/master/Documentation/WritingWithInk.md (thin by design; last release 1.2.0 June 2022).
- Arcweave: docs.arcweave.com/project-items/attributes (no numeric attribute type).
- Dialogic 2, Naninovel, StoryFlow, NarrativeFlow — verified to have scalar vars only, no reactive formula columns.
