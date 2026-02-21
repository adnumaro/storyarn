# Phase 5 — Expression System UI Integration

> **Status:** Pending
> **Depends on:** [Phase 4 — Variable Generation](04_VARIABLE_GENERATION.md)
> **Next:** [Phase 7 — Variable Reference Tracker](07_REFERENCE_TRACKER.md)

> **Problem:** Table variables exist in the backend but the expression editor, condition builders, and instruction builders don't know about them. Users can't reference table variables in flow logic.
>
> **Goal:** 4-level paths work in the code editor. Autocomplete shows table variables progressively. Condition/instruction builders show table variables grouped under table names.
>
> **Principle:** JS-heavy phase. Parser, autocomplete, and builder UI changes.

---

## AI Implementation Protocol

> **MANDATORY:** Follow this protocol for EVERY task. Do not skip steps.

### Per-Task Checklist

```
□ Read all files the task touches BEFORE writing code
□ Write tests FIRST or alongside implementation (not after)
□ Run `just quality` after completing the task
□ Verify: no warnings, no test failures, no credo issues, no biome issues
□ If any check fails: fix before moving to the next task
```

### Per-Phase Audit

After completing ALL tasks in a phase, run a full audit:

```
□ Security: no SQL injection, no unescaped user input, no mass assignment
□ Dead code: no unused functions, no unreachable branches, no leftover debug code
□ Bad practices: no God modules, no deep nesting, no magic strings
□ Componentization: components are focused, reusable, no monolith templates
□ Duplication: no copy-paste code, shared logic extracted
□ Potential bugs: nil handling, race conditions, missing error branches
□ SOLID: single responsibility, open for extension, dependency inversion via contexts
□ KISS: simplest solution that works, no premature abstractions
□ YAGNI: nothing built "for later", only what this phase needs
```

### Quality Command

```bash
just quality   # runs: biome check --write, mix credo --strict, mix test, vitest
```

---

## Design Specs for This Phase

### Parser behavior

The parser extracts all path segments as an array, then matches against the known variable list (already available in the hook's dataset). If it matches a table variable (has `table_name`), it's parsed as 4 levels. If it matches a regular variable, it's parsed as 2 levels. Fallback to current behavior for unknown paths.

### Autocomplete behavior

Progressive autocomplete by level: `sheet.` → shows regular variables + table names (with table icon `table-2`, arrow `→` indicating sub-levels) → `sheet.table.` → shows rows → `sheet.table.row.` → shows non-constant columns.

### Condition & instruction builder behavior

Table variables appear flattened in the variable selector with `variable_name: "attributes.strength.value"`, grouped visually under the table name as a subheader. No extra selectors — keeps the existing Sheet → Variable → Operator → Value flow.

---

## Key Files

| File                                                        | Action                                                     |
|-------------------------------------------------------------|------------------------------------------------------------|
| `assets/js/expression_editor/parser.js`                     | Modified — `extractVariableRef` handles 4-level paths      |
| `assets/js/expression_editor/autocomplete.js`               | Modified — progressive multi-level suggestions             |
| `assets/js/condition_builder/condition_builder_core.js`     | Modified — grouped variable display in combobox            |
| `assets/js/condition_builder/condition_rule_row.js`         | Modified — may need grouped dropdown rendering             |
| `assets/js/instruction_builder/instruction_builder_core.js` | Modified — grouped variable display in combobox            |
| `assets/js/instruction_builder/assignment_row.js`           | Modified — may need grouped dropdown rendering             |
| `assets/js/screenplay/builders/utils.js`                    | Modified — `groupVariablesBySheet` includes table grouping |
| `assets/js/instruction_builder/sentence_templates.js`       | Modified — variable slot supports composite names          |

---

## Mockup — Variable Autocomplete in Expression Editor

Progressive autocomplete when typing in the code expression editor.

```
STATE 1: User types "nameless_one."
┌─────────────────────────────────────────┐
│ nameless_one.█                          │
│                                         │
│ ┌─ autocomplete dropdown ─────────────┐ │
│ │  health           number            │ │
│ │  quest_started    boolean           │ │
│ │  class            select            │ │
│ │  ─────────────────────────────────  │ │
│ │  [⊞] attributes   table  →          │ │ ← table-2 icon, → = has sub-levels
│ │  [⊞] inventory    table  →          │ │
│ └─────────────────────────────────────┘ │
└─────────────────────────────────────────┘

STATE 2: User selects "attributes" → appends "attributes."
┌─────────────────────────────────────────┐
│ nameless_one.attributes.█               │
│                                         │
│ ┌─ autocomplete dropdown ─────────────┐ │
│ │  strength                           │ │ ← row names
│ │  wisdom                             │ │
│ │  charisma                           │ │
│ │  dexterity                          │ │
│ │  constitution                       │ │
│ │  intelligence                       │ │
│ └─────────────────────────────────────┘ │
└─────────────────────────────────────────┘

STATE 3: User selects "strength" → appends "strength."
┌─────────────────────────────────────────┐
│ nameless_one.attributes.strength.█      │
│                                         │
│ ┌─ autocomplete dropdown ─────────────┐ │
│ │  value            number            │ │ ← non-constant column names
│ │  max              number            │ │
│ └─────────────────────────────────────┘ │
│                                         │
│ (constant columns like "description"    │
│  do NOT appear — they're not variables) │
└─────────────────────────────────────────┘

STATE 4: User selects "value" → complete path
┌─────────────────────────────────────────┐
│ nameless_one.attributes.strength.value  │
│ ↑ complete 4-level variable reference   │
└─────────────────────────────────────────┘
```

---

## Mockup — Condition Builder with Table Variables

How table variables appear in the visual condition builder.

```
┌─ Condition Builder ────────────────────────────────────────────────────┐
│                                                                        │
│  Match [ALL ▾] of the following:                                       │
│                                                                        │
│  ┌─ Rule 1 ───────────────────────────────────────────────────────┐    │
│  │                                                                │    │
│  │  Sheet:    [nameless_one    ▾]                                 │    │
│  │                                                                │    │
│  │  Variable: [                ▾]  ← grouped dropdown:            │    │
│  │             ┌──────────────────────────────────────────┐       │    │
│  │             │  health              number              │       │    │
│  │             │  quest_started       boolean             │       │    │
│  │             │  class               select              │       │    │
│  │             │  ──────────────────────────────────────  │       │    │
│  │             │  ATTRIBUTES (table)   ← subheader        │       │    │
│  │             │    attributes.strength.value    number   │       │    │
│  │             │    attributes.strength.max      number   │       │    │
│  │             │    attributes.wisdom.value      number   │       │    │
│  │             │    attributes.wisdom.max        number   │       │    │
│  │             │    attributes.charisma.value    number   │       │    │
│  │             │  ──────────────────────────────────────  │       │    │
│  │             │  INVENTORY (table)    ← subheader        │       │    │
│  │             │    inventory.sword.quantity     number   │       │    │
│  │             │    inventory.sword.equipped     boolean  │       │    │
│  │             └──────────────────────────────────────────┘       │    │
│  │                                                                │    │
│  │  Operator: [greater than ▾]                                    │    │
│  │  Value:    [15            ]                                    │    │
│  │                                                                │    │
│  └────────────────────────────────────────────────────────────────┘    │
│                                                                        │
│  [+ Add rule]                                                          │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

**Key:** Table variables appear **flattened** with composite `variable_name` (e.g., `attributes.strength.value`), grouped under a **table name subheader** (`ATTRIBUTES`). No extra dropdowns — same Sheet → Variable → Operator → Value flow.

---

## Mockup — Instruction Builder with Table Variables

Same grouping pattern in the sentence-style instruction builder.

```
┌─ Instruction Builder ──────────────────────────────────────────────────┐
│                                                                        │
│  ┌─ Assignment 1 ─────────────────────────────────────────────────┐    │
│  │                                                                │    │
│  │  Set  [nameless_one ▾] · [attributes.strength.value ▾] to [25] │    │
│  │   ↑    ↑ sheet           ↑ variable (composite)        ↑ value │    │
│  │  verb  combobox          combobox (same grouped         literal│    │
│  │                          dropdown as condition)                │    │
│  │                                                                │    │
│  └────────────────────────────────────────────────────────────────┘    │
│                                                                        │
│  ┌─ Assignment 2 ─────────────────────────────────────────────────┐    │
│  │                                                                │    │
│  │  Add  [nameless_one ▾] · [attributes.wisdom.value ▾]  +  [5]   │    │
│  │                                                                │    │
│  └────────────────────────────────────────────────────────────────┘    │
│                                                                        │
│  [+ Add assignment]                                                    │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

---

## Task 5.1 — Parser: `extractVariableRef` for Multi-Level Paths

Update the parser to correctly extract sheet and variable from 4-level paths.

**Current behavior:**
```javascript
// "mc.jaime.attributes.strength.value"
// → {sheet: "mc.jaime.attributes.strength", variable: "value"}  ← WRONG
```

**New behavior:** Match against known variable list to determine the split point.

```javascript
function extractVariableRef(node, text, knownVariables) {
  const ids = [...]; // all Identifier parts
  if (ids.length < 2) return null;

  const fullPath = ids.join(".");

  // Try matching against known variables (longest match first)
  for (const v of knownVariables) {
    const key = `${v.sheet_shortcut}.${v.variable_name}`;
    if (key === fullPath) {
      return {
        sheet: v.sheet_shortcut,
        variable: v.variable_name,
        table_name: v.table_name || null,
        row_name: v.row_name || null,
        column_name: v.column_name || null,
        from: node.from,
        to: node.to,
      };
    }
  }

  // Fallback: last part = variable, rest = sheet (backward compat)
  return {
    sheet: ids.slice(0, -1).join("."),
    variable: ids[ids.length - 1],
    from: node.from,
    to: node.to,
  };
}
```

**Requires:** `knownVariables` array passed to the parser from the hook's dataset (already available as `project_variables`).

**Internal call sites that need `knownVariables` threaded:**
1. `extractConditionRefs` — calls `extractVariableRef` for condition expressions
2. `extractInstructionRefs` — calls `extractVariableRef` for instruction assignments
3. `highlightVariables` — calls `extractVariableRef` for syntax highlighting
4. `validateExpression` — calls `extractVariableRef` for validation checks

**Public entry points (where `knownVariables` enters the call chain):**
1. `parseExpression(text, knownVariables)` — main parser entry point
2. `getCompletions(context, knownVariables)` — autocomplete entry point

**Tests (vitest):**
- 2-level path → `{sheet: "mc.jaime", variable: "health"}`
- 4-level path with known var → `{sheet: "mc.jaime", variable: "attributes.strength.value", table_name: "attributes"}`
- Unknown path → fallback behavior
- Sheet with dots in shortcut (`mc.jaime`) + regular variable → correct split

---

## Task 5.2 — Autocomplete: Progressive Multi-Level

Update autocomplete to show table names as intermediate completions. See Autocomplete mockup above.

**Current:** After typing `sheet.` → show all variables flat.

**New behavior:**
1. After `sheet.` → show regular variables + table names (with `table-2` icon and `→` arrow indicator)
2. After `sheet.table.` → show row names
3. After `sheet.table.row.` → show non-constant column names
4. Selecting a column name completes the full 4-level path

**Implementation:** Build a trie-like structure from `knownVariables` grouped by path levels. At each cursor position, determine the current depth and filter suggestions.

**`completeVariable` pseudocode for level determination:**

```javascript
function completeVariable(prefix, knownVariables) {
  const parts = prefix.split(".");
  const depth = parts.length; // 1 = typing sheet, 2 = after sheet., 3 = after table., 4 = after row.

  if (depth === 2) {
    // After "sheet." — show regular vars + table names
    const sheet = parts[0];
    const sheetVars = knownVariables.filter(v => v.sheet_shortcut === sheet);
    const regularVars = sheetVars.filter(v => !v.table_name);
    const tableNames = [...new Set(sheetVars.filter(v => v.table_name).map(v => v.table_name))];
    return [
      ...regularVars.map(v => ({ label: v.variable_name, type: v.block_type, complete: true })),
      ...tableNames.map(t => ({ label: t, type: "table", complete: false, hasSubLevels: true })),
    ];
  }

  if (depth === 3) {
    // After "sheet.table." — show row names
    const [sheet, table] = parts;
    const tableVars = knownVariables.filter(v => v.sheet_shortcut === sheet && v.table_name === table);
    const rowNames = [...new Set(tableVars.map(v => v.row_name))];
    return rowNames.map(r => ({ label: r, complete: false, hasSubLevels: true }));
  }

  if (depth === 4) {
    // After "sheet.table.row." — show non-constant column names
    const [sheet, table, row] = parts;
    const rowVars = knownVariables.filter(v =>
      v.sheet_shortcut === sheet && v.table_name === table && v.row_name === row
    );
    return rowVars.map(v => ({ label: v.column_name, type: v.block_type, complete: true }));
  }

  return [];
}
```

**Visual indicators for table items in autocomplete dropdown:**
- Table names: `[⊞]` (table-2 icon) + name + "table" type label + `→` arrow
- Row names: plain text (no icon, no type label, `→` arrow)
- Column names: name + type label (no arrow — final level)

**Tests (vitest):**
- After `mc.` → shows `health`, `attributes` (table icon)
- After `mc.attributes.` → shows `strength`, `wisdom`, etc.
- After `mc.attributes.strength.` → shows `value` (not `description` if constant)
- Regular variable completion still works
- Empty table (no rows/columns) doesn't crash autocomplete

---

## Task 5.3 — Variable Grouping in Builders

Update `groupVariablesBySheet` to include table sub-groups. See Condition Builder and Instruction Builder mockups above.

**`utils.js` change:**

```javascript
export function groupVariablesBySheet(variables) {
  const groups = {};
  for (const v of variables) {
    const key = v.sheet_shortcut;
    if (!groups[key]) groups[key] = { shortcut: key, name: v.sheet_name, vars: [], tables: {} };

    if (v.table_name) {
      if (!groups[key].tables[v.table_name]) {
        groups[key].tables[v.table_name] = [];
      }
      groups[key].tables[v.table_name].push(v);
    } else {
      groups[key].vars.push(v);
    }
  }
  return Object.values(groups);
}
```

**Consumers of `groupVariablesBySheet`** — the files to update:
- `assets/js/condition_builder/condition_builder_core.js` — condition rule variable combobox
- `assets/js/instruction_builder/instruction_builder_core.js` — instruction assignment variable combobox

**Condition builder (`condition_builder_core.js`):** Variable combobox shows:
- Regular variables as before
- Separator line
- Table subheader (e.g., "ATTRIBUTES (table)") → flattened table variables underneath (e.g., `attributes.strength.value   number`)

**Instruction builder (`instruction_builder_core.js`):** Same grouping pattern.

**Sentence templates:** The `variable` slot already handles the full `variable_name` string. Since table variables have `variable_name: "attributes.strength.value"`, the sentence reads: "Set mc.jaime · attributes.strength.value to 10" — correct without template changes.

**Tests (vitest):**
- Variables grouped correctly: regular vars flat, table vars under table name
- Combobox renders table subheaders
- Selecting a table variable populates `variable` field with composite name

---

## Task 5.4 — Gettext (Phase 5)

No new gettext strings needed — this phase is JS-only and the builders use existing patterns.

Verify existing translations still render correctly with table variable names.

---

## Phase 5 — Post-phase Audit

```
□ Run `just quality` — all green (including vitest)
□ Security: no XSS in variable name display (combobox escapes by default)
□ Dead code: no unused autocomplete branches
□ Componentization: grouping logic in utils.js, not duplicated in each builder
□ Duplication: parser fallback shares code with original logic
□ Potential bugs: empty table (no rows/columns) doesn't crash autocomplete
□ SOLID: parser extracts, autocomplete suggests, builders render — each has one job
□ KISS: trie-like completion vs. full prefix tree — simpler wins
□ YAGNI: no fuzzy search for table variables, no drag-to-reorder in autocomplete
```

---

[← Phase 4 — Variable Generation](04_VARIABLE_GENERATION.md) | [Phase 7 — Variable Reference Tracker →](07_REFERENCE_TRACKER.md)
