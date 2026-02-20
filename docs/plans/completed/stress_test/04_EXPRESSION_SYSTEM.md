# 04 -- Expression System: Code Editor + Visual Builder

| Field           | Value                                                                                                                          |
|-----------------|--------------------------------------------------------------------------------------------------------------------------------|
| Gap Reference   | Gap 5 from `COMPLEX_NARRATIVE_STRESS_TEST.md`                                                                                  |
| Priority        | HIGH                                                                                                                           |
| Effort          | High                                                                                                                           |
| Dependencies    | Subtask 10 (response instruction backend) depends on Gap 4 (Document 03) for the full editor UI. Subtasks 1-7 are independent. |
| Previous        | [`03_DIALOGUE_UX.md`](./03_DIALOGUE_UX.md)                                                                                     |
| Next            | [`05_FLOW_TAGS.md`](05_FLOW_TAGS.md)                                                                                         |

---

## Context and Current State

### Instruction system

**Domain module:** `/lib/storyarn/flows/instruction.ex`

Assignment structure:
```elixir
%{
  "id" => "assign_12345",
  "sheet" => "mc.jaime",         # sheet shortcut
  "variable" => "health",        # block/variable name
  "operator" => "add",           # set, add, subtract, set_true, set_false, toggle, clear
  "value" => "10",               # literal value
  "value_type" => "literal",     # "literal" or "variable_ref"
  "value_sheet" => nil            # sheet shortcut for variable_ref
}
```

Operators by block type:
- `number`: set, add, subtract
- `boolean`: set_true, set_false, toggle
- `text`/`rich_text`: set, clear
- `select`/`multi_select`: set
- `date`: set

Key functions: `operators_for_type/1`, `operator_requires_value?/1`, `complete_assignment?/1`, `has_assignments?/1`, `add_assignment/1`, `remove_assignment/2`, `update_assignment/4`, `format_assignment_short/1`, `sanitize/1`.

**Execution engine:** `/lib/storyarn/flows/evaluator/instruction_exec.ex`

`execute(assignments, variables)` iterates complete assignments, resolves values (literal or variable_ref lookup), applies operators (`apply_operator/4`), returns `{:ok, new_variables, changes, errors}`.

`execute_string(json_string, variables)` parses a JSON string of assignments and executes them -- used by `dialogue_evaluator.ex` for response instructions.

**Instruction node evaluator:** `/lib/storyarn/flows/evaluator/node_evaluators/instruction_evaluator.ex`

Reads `data["assignments"]`, calls `InstructionExec.execute/2`, logs changes and errors to console/history.

### Condition system

**Domain module:** `/lib/storyarn/flows/condition.ex`

Condition structure:
```json
{
  "logic": "all",
  "rules": [
    {"id": "rule_1", "sheet": "mc.jaime", "variable": "health", "operator": "greater_than", "value": "50"}
  ]
}
```

Operators by block type:
- `text`: equals, not_equals, contains, starts_with, ends_with, is_empty
- `number`: equals, not_equals, greater_than, greater_than_or_equal, less_than, less_than_or_equal
- `boolean`: is_true, is_false, is_nil
- `select`: equals, not_equals, is_nil
- `multi_select`: contains, not_contains, is_empty
- `date`: equals, not_equals, before, after

Key functions: `parse/1`, `to_json/1`, `new/1`, `add_rule/2`, `remove_rule/2`, `update_rule/4`, `set_logic/2`, `sanitize/1`, `has_rules?/1`.

### JS builders

**Instruction builder:**
- Core: `/assets/js/screenplay/builders/instruction_builder_core.js` -- `createInstructionBuilder({container, assignments, variables, canEdit, context, eventName, pushEvent, translations})`
- Row: `/assets/js/instruction_builder/assignment_row.js` -- sentence-style "Set mc.jaime . health to 100" with combobox slots
- Templates: `/assets/js/instruction_builder/sentence_templates.js` -- operator configs with verb/sentence patterns
- Hook: `/assets/js/hooks/instruction_builder.js` -- thin wrapper, reads `data-*`, pushes `update_instruction_builder`
- HEEx: `/lib/storyarn_web/components/instruction_builder.ex` -- `<div phx-hook="InstructionBuilder" ...>`

**Condition builder:**
- Core: `/assets/js/screenplay/builders/condition_builder_core.js` -- `createConditionBuilder({...})`
- Hook: `/assets/js/hooks/condition_builder.js` -- thin wrapper, pushes `update_condition_builder` or `update_response_condition_builder`
- HEEx: `/lib/storyarn_web/components/condition_builder.ex` -- `<div phx-hook="ConditionBuilder" ...>`

### Response instruction current state

In `/lib/storyarn_web/live/flow_live/nodes/dialogue/config_sidebar.ex` (line 313-325), the response instruction is a plain `<input type="text">` with `phx-blur="update_response_instruction"`. The field stores a raw string in `response["instruction"]`.

In `dialogue_evaluator.ex` (line 28-50), `execute_response_instruction/3` calls `InstructionExec.execute_string/2` which tries to `Jason.decode` the string. If it is valid JSON array of assignments, they execute. If not (which is the common case with the plain text input), execution silently returns `{:ok, variables, [], []}`.

So the response instruction field is effectively dead -- it stores a raw string that cannot be executed.

### DSL design (from stress test plan)

**Instructions:**
```
mc.jaime.health = 50
global.quest_progress += 1
party.annah_present ?= true
mc.jaime.class = "warrior"
```

**Conditions:**
```
mc.jaime.health > 50
global.quest_progress >= 3 && party.annah_present
!(mc.jaime.dead) || global.override
mc.jaime.class == "warrior"
```

**Operators:**
- Assignment: `=` (set), `+=` (add), `-=` (subtract), `?=` (set if unset -- NEW)
- Comparison: `==` (equals), `!=` (not_equals), `>` (greater_than), `<` (less_than), `>=` (greater_than_or_equal), `<=` (less_than_or_equal)
- Logic: `&&` (AND/all), `||` (OR/any), `!` (NOT), parentheses for grouping
- Variables: `sheet_shortcut.variable_name` (existing Storyarn format)

**Architecture:**
```
Code text  <-->  Lezer AST  <-->  Structured data (assignments[] / condition{})
                                        |
                                  Visual Builder
```

---

## Subtasks

### Subtask 1: DSL grammar definition -- formal spec + Lezer grammar file

**Description:** Define the formal grammar for the Storyarn expression DSL covering both assignment statements and boolean expressions. Create the Lezer grammar file that will generate the parser. This subtask produces the grammar definition only -- the parser transformer comes in Subtask 2.

**Files affected:**

| File                                                      | Change                                               |
|-----------------------------------------------------------|------------------------------------------------------|
| New: `/assets/js/expression_editor/storyarn_expr.grammar` | Lezer grammar definition                             |
| New: `/assets/js/expression_editor/grammar_spec.md`       | Human-readable grammar specification (for reference) |

**Implementation steps:**

1. Define the grammar specification. The DSL has two modes:

   **Assignment mode** (used by instruction builders):
   ```
   Program       = Assignment (Newline Assignment)*
   Assignment    = VariableRef AssignOp Expression
   AssignOp      = "=" | "+=" | "-=" | "?="
   ```

   **Expression mode** (used by condition builders):
   ```
   Expression    = OrExpr
   OrExpr        = AndExpr ("||" AndExpr)*
   AndExpr       = NotExpr ("&&" NotExpr)*
   NotExpr       = "!" NotExpr | Comparison
   Comparison    = Value (CompareOp Value)?
   CompareOp     = "==" | "!=" | ">" | "<" | ">=" | "<="
   Value         = VariableRef | StringLiteral | NumberLiteral | BooleanLiteral | "(" Expression ")"
   VariableRef   = Identifier "." Identifier
   Identifier    = [a-zA-Z_][a-zA-Z0-9_]*
   StringLiteral = '"' [^"]* '"'
   NumberLiteral = [0-9]+ ("." [0-9]+)?
   BooleanLiteral = "true" | "false"
   ```

2. Create the Lezer grammar file at `/assets/js/expression_editor/storyarn_expr.grammar`:
   ```
   @top AssignmentProgram { assignment (";" assignment)* }
   @top ExpressionProgram { expression }

   assignment { variableRef assignOp expression }
   assignOp { "=" | "+=" | "-=" | "?=" }

   expression { orExpr }
   orExpr { andExpr ("||" andExpr)* }
   andExpr { notExpr ("&&" notExpr)* }
   notExpr { "!" notExpr | comparison }
   comparison { value (compareOp value)? }
   compareOp { "==" | "!=" | ">=" | "<=" | ">" | "<" }
   value { variableRef | StringLiteral | Number | Boolean | "(" expression ")" }

   variableRef { Identifier "." Identifier }

   @tokens {
     Identifier { $[a-zA-Z_] $[a-zA-Z0-9_]* }
     StringLiteral { '"' (!["\\] | "\\" _)* '"' }
     Number { $[0-9]+ ("." $[0-9]+)? }
     Boolean { "true" | "false" }
     whitespace { $[ \t\n\r]+ }
     LineComment { "//" ![\n]* }
   }

   @skip { whitespace | LineComment }
   ```

3. Install the Lezer build tool:
   ```bash
   cd assets && npm install @lezer/generator @lezer/lr --save-dev
   ```

4. Add a build script to `assets/package.json`:
   ```json
   "scripts": {
     "build:grammar": "lezer-generator assets/js/expression_editor/storyarn_expr.grammar -o assets/js/expression_editor/parser_generated.js"
   }
   ```

5. Create the human-readable grammar spec at `/assets/js/expression_editor/grammar_spec.md` documenting operator precedence, mapping to Storyarn operators, and examples.

**Test battery:**

| Test                                   | Location                                                      | What it verifies                                             |
|----------------------------------------|---------------------------------------------------------------|--------------------------------------------------------------|
| Grammar compiles without errors        | Build step                                                    | `npm run build:grammar` exits with code 0                    |
| Generated parser file exists           | Build step                                                    | `parser_generated.js` is created                             |
| Grammar parses simple assignment       | New: `/assets/js/__tests__/expression_editor/grammar.test.js` | `mc.jaime.health = 50` parses without errors                 |
| Grammar parses compound condition      | Same file                                                     | `mc.jaime.health > 50 && global.quest >= 3` parses correctly |
| Grammar handles string literals        | Same file                                                     | `mc.jaime.class == "warrior"` parses correctly               |
| Grammar handles negation               | Same file                                                     | `!(mc.jaime.dead)` parses correctly                          |
| Grammar handles ?= operator            | Same file                                                     | `party.present ?= true` parses correctly                     |
| Grammar handles multi-line assignments | Same file                                                     | Two assignments separated by `;` parse correctly             |

> Run `mix test` and `mix credo --strict` before proceeding.

---

### Subtask 2: Parser -- Lezer AST to structured data transformer

**Description:** Build the transformer that converts a Lezer parse tree into Storyarn's existing structured data formats: `assignments[]` for instruction mode, and `condition{}` (with `logic` + `rules`) for expression mode. This is the "text to data" direction.

**Files affected:**

| File | Change |
|------|--------|
| New: `/assets/js/expression_editor/parser.js` | AST-to-structured-data transformer |

**Implementation steps:**

1. Create `/assets/js/expression_editor/parser.js` with two exported functions:

   ```javascript
   import { parser as generatedParser } from "./parser_generated.js";

   /**
    * Parse an assignment program text into an assignments array.
    * @param {string} text - e.g. "mc.jaime.health = 50\nglobal.quest += 1"
    * @returns {{ assignments: Array, errors: Array<{from: number, to: number, message: string}> }}
    */
   export function parseAssignments(text) { ... }

   /**
    * Parse a boolean expression text into a condition object.
    * @param {string} text - e.g. "mc.jaime.health > 50 && global.quest >= 3"
    * @returns {{ condition: Object, errors: Array<{from: number, to: number, message: string}> }}
    */
   export function parseCondition(text) { ... }
   ```

2. **Assignment parsing logic:**
   - Walk the Lezer tree, find each `assignment` node.
   - Extract `variableRef` -> `sheet` (first Identifier) and `variable` (second Identifier).
   - Map `assignOp` to Storyarn operators: `"="` -> `"set"`, `"+="` -> `"add"`, `"-="` -> `"subtract"`, `"?="` -> `"set_if_unset"`.
   - Extract the value expression:
     - If it is a `variableRef`, set `value_type: "variable_ref"`, `value_sheet` and `value`.
     - If it is a literal (Number, StringLiteral, Boolean), set `value_type: "literal"` and `value`.
     - For Boolean `true`/`false` in assignment context: map to `operator: "set_true"` / `"set_false"` and clear value.
   - Generate an `id` for each assignment (`assign_${timestamp}_${random}`).
   - Collect parse errors from the Lezer tree (error nodes) with positions.

3. **Condition parsing logic:**
   - Walk the tree for `expression` node.
   - Top-level `orExpr` with multiple `andExpr` children maps to `logic: "any"` with each `andExpr` as a block of rules.
   - Top-level `andExpr` (no `||`) maps to `logic: "all"` with all comparisons as rules.
   - Each `comparison` maps to a rule:
     - Left `variableRef` -> `sheet` + `variable`.
     - `compareOp` maps to Storyarn operators: `"=="` -> `"equals"`, `"!="` -> `"not_equals"`, `">"` -> `"greater_than"`, `"<"` -> `"less_than"`, `">="` -> `"greater_than_or_equal"`, `"<="` -> `"less_than_or_equal"`.
     - Right value -> `value`.
   - For `notExpr` (`!` prefix): this is handled as a special case -- negate the inner comparison's operator (e.g., `!= equals` becomes `not_equals`). For complex negated groups, this may produce a parse error or be represented as a raw expression (future work for nested conditions from Gap 1).
   - Boolean-only checks like `party.present` (no comparison operator) map to `operator: "is_true"`.
   - `!party.present` maps to `operator: "is_false"`.
   - Generate `id` for each rule.

4. Handle error recovery: Lezer parsers are error-tolerant. If the tree contains error nodes, collect them in the `errors` array with `{from, to, message}` positions. Still return partial results for valid portions.

**Test battery:**

| Test                         | Location                                                | What it verifies                                                                                                             |
|------------------------------|---------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------|
| Parse simple set assignment  | `/assets/js/__tests__/expression_editor/parser.test.js` | `"mc.jaime.health = 50"` -> `[{sheet: "mc.jaime", variable: "health", operator: "set", value: "50", value_type: "literal"}]` |
| Parse add assignment         | Same file                                               | `"mc.jaime.health += 10"` -> operator `"add"`                                                                                |
| Parse subtract assignment    | Same file                                               | `"mc.jaime.health -= 5"` -> operator `"subtract"`                                                                            |
| Parse set_if_unset           | Same file                                               | `"party.present ?= true"` -> operator `"set_if_unset"`                                                                       |
| Parse variable_ref value     | Same file                                               | `"mc.link.sword = global.quests.done"` -> `value_type: "variable_ref"`, `value_sheet: "global.quests"`, `value: "done"`      |
| Parse boolean true           | Same file                                               | `"mc.jaime.alive = true"` -> operator `"set_true"`                                                                           |
| Parse multi-line assignments | Same file                                               | Two assignments separated by newline produce 2-element array                                                                 |
| Parse simple condition       | Same file                                               | `"mc.jaime.health > 50"` -> `{logic: "all", rules: [{operator: "greater_than", value: "50"}]}`                               |
| Parse AND condition          | Same file                                               | `"A > 1 && B < 2"` -> `logic: "all"`, 2 rules                                                                                |
| Parse OR condition           | Same file                                               | `"A > 1 \|\| B < 2"` -> `logic: "any"`, rules grouped appropriately                                                          |
| Parse negation               | Same file                                               | `"!(mc.jaime.dead)"` -> operator `"is_false"`                                                                                |
| Parse boolean variable check | Same file                                               | `"party.present"` (no operator) -> operator `"is_true"`                                                                      |
| Parse string comparison      | Same file                                               | `'mc.jaime.class == "warrior"'` -> value `"warrior"`                                                                         |
| Error recovery               | Same file                                               | `"mc.jaime.health = "` returns partial result + error with position                                                          |

> Run `mix test` and `mix credo --strict` before proceeding.

---

### Subtask 3: Serializer -- structured data to text

**Description:** Build the reverse transformer: Storyarn's structured data formats to human-readable DSL text. This is the "data to text" direction. Used when switching from Builder tab to Code tab.

**Files affected:**

| File                                              | Change                            |
|---------------------------------------------------|-----------------------------------|
| New: `/assets/js/expression_editor/serializer.js` | Structured data to text converter |

**Implementation steps:**

1. Create `/assets/js/expression_editor/serializer.js` with two exported functions:

   ```javascript
   /**
    * Serialize an assignments array to DSL text.
    * @param {Array} assignments - Storyarn assignment objects
    * @returns {string} Human-readable assignment text
    */
   export function serializeAssignments(assignments) { ... }

   /**
    * Serialize a condition object to DSL text.
    * @param {Object} condition - Storyarn condition ({logic, rules})
    * @returns {string} Human-readable boolean expression
    */
   export function serializeCondition(condition) { ... }
   ```

2. **Assignment serialization:**
   - For each complete assignment, generate one line:
     - Map operator to symbol: `"set"` -> `=`, `"add"` -> `+=`, `"subtract"` -> `-=`, `"set_if_unset"` -> `?=`.
     - `"set_true"` -> `= true`, `"set_false"` -> `= false`, `"toggle"` -> special: `toggle mc.jaime.alive` (no `=`), `"clear"` -> special: `clear mc.jaime.text` (no `=`).
     - Variable ref: `{sheet}.{variable}`.
     - Value: literal as-is (quote strings that contain spaces), variable_ref as `{value_sheet}.{value}`.
   - Join lines with `\n`.
   - Skip incomplete assignments (missing sheet or variable).

3. **Condition serialization:**
   - Join rules with ` && ` if `logic == "all"`, or ` || ` if `logic == "any"`.
   - Each rule:
     - Map operator to symbol: `"equals"` -> `==`, `"not_equals"` -> `!=`, `"greater_than"` -> `>`, `"less_than"` -> `<`, `"greater_than_or_equal"` -> `>=`, `"less_than_or_equal"` -> `<=`.
     - `"is_true"` -> just the variable ref (e.g., `party.present`).
     - `"is_false"` -> negated variable ref (e.g., `!party.present`).
     - `"is_nil"` -> not directly representable in DSL; use comment: `/* is_nil: mc.jaime.class */`.
     - `"is_empty"` -> same approach with comment fallback.
     - For text operators like `"contains"`, `"starts_with"`, `"ends_with"`: these do not have DSL symbols. Use function-call syntax: `contains(mc.jaime.name, "Annah")`. These are uncommon and can be extended later.
   - Quote string values: `mc.jaime.class == "warrior"`.
   - Numeric values unquoted: `mc.jaime.health > 50`.

4. Ensure round-trip: `serializeAssignments(parseAssignments(text).assignments)` should produce equivalent text (not necessarily identical whitespace, but semantically equivalent).

**Test battery:**

| Test                        | Location                                                    | What it verifies                                                                                    |
|-----------------------------|-------------------------------------------------------------|-----------------------------------------------------------------------------------------------------|
| Serialize set assignment    | `/assets/js/__tests__/expression_editor/serializer.test.js` | `{operator: "set", sheet: "mc.jaime", variable: "health", value: "50"}` -> `"mc.jaime.health = 50"` |
| Serialize add assignment    | Same file                                                   | operator "add" -> `"mc.jaime.health += 10"`                                                         |
| Serialize variable ref      | Same file                                                   | value_type "variable_ref" -> `"mc.link.sword = global.quests.done"`                                 |
| Serialize set_true          | Same file                                                   | operator "set_true" -> `"mc.jaime.alive = true"`                                                    |
| Serialize toggle            | Same file                                                   | operator "toggle" -> `"toggle mc.jaime.alive"`                                                      |
| Serialize clear             | Same file                                                   | operator "clear" -> `"clear mc.jaime.text"`                                                         |
| Serialize set_if_unset      | Same file                                                   | operator "set_if_unset" -> `"party.present ?= true"`                                                |
| Serialize multi assignment  | Same file                                                   | 2 assignments -> 2 lines joined by `\n`                                                             |
| Skip incomplete assignments | Same file                                                   | Assignment with no sheet is omitted                                                                 |
| Serialize AND condition     | Same file                                                   | logic "all" + 2 rules -> `"A > 1 && B < 2"`                                                         |
| Serialize OR condition      | Same file                                                   | logic "any" + 2 rules -> `"A > 1 \|\| B < 2"`                                                       |
| Serialize is_true           | Same file                                                   | operator "is_true" -> just variable ref                                                             |
| Serialize is_false          | Same file                                                   | operator "is_false" -> `"!mc.jaime.dead"`                                                           |
| Serialize string value      | Same file                                                   | value "warrior" -> `'== "warrior"'`                                                                 |
| Round-trip assignments      | Same file                                                   | serialize(parse(text).assignments) produces equivalent text                                         |
| Round-trip conditions       | Same file                                                   | serialize(parse(text).condition) produces equivalent text                                           |

> Run `mix test` and `mix credo --strict` before proceeding.

---

### Subtask 4: CodeMirror 6 integration -- Phoenix hook wrapping CodeMirror

**Description:** Create a Phoenix LiveView hook that wraps CodeMirror 6 with the custom Storyarn expression language. Provides syntax highlighting, basic editing, and a minimal API for getting/setting content programmatically. Autocomplete and linting are added in subsequent subtasks.

**Files affected:**

| File                                         | Change                                       |
|----------------------------------------------|----------------------------------------------|
| New: `/assets/js/hooks/expression_editor.js` | Phoenix LiveView hook wrapping CodeMirror 6  |
| New: `/assets/js/expression_editor/setup.js` | CodeMirror configuration factory             |
| New: `/assets/js/expression_editor/theme.js` | Custom theme matching Storyarn design system |
| `/assets/js/hooks/index.js`                  | Register the new hook                        |
| `assets/package.json`                        | Add CodeMirror dependencies                  |

**Implementation steps:**

1. Install CodeMirror 6 packages:
   ```bash
   cd assets && npm install @codemirror/state @codemirror/view @codemirror/language @codemirror/commands @codemirror/autocomplete @codemirror/lint @lezer/lr
   ```

2. Create `/assets/js/expression_editor/theme.js`:
   - Define a CodeMirror theme that matches Storyarn's daisyUI/Tailwind design.
   - Use CSS variables from the existing theme (`--b1`, `--b2`, `--bc`, etc.) for background, text, selection colors.
   - Style tokens: variables in blue, operators in purple, strings in green, numbers in orange, keywords (true/false) in teal, errors with red underline.
   - Keep the editor compact (`font-size: 13px`, `line-height: 1.4`) to fit in sidebars and response cards.

3. Create `/assets/js/expression_editor/setup.js`:
   ```javascript
   import { EditorState } from "@codemirror/state";
   import { EditorView, keymap, placeholder } from "@codemirror/view";
   import { defaultKeymap } from "@codemirror/commands";
   import { LRLanguage, LanguageSupport } from "@codemirror/language";
   import { parser as exprParser } from "./parser_generated.js";
   import { storyarnTheme } from "./theme.js";

   /**
    * Create a CodeMirror editor instance.
    * @param {Object} opts
    * @param {HTMLElement} opts.container
    * @param {string} opts.content - Initial text
    * @param {"assignments"|"expression"} opts.mode
    * @param {boolean} opts.editable
    * @param {Function} opts.onChange - Callback when content changes: (text) => void
    * @param {string} [opts.placeholderText]
    * @returns {{ view: EditorView, destroy: Function, getContent: Function, setContent: Function }}
    */
   export function createExpressionEditor(opts) { ... }
   ```
   - Configure the parser for the appropriate top rule (`AssignmentProgram` or `ExpressionProgram`) based on `mode`.
   - Set up extensions: `storyarnTheme`, `keymap.of(defaultKeymap)`, `placeholder(opts.placeholderText)`, `EditorView.editable.of(opts.editable)`.
   - Wire `EditorView.updateListener` to call `opts.onChange` on document changes (debounced at ~300ms to avoid excessive pushes).
   - Return API: `getContent()` returns current text, `setContent(text)` replaces content, `destroy()` cleans up.

4. Create `/assets/js/hooks/expression_editor.js`:
   ```javascript
   import { createExpressionEditor } from "../expression_editor/setup.js";

   export const ExpressionEditor = {
     mounted() {
       this.mode = this.el.dataset.mode || "expression"; // "assignments" or "expression"
       this.content = this.el.dataset.content || "";
       this.editable = JSON.parse(this.el.dataset.editable || "true");
       this.eventName = this.el.dataset.eventName || "update_expression";
       this.context = JSON.parse(this.el.dataset.context || "{}");

       this.editor = createExpressionEditor({
         container: this.el,
         content: this.content,
         mode: this.mode,
         editable: this.editable,
         placeholderText: this.el.dataset.placeholder || "",
         onChange: (text) => {
           this.pushEvent(this.eventName, { text, ...this.context });
         },
       });

       // Listen for external content updates (collaboration)
       this.handleEvent("expression_content_updated", (data) => {
         if (data.context_id === this.el.id) {
           this.editor.setContent(data.text);
         }
       });
     },

     destroyed() {
       this.editor?.destroy();
     },
   };
   ```

5. Register in `/assets/js/hooks/index.js`.

**Test battery:**

| Test                                | Location                                               | What it verifies                                               |
|-------------------------------------|--------------------------------------------------------|----------------------------------------------------------------|
| Editor mounts without error         | Manual / E2E                                           | Hook `mounted()` creates CodeMirror view inside the element    |
| Syntax highlighting applies         | Manual                                                 | Variable refs appear in blue, operators in purple              |
| onChange fires on edit              | `/assets/js/__tests__/expression_editor/setup.test.js` | Typing triggers onChange callback with updated text            |
| setContent updates editor           | Same file                                              | Calling `setContent("new text")` changes the visible content   |
| getContent returns current text     | Same file                                              | After editing, `getContent()` returns the modified text        |
| Read-only mode blocks editing       | Same file                                              | With `editable: false`, keyboard input does not modify content |
| Assignment mode uses correct parser | Same file                                              | `mode: "assignments"` parses `"a.b = 1"` without errors        |
| Expression mode uses correct parser | Same file                                              | `mode: "expression"` parses `"a.b > 1"` without errors         |

> Run `mix test` and `mix credo --strict` before proceeding.

---

### Subtask 5: Autocomplete extension -- variable name completion

**Description:** Add CodeMirror autocomplete that suggests variable names from the project's variables list, grouped by sheet. When the user types a sheet shortcut followed by `.`, the autocomplete suggests variables from that sheet. When typing from scratch, it suggests sheet shortcuts first.

**Files affected:**

| File                                                | Change                                         |
|-----------------------------------------------------|------------------------------------------------|
| New: `/assets/js/expression_editor/autocomplete.js` | Autocomplete completion source                 |
| `/assets/js/expression_editor/setup.js`             | Wire autocomplete extension into editor config |

**Implementation steps:**

1. Create `/assets/js/expression_editor/autocomplete.js`:
   ```javascript
   import { autocompletion } from "@codemirror/autocomplete";

   /**
    * Creates an autocomplete extension for Storyarn variables.
    * @param {Array} variables - Flat list of {sheet_shortcut, variable_name, block_type}
    * @returns {Extension} CodeMirror extension
    */
   export function variableAutocomplete(variables) {
     const grouped = groupBySheet(variables);

     return autocompletion({
       override: [
         (context) => completeVariable(context, variables, grouped),
       ],
     });
   }
   ```

2. Completion logic in `completeVariable`:
   - Get the word at cursor using `context.matchBefore(/[a-zA-Z_][a-zA-Z0-9_.]*/)`.
   - If the word contains a `.`:
     - Split on `.` to get sheet shortcut prefix.
     - Find the sheet in grouped variables.
     - Suggest variables from that sheet, with their `block_type` as detail.
   - If no `.`:
     - Suggest sheet shortcuts (deduplicated).
     - Each suggestion appends `.` on accept.
   - Format completions: `{ label, detail, type, apply }`.
   - Use `type: "variable"` for variables, `type: "namespace"` for sheets.

3. Update `setup.js` to accept a `variables` option and include the autocomplete extension:
   ```javascript
   if (opts.variables && opts.variables.length > 0) {
     extensions.push(variableAutocomplete(opts.variables));
   }
   ```

4. Update the hook to pass variables:
   ```javascript
   this.variables = JSON.parse(this.el.dataset.variables || "[]");
   // ... pass to createExpressionEditor
   ```

**Test battery:**

| Test                                  | Location                                                      | What it verifies                                         |
|---------------------------------------|---------------------------------------------------------------|----------------------------------------------------------|
| Sheet shortcuts suggested when typing | `/assets/js/__tests__/expression_editor/autocomplete.test.js` | Typing `"mc"` suggests `"mc.jaime"`, `"mc.link"` etc.    |
| Variables suggested after dot         | Same file                                                     | Typing `"mc.jaime."` suggests `"health"`, `"class"` etc. |
| Block type shown as detail            | Same file                                                     | Completion for "health" shows "(number)" as detail       |
| Empty input shows all sheets          | Same file                                                     | With empty prefix, all sheet shortcuts are listed        |
| No suggestions for unknown prefix     | Same file                                                     | Typing `"zzz"` returns no completions                    |
| Dot appended to sheet selection       | Same file                                                     | Selecting `"mc.jaime"` from completions adds the dot     |

> Run `mix test` and `mix credo --strict` before proceeding.

---

### Subtask 6: Lint extension -- validation + error markers

**Description:** Add a CodeMirror linting extension that validates the expression text using the parser (Subtask 2) and displays inline error markers for syntax errors, undefined variables, and type mismatches.

**Files affected:**

| File                                          | Change                                   |
|-----------------------------------------------|------------------------------------------|
| New: `/assets/js/expression_editor/linter.js` | Lint source using parser diagnostics     |
| `/assets/js/expression_editor/setup.js`       | Wire linter extension into editor config |

**Implementation steps:**

1. Create `/assets/js/expression_editor/linter.js`:
   ```javascript
   import { linter } from "@codemirror/lint";
   import { parseAssignments, parseCondition } from "./parser.js";

   /**
    * Creates a linter extension for the expression editor.
    * @param {"assignments"|"expression"} mode
    * @param {Array} variables - For variable existence checking
    * @returns {Extension} CodeMirror linter extension
    */
   export function expressionLinter(mode, variables) {
     const variableSet = new Set(
       variables.map((v) => `${v.sheet_shortcut}.${v.variable_name}`)
     );

     return linter((view) => {
       const text = view.state.doc.toString();
       if (!text.trim()) return [];

       const diagnostics = [];
       const result = mode === "assignments"
         ? parseAssignments(text)
         : parseCondition(text);

       // Syntax errors from parser
       for (const err of result.errors) {
         diagnostics.push({
           from: err.from,
           to: err.to,
           severity: "error",
           message: err.message,
         });
       }

       // Undefined variable warnings
       // Walk the parsed data and check each variable ref against variableSet
       ...

       return diagnostics;
     });
   }
   ```

2. Variable existence checking:
   - For assignments: check each `sheet.variable` pair in the assignments array.
   - For conditions: check each rule's `sheet.variable`.
   - If a variable ref is not in `variableSet`, add a warning diagnostic at the appropriate position.
   - Severity: `"warning"` for undefined variables (they might be defined later or in another context), `"error"` for syntax errors.

3. To map structured data back to text positions, the parser (Subtask 2) needs to also return position metadata. Update the parser to include `{from, to}` character offsets for each extracted variable reference. This requires walking the Lezer tree and recording node positions.

4. Wire into `setup.js`:
   ```javascript
   if (opts.variables) {
     extensions.push(expressionLinter(opts.mode, opts.variables));
   }
   ```

**Test battery:**

| Test                                  | Location                                                | What it verifies                                             |
|---------------------------------------|---------------------------------------------------------|--------------------------------------------------------------|
| No diagnostics for valid expression   | `/assets/js/__tests__/expression_editor/linter.test.js` | `"mc.jaime.health > 50"` with matching variable returns `[]` |
| Syntax error marked                   | Same file                                               | `"mc.jaime.health >"` returns error diagnostic               |
| Undefined variable warning            | Same file                                               | Variable not in list returns warning diagnostic              |
| Multiple errors collected             | Same file                                               | Text with two errors returns 2 diagnostics                   |
| Empty text returns no diagnostics     | Same file                                               | `""` returns `[]`                                            |
| Assignment mode validates assignments | Same file                                               | `"mc.jaime.health = "` returns error for missing value       |

> Run `mix test` and `mix credo --strict` before proceeding.

---

### Subtask 7: Tab switcher HEEx component -- Builder | Code with bidirectional sync

**Description:** Create a reusable HEEx component that wraps both the visual builder (condition or instruction) and the code editor in a tabbed interface. Switching tabs converts data bidirectionally using the parser and serializer. The structured data is always the source of truth.

**Files affected:**

| File                                                     | Change                                |
|----------------------------------------------------------|---------------------------------------|
| New: `/lib/storyarn_web/components/expression_editor.ex` | HEEx component with Builder/Code tabs |

**Implementation steps:**

1. Create `/lib/storyarn_web/components/expression_editor.ex`:
   ```elixir
   defmodule StoryarnWeb.Components.ExpressionEditor do
     @moduledoc """
     Tabbed expression editor: Builder | Code.
     Wraps visual builder and CodeMirror editor with bidirectional sync.
     """

     use Phoenix.Component
     use Gettext, backend: StoryarnWeb.Gettext

     import StoryarnWeb.Components.CoreComponents
     import StoryarnWeb.Components.ConditionBuilder
     import StoryarnWeb.Components.InstructionBuilder

     attr :id, :string, required: true
     attr :mode, :string, required: true, values: ~w(condition instruction)
     attr :condition, :map, default: nil
     attr :assignments, :list, default: []
     attr :variables, :list, default: []
     attr :can_edit, :boolean, default: true
     attr :context, :map, default: %{}
     attr :switch_mode, :boolean, default: false
     attr :event_name, :string, default: nil
     attr :active_tab, :string, default: "builder"

     def expression_editor(assigns) do
       # Serialize data to text for the Code tab
       serialized_text =
         case assigns.mode do
           "condition" -> serialize_condition_to_text(assigns.condition)
           "instruction" -> serialize_assignments_to_text(assigns.assignments)
         end

       assigns = assign(assigns, :serialized_text, serialized_text)

       ~H"""
       <div id={@id} class="expression-editor">
         <div class="flex items-center gap-1 mb-2">
           <button
             type="button"
             class={"btn btn-xs #{if @active_tab == "builder", do: "btn-active", else: "btn-ghost"}"}
             phx-click="toggle_expression_tab"
             phx-value-id={@id}
             phx-value-tab="builder"
           >
             {dgettext("flows", "Builder")}
           </button>
           <button
             type="button"
             class={"btn btn-xs #{if @active_tab == "code", do: "btn-active", else: "btn-ghost"}"}
             phx-click="toggle_expression_tab"
             phx-value-id={@id}
             phx-value-tab="code"
           >
             {dgettext("flows", "Code")}
           </button>
         </div>

         <div :if={@active_tab == "builder"}>
           <.condition_builder
             :if={@mode == "condition"}
             id={"#{@id}-cond-builder"}
             condition={@condition}
             variables={@variables}
             can_edit={@can_edit}
             context={@context}
             switch_mode={@switch_mode}
             event_name={@event_name}
           />
           <.instruction_builder
             :if={@mode == "instruction"}
             id={"#{@id}-inst-builder"}
             assignments={@assignments}
             variables={@variables}
             can_edit={@can_edit}
             context={@context}
             event_name={@event_name}
           />
         </div>

         <div
           :if={@active_tab == "code"}
           id={"#{@id}-code-editor"}
           phx-hook="ExpressionEditor"
           phx-update="ignore"
           data-mode={if @mode == "condition", do: "expression", else: "assignments"}
           data-content={@serialized_text}
           data-editable={Jason.encode!(@can_edit)}
           data-variables={Jason.encode!(@variables)}
           data-context={Jason.encode!(@context)}
           data-event-name={@event_name}
           data-placeholder={if @mode == "condition", do: dgettext("flows", "mc.jaime.health > 50"), else: dgettext("flows", "mc.jaime.health = 50")}
           class="min-h-[60px] border border-base-300 rounded-lg overflow-hidden"
         >
         </div>
       </div>
       """
     end

     # Serialization helpers (call JS serializer via a thin Elixir mirror,
     # or use Instruction.format_assignment_short/1 for assignments)
     defp serialize_condition_to_text(nil), do: ""
     defp serialize_condition_to_text(%{"rules" => []}), do: ""
     defp serialize_condition_to_text(condition) do
       # Server-side serialization using existing Elixir code
       # Each rule: "sheet.variable operator value"
       rules = condition["rules"] || []
       joiner = if condition["logic"] == "any", do: " || ", else: " && "

       rules
       |> Enum.map(&format_rule_to_text/1)
       |> Enum.reject(&(&1 == ""))
       |> Enum.join(joiner)
     end

     defp serialize_assignments_to_text(nil), do: ""
     defp serialize_assignments_to_text([]), do: ""
     defp serialize_assignments_to_text(assignments) do
       assignments
       |> Enum.map(&Storyarn.Flows.Instruction.format_assignment_short/1)
       |> Enum.reject(&(&1 == ""))
       |> Enum.join("\n")
     end

     defp format_rule_to_text(rule) do
       sheet = rule["sheet"]
       variable = rule["variable"]
       operator = rule["operator"]
       value = rule["value"]

       if is_binary(sheet) and sheet != "" and is_binary(variable) and variable != "" do
         ref = "#{sheet}.#{variable}"
         format_comparison(ref, operator, value)
       else
         ""
       end
     end

     defp format_comparison(ref, "is_true", _), do: ref
     defp format_comparison(ref, "is_false", _), do: "!#{ref}"
     defp format_comparison(ref, "is_nil", _), do: "#{ref} == nil"
     defp format_comparison(ref, "is_empty", _), do: "#{ref} == \"\""
     defp format_comparison(ref, op, value) do
       symbol = operator_to_symbol(op)
       "#{ref} #{symbol} #{format_value(value)}"
     end

     defp operator_to_symbol("equals"), do: "=="
     defp operator_to_symbol("not_equals"), do: "!="
     defp operator_to_symbol("greater_than"), do: ">"
     defp operator_to_symbol("less_than"), do: "<"
     defp operator_to_symbol("greater_than_or_equal"), do: ">="
     defp operator_to_symbol("less_than_or_equal"), do: "<="
     defp operator_to_symbol("contains"), do: "contains"
     defp operator_to_symbol("starts_with"), do: "starts_with"
     defp operator_to_symbol("ends_with"), do: "ends_with"
     defp operator_to_symbol("not_contains"), do: "not_contains"
     defp operator_to_symbol("before"), do: "<"
     defp operator_to_symbol("after"), do: ">"
     defp operator_to_symbol(op), do: op

     defp format_value(nil), do: "?"
     defp format_value(v) when is_binary(v) do
       case Float.parse(v) do
         {_, ""} -> v
         _ -> ~s("#{v}")
       end
     end
     defp format_value(v), do: to_string(v)
   end
   ```

2. The tab toggle event is handled in `show.ex` or wherever the expression editor is used. Add a handler:
   ```elixir
   def handle_event("toggle_expression_tab", %{"id" => id, "tab" => tab}, socket) do
     # Store active tab per expression editor instance in panel_sections
     panel_sections = Map.put(socket.assigns.panel_sections, "tab_#{id}", tab)
     {:noreply, assign(socket, :panel_sections, panel_sections)}
   end
   ```

3. When switching from Code tab to Builder tab, the code editor's `onChange` callback has already pushed the parsed structured data back to the server. The Builder tab renders from the server-side assigns which are up to date.

4. When switching from Builder tab to Code tab, the server serializes the current structured data into text via `serialize_condition_to_text` or `serialize_assignments_to_text`, and the CodeMirror editor mounts with that text.

**Test battery:**

| Test                                         | Location                                                   | What it verifies                                               |
|----------------------------------------------|------------------------------------------------------------|----------------------------------------------------------------|
| Component renders Builder tab by default     | `/test/storyarn_web/components/expression_editor_test.exs` | Output contains builder component, no code editor              |
| Tab buttons present                          | Same file                                                  | Output contains "Builder" and "Code" buttons                   |
| Condition mode renders condition builder     | Same file                                                  | With `mode="condition"`, contains `condition-builder` hook     |
| Instruction mode renders instruction builder | Same file                                                  | With `mode="instruction"`, contains `instruction-builder` hook |
| Serialization produces valid text            | Same file (unit)                                           | `serialize_assignments_to_text` converts assignments correctly |
| Condition serialization produces valid text  | Same file (unit)                                           | `serialize_condition_to_text` converts rules correctly         |
| Empty data serializes to empty string        | Same file                                                  | `[]` or `%{"rules" => []}` returns `""`                        |

> Run `mix test` and `mix credo --strict` before proceeding.

---

### Subtask 8: Integrate in condition contexts -- condition nodes + response conditions get Code tab

**Description:** Replace the bare `<.condition_builder>` component with the new `<.expression_editor mode="condition">` wrapper in all condition contexts: condition node sidebar and response condition builders (both in the sidebar and full editor).

**Files affected:**

| File                                                                 | Change                                                                                             |
|----------------------------------------------------------------------|----------------------------------------------------------------------------------------------------|
| `/lib/storyarn_web/live/flow_live/nodes/condition/config_sidebar.ex` | Replace `condition_builder` with `expression_editor`                                               |
| `/lib/storyarn_web/live/flow_live/nodes/dialogue/config_sidebar.ex`  | Replace response condition `condition_builder` with `expression_editor`                            |
| `/lib/storyarn_web/live/flow_live/components/screenplay_editor.ex`   | Replace response condition `condition_builder` with `expression_editor` (from Subtask 6 of Doc 03) |
| `/lib/storyarn_web/live/flow_live/show.ex`                           | Add `toggle_expression_tab` event handler                                                          |

**Implementation steps:**

1. In `condition/config_sidebar.ex`, find the `<.condition_builder>` call and replace with:
   ```elixir
   <.expression_editor
     id={"condition-expr-#{@node.id}"}
     mode="condition"
     condition={@form[:condition].value}
     variables={@project_variables}
     can_edit={@can_edit}
     active_tab={Map.get(@panel_sections, "tab_condition-expr-#{@node.id}", "builder")}
   />
   ```

2. In `dialogue/config_sidebar.ex`, in the `response_item` component, replace the `<.condition_builder>` with:
   ```elixir
   <.expression_editor
     id={"response-cond-expr-#{@response["id"]}"}
     mode="condition"
     condition={@parsed_condition}
     variables={@project_variables}
     can_edit={@can_edit}
     context={%{"response-id" => @response["id"], "node-id" => @node.id}}
     active_tab={Map.get(@panel_sections, "tab_response-cond-expr-#{@response["id"]}", "builder")}
   />
   ```

3. In `screenplay_editor.ex`, do the same replacement for response conditions.

4. In `show.ex`, add the tab toggle handler (if not already added in Subtask 7):
   ```elixir
   def handle_event("toggle_expression_tab", %{"id" => id, "tab" => tab}, socket) do
     panel_sections = Map.put(socket.assigns.panel_sections, "tab_#{id}", tab)
     {:noreply, assign(socket, :panel_sections, panel_sections)}
   end
   ```

5. Import `StoryarnWeb.Components.ExpressionEditor` in the relevant modules (or rely on auto-import if configured).

**Test battery:**

| Test                                         | Location                           | What it verifies                                             |
|----------------------------------------------|------------------------------------|--------------------------------------------------------------|
| Condition node sidebar has Builder/Code tabs | Integration test or component test | Contains "Builder" and "Code" tab buttons                    |
| Response condition in sidebar has tabs       | Same                               | Response condition section contains expression editor tabs   |
| Condition builder still functional           | Integration                        | After integration, existing builder events still work        |
| Code tab renders CodeMirror container        | Integration                        | When Code tab active, contains `phx-hook="ExpressionEditor"` |
| Tab state persists per instance              | Integration                        | Switching tab for one condition does not affect another      |

> Run `mix test` and `mix credo --strict` before proceeding.

---

### Subtask 9: Integrate in instruction contexts -- instruction nodes + response instructions get Code tab

**Description:** Replace the bare `<.instruction_builder>` in instruction node sidebars with the `<.expression_editor mode="instruction">` wrapper. Also prepare response instruction integration for the full editor (to be wired with actual assignments data in Subtask 10).

**Files affected:**

| File                                                                   | Change                                                 |
|------------------------------------------------------------------------|--------------------------------------------------------|
| `/lib/storyarn_web/live/flow_live/nodes/instruction/config_sidebar.ex` | Replace `instruction_builder` with `expression_editor` |

**Implementation steps:**

1. In `instruction/config_sidebar.ex`, replace:
   ```elixir
   <.instruction_builder
     id={"instruction-builder-#{@node.id}"}
     assignments={@assignments}
     variables={@project_variables}
     can_edit={@can_edit}
   />
   ```
   with:
   ```elixir
   <.expression_editor
     id={"instruction-expr-#{@node.id}"}
     mode="instruction"
     assignments={@assignments}
     variables={@project_variables}
     can_edit={@can_edit}
     active_tab={Map.get(@panel_sections, "tab_instruction-expr-#{@node.id}", "builder")}
   />
   ```

2. Ensure the `panel_sections` assign is available in the sidebar (it is already passed from `properties_panels.ex`).

**Test battery:**

| Test                                           | Location       | What it verifies                                                    |
|------------------------------------------------|----------------|---------------------------------------------------------------------|
| Instruction node sidebar has Builder/Code tabs | Component test | Contains "Builder" and "Code" buttons                               |
| Builder tab shows assignment builder           | Same           | Builder tab contains instruction builder hook                       |
| Code tab shows code editor                     | Same           | Code tab contains expression editor hook                            |
| Assignment events still work through builder   | Integration    | Adding/removing assignments via builder still pushes correct events |

> Run `mix test` and `mix credo --strict` before proceeding.

---

### Subtask 10: Response instruction backend -- replace dead instruction string with assignments array

**Description:** The response `"instruction"` field currently stores a raw string that is never properly executed. Replace it with an `"instruction_assignments"` field that stores a proper assignments array (same format as instruction node assignments). Wire the dialogue evaluator to execute these assignments when a response is selected.

**Files affected:**

| File                                                                  | Change                                                                                                                                |
|-----------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------|
| `/lib/storyarn_web/live/flow_live/nodes/dialogue/node.ex`             | Update `handle_update_response_instruction` to accept assignments array; add new `handle_update_response_instruction_builder` handler |
| `/lib/storyarn/flows/evaluator/node_evaluators/dialogue_evaluator.ex` | Execute `instruction_assignments` instead of raw `instruction` string                                                                 |
| `/lib/storyarn_web/live/flow_live/show.ex`                            | Add event handler for `update_response_instruction_builder`                                                                           |
| `/lib/storyarn_web/live/flow_live/nodes/dialogue/config_sidebar.ex`   | Replace plain `<input>` for instruction with `<.expression_editor>`                                                                   |
| `/lib/storyarn_web/live/flow_live/components/screenplay_editor.ex`    | Replace plain `<input>` for instruction with `<.expression_editor>` (from Doc 03 Subtask 6)                                           |
| `/lib/storyarn/flows/instruction.ex`                                  | Add `?=` (set_if_unset) operator                                                                                                      |

**Implementation steps:**

1. **Add `?=` operator to `instruction.ex`:**
   - Add `"set_if_unset"` to the appropriate operator lists:
     ```elixir
     # All types can use set_if_unset
     @set_if_unset_operators ~w(set_if_unset)
     ```
   - Update `@all_operators` to include `"set_if_unset"`.
   - Add to `operator_label/1`: `def operator_label("set_if_unset"), do: "?="`.
   - Add to `operator_requires_value?/1`: `set_if_unset` requires a value, so no change needed (default returns `true`).
   - Add to `operators_for_type/1`: Append `"set_if_unset"` to each type's operator list. Or add it as a universal operator available for all types.

2. **Add `?=` execution to `instruction_exec.ex`:**
   ```elixir
   # set_if_unset: only set if current value is nil
   defp apply_operator("set_if_unset", nil, value, _type), do: value
   defp apply_operator("set_if_unset", old, _value, _type), do: old
   ```

3. **Update dialogue node data model:**
   - In `dialogue/node.ex` `default_data/0`, the response structure already has `"instruction" => nil`.
   - Add `"instruction_assignments"` as the new field:
     ```elixir
     new_response = %{
       "id" => new_id,
       "text" => default_text,
       "condition" => nil,
       "instruction" => nil,              # legacy, kept for backwards compat
       "instruction_assignments" => []     # new: proper assignments array
     }
     ```

4. **Add handler for the instruction builder events from response cards:**
   ```elixir
   # In dialogue/node.ex
   def handle_update_response_instruction_builder(
         %{"assignments" => assignments, "response-id" => response_id, "node-id" => node_id},
         socket
       ) do
     NodeHelpers.persist_node_update(socket, node_id, fn data ->
       Map.update(data, "responses", [], fn responses ->
         Enum.map(responses, fn
           %{"id" => ^response_id} = resp ->
             Map.put(resp, "instruction_assignments", Instruction.sanitize(assignments))
           resp -> resp
         end)
       end)
     end)
   end
   ```

5. **Wire event in `show.ex`:**
   ```elixir
   def handle_event("update_response_instruction_builder", params, socket) do
     with_auth(:edit_content, socket, fn ->
       Dialogue.Node.handle_update_response_instruction_builder(params, socket)
     end)
   end
   ```

6. **Update dialogue evaluator:**
   In `dialogue_evaluator.ex`, update `auto_select_response/6` and the response map to check `instruction_assignments` first, falling back to the legacy `instruction` string:
   ```elixir
   state =
     cond do
       is_list(only[:instruction_assignments]) and only[:instruction_assignments] != [] ->
         {:ok, new_vars, changes, errors} =
           InstructionExec.execute(only.instruction_assignments, state.variables)
         # ... log changes and errors as in instruction_evaluator.ex
         %{state | variables: new_vars}

       is_binary(only[:instruction]) and only[:instruction] != "" ->
         execute_response_instruction(only.instruction, state, node_id)

       true ->
         state
     end
   ```
   Also update `evaluate_response_conditions/2` to include `instruction_assignments` in the evaluated map:
   ```elixir
   %{
     id: resp["id"],
     text: resp["text"] || "",
     valid: valid,
     rule_details: rule_results,
     instruction: resp["instruction"],
     instruction_assignments: resp["instruction_assignments"] || []
   }
   ```

7. **Replace UI in dialogue sidebar:**
   In `dialogue/config_sidebar.ex` `response_item/1`, replace the plain `<input>` for instruction with:
   ```elixir
   <.expression_editor
     id={"response-inst-expr-#{@response["id"]}"}
     mode="instruction"
     assignments={@response["instruction_assignments"] || []}
     variables={@project_variables}
     can_edit={@can_edit}
     context={%{"response-id" => @response["id"], "node-id" => @node.id}}
     event_name="update_response_instruction_builder"
     active_tab={Map.get(@panel_sections, "tab_response-inst-expr-#{@response["id"]}", "builder")}
   />
   ```

8. **Replace UI in full editor (screenplay_editor.ex):**
   Same replacement as above for the instruction section in response cards.

**Test battery:**

| Test                                                    | Location                                                                     | What it verifies                                                              |
|---------------------------------------------------------|------------------------------------------------------------------------------|-------------------------------------------------------------------------------|
| set_if_unset operator in instruction.ex                 | `/test/storyarn/flows/instruction_test.exs`                                  | `operators_for_type("number")` includes `"set_if_unset"`                      |
| set_if_unset label                                      | Same file                                                                    | `operator_label("set_if_unset")` returns `"?="`                               |
| set_if_unset execution (nil value)                      | `/test/storyarn/flows/evaluator/instruction_exec_test.exs`                   | Variable with `nil` value gets set                                            |
| set_if_unset execution (existing value)                 | Same file                                                                    | Variable with existing value is not overwritten                               |
| Response instruction_assignments saved                  | New test in `/test/storyarn_web/live/flow_live/show_events_test.exs`         | `update_response_instruction_builder` event persists assignments to node data |
| Dialogue evaluator executes response assignments        | `/test/storyarn/flows/evaluator/dialogue_evaluator_test.exs` (new or extend) | Response with `instruction_assignments` triggers variable changes             |
| Backwards compat: legacy instruction string still works | Same file                                                                    | Response with old `instruction` JSON string still executes                    |
| Builder renders in response card                        | Component/integration test                                                   | Response instruction area shows expression editor with Builder/Code tabs      |

> Run `mix test` and `mix credo --strict` before proceeding.

---

### Subtask 11: Visual builder variable autocomplete improvement -- group by sheet, add inline search

**Description:** Improve the existing combobox component used in both condition and instruction visual builders to handle large variable lists (1,000+) by grouping options by sheet and adding inline search/filter. This makes the visual builder usable at Planescape scale.

**Files affected:**

| File                                         | Change                                                 |
|----------------------------------------------|--------------------------------------------------------|
| `/assets/js/instruction_builder/combobox.js` | Add grouped options rendering and inline search filter |

**Implementation steps:**

1. Open `/assets/js/instruction_builder/combobox.js` (the shared combobox used by both builders).

2. Add **grouped rendering** to the dropdown:
   - When options have a `group` property (set by the caller), render group headers in the dropdown:
     ```
     ── mc.jaime ──
       health (number)
       class (select)
       alive (boolean)
     ── global ──
       quest_progress (number)
       fortress (number)
     ```
   - Group headers are non-selectable, styled with small text and a separator line.

3. Add **inline search filter**:
   - At the top of the dropdown, add an auto-focused text input.
   - As the user types, filter options across all groups.
   - Filtering checks both the option label and the group name (so typing "jaime" shows all variables in the "mc.jaime" sheet).
   - Debounce filtering at 100ms for responsiveness.
   - If a group has no matching options after filtering, hide the entire group.

4. Update callers in `assignment_row.js` and `condition_rule_row.js` (if it exists) to pass `group` property on options:
   - For sheet selection: no grouping needed (flat list of sheets).
   - For variable selection: group by sheet (the options already come from a single sheet, so this is mainly relevant for the "value" slot in variable_ref mode where any variable from any sheet can be selected).
   - For the "value" slot with select-type variables: options are already flat (select options from one variable).

5. Update `getOptionsForSlot("variable", ...)` in `assignment_row.js` to add a `group` property to each option based on the sheet shortcut.

**Test battery:**

| Test                                 | Location       | What it verifies                                             |
|--------------------------------------|----------------|--------------------------------------------------------------|
| Grouped options render with headers  | Manual / E2E   | Variable dropdown shows sheet-grouped sections with headers  |
| Search filter narrows options        | Manual / E2E   | Typing "heal" in the search input hides non-matching options |
| Search matches group name            | Manual / E2E   | Typing "jaime" shows all variables in mc.jaime               |
| Empty search shows all options       | Manual / E2E   | With empty search input, all options are visible             |
| No results state                     | Manual / E2E   | Typing "zzzzz" shows "No matches" message                    |
| Keyboard navigation still works      | Manual / E2E   | Arrow keys and Enter still select options                    |
| Existing combobox behavior preserved | Existing tests | Free-text mode and basic selection still work as before      |

> Run `mix test` and `mix credo --strict` before proceeding.

---

## Summary of file changes across all subtasks

| File                                                                   | Subtasks         | Type                |
|------------------------------------------------------------------------|------------------|---------------------|
| `/assets/js/expression_editor/storyarn_expr.grammar`                   | 1                | **New**             |
| `/assets/js/expression_editor/grammar_spec.md`                         | 1                | **New**             |
| `/assets/js/expression_editor/parser_generated.js`                     | 1 (build output) | **New** (generated) |
| `/assets/js/expression_editor/parser.js`                               | 2                | **New**             |
| `/assets/js/expression_editor/serializer.js`                           | 3                | **New**             |
| `/assets/js/expression_editor/setup.js`                                | 4, 5, 6          | **New**             |
| `/assets/js/expression_editor/theme.js`                                | 4                | **New**             |
| `/assets/js/expression_editor/autocomplete.js`                         | 5                | **New**             |
| `/assets/js/expression_editor/linter.js`                               | 6                | **New**             |
| `/assets/js/hooks/expression_editor.js`                                | 4                | **New**             |
| `/assets/js/hooks/index.js`                                            | 4                | Modified            |
| `/lib/storyarn_web/components/expression_editor.ex`                    | 7                | **New**             |
| `/lib/storyarn_web/live/flow_live/nodes/condition/config_sidebar.ex`   | 8                | Modified            |
| `/lib/storyarn_web/live/flow_live/nodes/dialogue/config_sidebar.ex`    | 8, 10            | Modified            |
| `/lib/storyarn_web/live/flow_live/components/screenplay_editor.ex`     | 8, 10            | Modified            |
| `/lib/storyarn_web/live/flow_live/show.ex`                             | 8, 10            | Modified            |
| `/lib/storyarn_web/live/flow_live/nodes/instruction/config_sidebar.ex` | 9                | Modified            |
| `/lib/storyarn/flows/instruction.ex`                                   | 10               | Modified            |
| `/lib/storyarn/flows/evaluator/instruction_exec.ex`                    | 10               | Modified            |
| `/lib/storyarn_web/live/flow_live/nodes/dialogue/node.ex`              | 10               | Modified            |
| `/lib/storyarn/flows/evaluator/node_evaluators/dialogue_evaluator.ex`  | 10               | Modified            |
| `/assets/js/instruction_builder/combobox.js`                           | 11               | Modified            |
| `/assets/js/instruction_builder/assignment_row.js`                     | 11               | Modified            |
| `assets/package.json`                                                  | 1, 4             | Modified            |

---

## DSL operator mapping reference

### Assignment operators

| DSL Symbol   | Storyarn Operator  | Applies to              |
|--------------|--------------------|-------------------------|
| `=`          | `set`              | All types               |
| `+=`         | `add`              | number                  |
| `-=`         | `subtract`         | number                  |
| `?=`         | `set_if_unset`     | All types (NEW)         |
| `= true`     | `set_true`         | boolean                 |
| `= false`    | `set_false`        | boolean                 |
| `toggle`     | `toggle`           | boolean (prefix syntax) |
| `clear`      | `clear`            | text (prefix syntax)    |

### Comparison operators

| DSL Symbol   | Storyarn Operator       |
|--------------|-------------------------|
| `==`         | `equals`                |
| `!=`         | `not_equals`            |
| `>`          | `greater_than`          |
| `<`          | `less_than`             |
| `>=`         | `greater_than_or_equal` |
| `<=`         | `less_than_or_equal`    |
| (bare ref)   | `is_true`               |
| `!` (prefix) | `is_false`              |

### Logic operators

| DSL Symbol | Storyarn Logic |
|------------|----------------|
| `&&`       | `"all"` (AND)  |
| `\|\|`     | `"any"` (OR)   |
| `!`        | NOT (negation) |
| `( )`      | Grouping       |

---

**Next document:** [`05_FLOW_TAGS.md`](05_FLOW_TAGS.md) -- Flow Tags and Organization
