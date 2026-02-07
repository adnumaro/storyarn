# Instruction Node + Variable Reference System

> **Status**: Phases A-C complete, Phase D pending
> **Date**: February 7, 2026
> **Scope**: Instruction node visual builder, variable write/read tracking, variable usage UI on pages

---

## Overview

Four phases that build on each other:

| Phase | What | Effort | Depends on | Status |
|-------|------|--------|------------|--------|
| **A** | Instruction Node (visual builder) | Medium | Nothing | ✅ Done |
| **B** | Variable Reference Tracking (DB + tracker) | Medium | A | ✅ Done |
| **C** | Variable Usage UI (page editor) | Small | B | ✅ Done |
| **D** | Robustness (stale refs, repair) | Small | C | Pending |

**Total new files:** 8
**Total modified files:** ~14
**Total new tests:** ~20

---

## Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────────┐
│                        FLOW EDITOR                                   │
│                                                                      │
│  ┌──────────────────┐   ┌──────────────────┐   ┌──────────────────┐ │
│  │  Condition Node   │   │ Instruction Node  │   │  Dialogue Node   │ │
│  │  (reads vars)     │   │  (writes vars)    │   │  input_condition │ │
│  │                   │   │                   │   │  (reads vars)    │ │
│  │  rules: [         │   │  assignments: [   │   │                  │ │
│  │   {page, var,     │   │   {page, var,     │   │  (plain text     │ │
│  │    op, value}     │   │    op, value}     │   │   for now)       │ │
│  │  ]                │   │  ]                │   │                  │ │
│  └────────┬─────────┘   └────────┬─────────┘   └──────────────────┘ │
│           │                      │                                   │
│           │ on save              │ on save                           │
│           ▼                      ▼                                   │
│  ┌──────────────────────────────────────────────────────────────────┐│
│  │           VariableReferenceTracker                               ││
│  │                                                                  ││
│  │  1. Delete old refs for this node                                ││
│  │  2. Parse rules/assignments from node.data                       ││
│  │  3. Resolve page_shortcut + variable_name → block_id             ││
│  │  4. INSERT variable_references (node_id, block_id, "read"|"write")│
│  └──────────────────────────────────┬───────────────────────────────┘│
└─────────────────────────────────────┼────────────────────────────────┘
                                      │
                              ┌───────▼───────┐
                              │  variable_    │
                              │  references   │
                              │  table        │
                              │               │
                              │  flow_node_id │
                              │  block_id     │
                              │  kind         │
                              └───────┬───────┘
                                      │
┌─────────────────────────────────────┼────────────────────────────────┐
│                        PAGE EDITOR  │                                │
│                                     ▼                                │
│  ┌──────────────────────────────────────────────────────────────────┐│
│  │  Variable: health (number)                      Current value: 100│
│  │                                                                  ││
│  │  📖 Read by:                                                     ││
│  │    Flow "Main Quest" → Condition node                [Navigate]  ││
│  │    Flow "Side Quest" → Condition node                [Navigate]  ││
│  │                                                                  ││
│  │  ✏️ Modified by:                                                  ││
│  │    Flow "Main Quest" → Instruction (health += 10)    [Navigate]  ││
│  │    Flow "Combat"     → Instruction (health -= 20)    [Navigate]  ││
│  └──────────────────────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────────────────────┘
```

---

## Phase A: Instruction Node

### A1. Domain Logic

**New file:** `lib/storyarn/flows/instruction.ex`

Mirror the structure of `lib/storyarn/flows/condition.ex`. Pure domain module — no Phoenix dependencies.

```elixir
defmodule Storyarn.Flows.Instruction do
  @moduledoc """
  Domain logic for Instruction node assignments.

  The "write" counterpart to Condition (which is "read").
  Manages a list of variable assignments within an instruction node.
  """

  # Operators grouped by variable type
  @number_operators ~w(set add subtract)
  @boolean_operators ~w(set_true set_false toggle)
  @text_operators ~w(set clear)
  @select_operators ~w(set)
  @date_operators ~w(set)

  # Value types for assignment values
  @value_types ~w(literal variable_ref)

  # Public API — mirror Condition's interface:

  @spec operators_for_type(String.t()) :: [String.t()]
  # "number" → @number_operators
  # "boolean" → @boolean_operators
  # "text" | "rich_text" → @text_operators
  # "select" | "multi_select" → @select_operators
  # "date" → @date_operators
  # _ → @text_operators (fallback)

  @spec operator_label(String.t()) :: String.t()
  # "set" → "="
  # "add" → "+="
  # "subtract" → "-="
  # "set_true" → "= true"
  # "set_false" → "= false"
  # "toggle" → "toggle"
  # "clear" → "clear"

  @spec operator_requires_value?(String.t()) :: boolean()
  # false for: set_true, set_false, toggle, clear
  # true for everything else

  @spec valid_value_type?(String.t()) :: boolean()
  # true for "literal" and "variable_ref"

  @spec new() :: list()
  # Returns [] (empty assignments list)

  @spec add_assignment(list()) :: list()
  # Appends %{"id" => "assign_#{unique_int}", "page" => nil, "variable" => nil,
  #           "operator" => "set", "value" => nil, "value_type" => "literal", "value_page" => nil}

  @spec remove_assignment(list(), String.t()) :: list()
  # Filters out assignment with matching id

  @spec update_assignment(list(), String.t(), String.t(), any()) :: list()
  # Updates a single field of an assignment by its id
  # Fields: "page", "variable", "operator", "value", "value_type", "value_page"
  # When "value_type" changes to "literal" → clear "value_page"
  # When "value_type" changes to "variable_ref" → clear "value" (will be set via value_page + value dropdowns)

  @spec format_assignment_short(map()) :: String.t()
  # Returns human-readable string, e.g.:
  #
  # Literal value:
  # %{"page" => "mc.jaime", "variable" => "health", "operator" => "add", "value" => "10", "value_type" => "literal"}
  # → "mc.jaime.health += 10"
  #
  # Variable reference:
  # %{"page" => "mc.link", "variable" => "hasMasterSword", "operator" => "set",
  #   "value_type" => "variable_ref", "value_page" => "global.quests", "value" => "masterSwordDone"}
  # → "mc.link.hasMasterSword = global.quests.masterSwordDone"
  #
  # No-value operators:
  # %{"page" => "mc.jaime", "variable" => "alive", "operator" => "set_true"}
  # → "mc.jaime.alive = true"
end
```

**Assignment data structure:**

```elixir
# Literal value assignment
%{
  "id" => "assign_12345",        # unique, auto-generated
  "page" => "mc.jaime",          # target page shortcut (string)
  "variable" => "health",        # target variable_name (string)
  "operator" => "add",           # write operator
  "value" => "10",               # literal value (string, parsed by game engine)
  "value_type" => "literal",     # "literal" (default) | "variable_ref"
  "value_page" => nil             # only used when value_type == "variable_ref"
}

# Variable reference assignment
%{
  "id" => "assign_67890",
  "page" => "mc.link",                         # target page shortcut
  "variable" => "hasMasterSword",              # target variable_name
  "operator" => "set",                         # write operator
  "value" => "questToGetMasterSwordFinished",  # source variable_name
  "value_type" => "variable_ref",              # referencing another variable
  "value_page" => "pages.globalVariables"      # source page shortcut
}
```

**Operator sentence templates for UI:**

Each operator defines a sentence template. Static words are rendered as plain text, `[slots]` are inline combobox inputs. The sentence structure changes based on the operator:

| Operator | Sentence Template | Example Render |
|----------|-------------------|----------------|
| `set` | `Set [page]·[variable] to [value]` | `Set mc.jaime · health to 100` |
| `add` | `Add [value] to [page]·[variable]` | `Add 10 to mc.jaime · health` |
| `subtract` | `Subtract [value] from [page]·[variable]` | `Subtract 20 from mc.jaime · health` |
| `set_true` | `Set [page]·[variable] to true` | `Set mc.zelda · hasMasterSword to true` |
| `set_false` | `Set [page]·[variable] to false` | `Set mc.jaime · isAlive to false` |
| `toggle` | `Toggle [page]·[variable]` | `Toggle mc.jaime · isAlive` |
| `clear` | `Clear [page]·[variable]` | `Clear mc.jaime · name` |

When `value_type == "variable_ref"`, the value slot becomes a page·variable combobox:

| Operator | Sentence Template (variable_ref) | Example Render |
|----------|----------------------------------|----------------|
| `set` | `Set [page]·[variable] to [src_page]·[src_variable]` | `Set mc.link · hasMasterSword to global.quests · masterSwordDone` |
| `add` | `Add [src_page]·[src_variable] to [page]·[variable]` | `Add items.potion · value to mc.jaime · health` |
| `subtract` | `Subtract [src_page]·[src_variable] from [page]·[variable]` | `Subtract enemy.boss · damage from mc.jaime · health` |

**Note:** Operators that don't require a value (`set_true`, `set_false`, `toggle`, `clear`) ignore `value_type` entirely — the toggle between literal/variable_ref is hidden for these operators.

---

### A2. Node Type Registry

**Modify:** `lib/storyarn_web/live/flow_live/node_type_registry.ex`

Update `default_data/1` and `extract_form_data/2`:

```elixir
def default_data("instruction") do
  %{
    "assignments" => [],
    "description" => ""
  }
end

def extract_form_data("instruction", data) do
  %{
    "assignments" => data["assignments"] || [],
    "description" => data["description"] || ""
  }
end
```

**Note:** Remove the old `"action"` and `"parameters"` fields. Since we haven't launched, no migration needed — the new default_data replaces the old one.

---

### A3. Sentence-Flow Builder (JS Component)

> **Architecture decision:** The builder is a **JS-driven component** (LiveView hook) rather than server-rendered HEEx. This provides a more fluid UX: search-as-you-type comboboxes, auto-advance between inputs, and inline borderless styling — all without roundtrips per keystroke. Communication with LiveView is limited to: (1) receiving initial data + variables on mount, and (2) pushing the final `assignments` array back on change.

**New files:**
- `assets/js/hooks/instruction_builder/instruction_builder_hook.js` — LiveView hook (entry point)
- `assets/js/hooks/instruction_builder/assignment_row.js` — One sentence-flow row
- `assets/js/hooks/instruction_builder/combobox.js` — Searchable combobox widget
- `assets/js/hooks/instruction_builder/sentence_templates.js` — Operator → sentence template mapping
- `lib/storyarn_web/components/instruction_builder.ex` — Thin HEEx wrapper that renders the hook container

**Thin HEEx wrapper** (`instruction_builder.ex`):

```elixir
defmodule StoryarnWeb.Components.InstructionBuilder do
  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  attr :id, :string, required: true
  attr :assignments, :list, default: []
  attr :variables, :list, default: []
  attr :can_edit, :boolean, default: true

  def instruction_builder(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="InstructionBuilder"
      data-assignments={Jason.encode!(@assignments)}
      data-variables={Jason.encode!(@variables)}
      data-can-edit={Jason.encode!(@can_edit)}
      class="instruction-builder"
    >
      <%!-- JS renders content here --%>
    </div>
    """
  end
end
```

#### Visual Design: Sentence-Flow UI

Each assignment row reads like a sentence. Inputs are **inline, borderless, with only a bottom border** — they feel like blanks in a sentence, not form fields. The user types as if writing text, but is actually moving between searchable comboboxes.

```
┌─────────────────────────────────────────────────────────────────────┐
│                                                                       │
│  Set  mc.jaime · health  to  100                              [✕]   │
│       ‾‾‾‾‾‾‾‾   ‾‾‾‾‾‾      ‾‾‾                                  │
│       combobox    combobox     combobox/input                        │
│                                                                       │
│  Add  10  to  mc.jaime · gold                                 [✕]   │
│       ‾‾                ‾‾‾‾                                        │
│                                                                       │
│  Set  mc.link · hasMasterSword  to  global.quests · swordDone [✕]   │
│       ‾‾‾‾‾‾‾   ‾‾‾‾‾‾‾‾‾‾‾‾      ‾‾‾‾‾‾‾‾‾‾‾‾‾  ‾‾‾‾‾‾‾‾      │
│       combobox   combobox           combobox         combobox        │
│                                     (value_type = variable_ref)      │
│                                                                       │
│  Toggle  mc.jaime · isAlive                                   [✕]   │
│                                                                       │
│  [+ Add assignment]                                                   │
│                                                                       │
└─────────────────────────────────────────────────────────────────────┘
```

**Key visual principles:**
- Static words ("Set", "to", "Add", "from") are plain text, styled as `text-base-content/50`
- Combobox inputs have no visible border — only a subtle `border-bottom` (1px dashed) when empty, solid when filled
- Input width auto-adjusts to content (JS measures text width + padding)
- The entire row has a single bottom divider separating it from the next row
- On hover, the row gets a subtle background highlight
- The `[✕]` button is only visible on row hover

#### Combobox Widget

A reusable searchable combobox for page, variable, and value selection.

**Behavior:**
1. **Click or Tab into** → Shows full dropdown of options (grouped by page for variables)
2. **Type any characters** → Filters options in real-time (matches against label, slug, and shortcut)
3. **Arrow keys** → Navigate filtered options
4. **Enter** → Select highlighted option AND **auto-advance to next input in the row**
5. **Escape** → Close dropdown, keep current value
6. **Tab** → Close dropdown, keep current value, advance to next input

**Filtering logic:**
- Case-insensitive substring match against multiple fields
- For pages: matches `title` and `shortcut` (e.g., typing "zel" matches "Zelda" and "mc.zelda")
- For variables: matches `variable_name` and `block label` (e.g., typing "hea" matches "health" and "Health Points")
- Results grouped by page with sticky page headers in the dropdown

**Dropdown rendering:**
```
┌───────────────────────────────┐
│ 🔍 zel                        │  ← input with current search text
├───────────────────────────────┤
│ mc.zelda                      │  ← page group header (sticky)
│   health (number)             │
│   hasMasterSword (boolean)    │
│   questProgress (number)      │
│                               │
│ global.zelda_quests           │  ← another page group
│   zeldaApproval (number)      │
└───────────────────────────────┘
```

**Implementation notes:**
- Pure JS (no external library) — small enough to not need one
- Positioned absolutely below the input, flips up if near viewport bottom
- Max height with scroll for long lists
- Highlighted option follows arrow keys with scroll-into-view
- All options provided client-side on mount (avoids roundtrips for filtering)

#### Sentence Templates (`sentence_templates.js`)

```javascript
// Each template defines the order of elements in a row.
// "slot" entries are interactive (combobox/input), "text" entries are static labels.

export const SENTENCE_TEMPLATES = {
  set: [
    { type: "text", value: "Set" },
    { type: "slot", key: "page", placeholder: "page" },
    { type: "text", value: "·" },
    { type: "slot", key: "variable", placeholder: "variable" },
    { type: "text", value: "to" },
    { type: "slot", key: "value", placeholder: "value" },
  ],
  add: [
    { type: "text", value: "Add" },
    { type: "slot", key: "value", placeholder: "value" },
    { type: "text", value: "to" },
    { type: "slot", key: "page", placeholder: "page" },
    { type: "text", value: "·" },
    { type: "slot", key: "variable", placeholder: "variable" },
  ],
  subtract: [
    { type: "text", value: "Subtract" },
    { type: "slot", key: "value", placeholder: "value" },
    { type: "text", value: "from" },
    { type: "slot", key: "page", placeholder: "page" },
    { type: "text", value: "·" },
    { type: "slot", key: "variable", placeholder: "variable" },
  ],
  set_true: [
    { type: "text", value: "Set" },
    { type: "slot", key: "page", placeholder: "page" },
    { type: "text", value: "·" },
    { type: "slot", key: "variable", placeholder: "variable" },
    { type: "text", value: "to true" },
  ],
  set_false: [
    { type: "text", value: "Set" },
    { type: "slot", key: "page", placeholder: "page" },
    { type: "text", value: "·" },
    { type: "slot", key: "variable", placeholder: "variable" },
    { type: "text", value: "to false" },
  ],
  toggle: [
    { type: "text", value: "Toggle" },
    { type: "slot", key: "page", placeholder: "page" },
    { type: "text", value: "·" },
    { type: "slot", key: "variable", placeholder: "variable" },
  ],
  clear: [
    { type: "text", value: "Clear" },
    { type: "slot", key: "page", placeholder: "page" },
    { type: "text", value: "·" },
    { type: "slot", key: "variable", placeholder: "variable" },
  ],
};

// When value_type == "variable_ref", the "value" slot is replaced by two slots:
// { type: "slot", key: "value_page", placeholder: "page" }
// { type: "text", value: "·" }
// { type: "slot", key: "value", placeholder: "variable" }
```

#### Value Type Toggle

Within the sentence flow, the value slot has a small toggle icon inline:

```
Set  mc.jaime · health  to  [123] 100       ← literal mode (default)
Set  mc.jaime · health  to  [{x}] global.quests · swordDone  ← variable_ref mode
```

- `[123]` / `[{x}]` is a tiny clickable icon (12x12px) that appears before the value slot
- Only visible when the operator requires a value
- Clicking toggles between literal and variable_ref, clearing the current value
- The icon uses `text-base-content/30` and becomes `text-primary` on hover

#### Auto-Advance Logic

When a combobox selection is made (Enter or click):
1. Determine the next slot in the current sentence template
2. If next slot exists → focus it and open its dropdown
3. If no next slot (end of sentence) → focus the `[+ Add assignment]` button
4. If the operator changes → re-render the sentence template (the slots may reorder)

**Special case: operator change.** When the user selects a variable, the builder detects its type and auto-selects the first available operator. This may change the sentence template. The builder re-renders the row and focuses the next unfilled slot.

#### Hook Lifecycle (`instruction_builder_hook.js`)

```javascript
export const InstructionBuilder = {
  mounted() {
    this.assignments = JSON.parse(this.el.dataset.assignments);
    this.variables = JSON.parse(this.el.dataset.variables);
    this.canEdit = JSON.parse(this.el.dataset.canEdit);
    this.render();
  },

  updated() {
    // LiveView pushed new data (e.g., after another user's edit in collaboration)
    const newAssignments = JSON.parse(this.el.dataset.assignments);
    if (JSON.stringify(newAssignments) !== JSON.stringify(this.assignments)) {
      this.assignments = newAssignments;
      this.render();
    }
  },

  // Push changes back to LiveView
  pushAssignments() {
    this.pushEvent("update_instruction_builder", {
      action: "replace_all",
      assignments: this.assignments
    });
  },

  render() {
    // Render assignment rows + "Add" button into this.el
    // Each row is an AssignmentRow instance
  }
};
```

**Key architecture point:** The JS component owns the `assignments` array locally and pushes the entire array to LiveView on every meaningful change (add, remove, field change). This avoids the field-by-field event pattern and gives instant UI feedback. LiveView receives the full state and persists it.

#### CSS (Tailwind v4)

```css
/* In assets/css/app.css or a component-specific file */

.instruction-builder .assignment-row {
  @apply flex flex-wrap items-baseline gap-1 py-2 border-b border-base-300/30;
}

.instruction-builder .sentence-text {
  @apply text-sm text-base-content/50 select-none;
}

.instruction-builder .sentence-slot {
  @apply text-sm text-base-content font-medium bg-transparent
         border-0 border-b border-dashed border-base-content/20
         outline-none min-w-[3ch] px-0.5;
  /* Auto-width: set by JS based on content */
}

.instruction-builder .sentence-slot:focus {
  @apply border-solid border-primary;
}

.instruction-builder .sentence-slot.filled {
  @apply border-solid border-base-content/10;
}

.instruction-builder .sentence-slot::placeholder {
  @apply text-base-content/25 font-normal italic;
}

.instruction-builder .combobox-dropdown {
  @apply absolute z-50 mt-1 w-64 max-h-48 overflow-y-auto
         bg-base-100 border border-base-300 rounded-lg shadow-lg;
}

.instruction-builder .combobox-option {
  @apply px-3 py-1.5 text-sm cursor-pointer hover:bg-base-200;
}

.instruction-builder .combobox-option.highlighted {
  @apply bg-primary/10 text-primary;
}

.instruction-builder .combobox-group-header {
  @apply px-3 py-1 text-xs font-semibold text-base-content/40
         sticky top-0 bg-base-100;
}

.instruction-builder .value-type-toggle {
  @apply inline-flex items-center justify-center w-4 h-4 rounded
         text-[10px] text-base-content/30 hover:text-primary
         cursor-pointer select-none;
}
```

---

### A4. Panel Component

**New file:** `lib/storyarn_web/live/flow_live/components/panels/instruction_panel.ex`

```elixir
defmodule StoryarnWeb.FlowLive.Components.Panels.InstructionPanel do
  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.InstructionBuilder

  attr :form, :map, required: true
  attr :node, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :project_variables, :list, default: []

  def instruction_properties(assigns)
end
```

**Layout:**

```
┌─────────────────────────────────────────────┐
│ Description                                  │
│ ┌──────────────────────────────────────────┐ │
│ │ [text input: "Reward player for quest"]  │ │
│ └──────────────────────────────────────────┘ │
│                                              │
│ Assignments                                  │
│ ┌──────────────────────────────────────────┐ │
│ │ <.instruction_builder                    │ │
│ │   id={"instruction-builder-#{@node.id}"} │ │
│ │   assignments={@node.data["assignments"]}│ │
│ │   variables={@project_variables}         │ │
│ │   can_edit={@can_edit}                   │ │
│ │ />                                       │ │
│ └──────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

**Key details:**
- The description field uses `phx-blur="update_node_field"` + `phx-value-field="description"` (same pattern as exit node's `technical_id`).
- The `<.instruction_builder>` renders a `phx-hook="InstructionBuilder"` div. No `on_change` attr needed — the hook pushes events directly via `this.pushEvent()`.
- No `<.form>` wrapper for assignments — the JS component owns its own state and communicates via hook events.

---

### A5. Event Handler

**New file:** `lib/storyarn_web/live/flow_live/handlers/instruction_event_handlers.ex`

Since the JS component owns the assignments array client-side and pushes the full state on each change, the server-side handler is simpler than the condition builder's field-by-field approach:

```elixir
defmodule StoryarnWeb.FlowLive.Handlers.InstructionEventHandlers do
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias Storyarn.Flows
  alias StoryarnWeb.FlowLive.Helpers.FormHelpers

  import StoryarnWeb.FlowLive.Helpers.SocketHelpers

  @spec handle_update_instruction_builder(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_update_instruction_builder(%{"assignments" => assignments}, socket) do
    node = socket.assigns.selected_node

    # Sanitize: only keep known keys per assignment
    sanitized =
      Enum.map(assignments, fn assign ->
        Map.take(assign, ~w(id page variable operator value value_type value_page))
      end)

    updated_data = Map.put(node.data, "assignments", sanitized)

    case Flows.update_node_data(node, updated_data) do
      {:ok, updated_node, _meta} ->
        form = FormHelpers.node_data_to_form(updated_node)
        schedule_save_status_reset()

        {:noreply,
         socket
         |> reload_flow_data()
         |> assign(:selected_node, updated_node)
         |> assign(:node_form, form)
         |> assign(:save_status, :saved)
         |> push_event("node_updated", %{id: node.id, data: updated_node.data})}

      {:error, _} ->
        {:noreply, socket}
    end
  end
end
```

**Key difference from condition builder:** No dispatch logic, no field-level parsing. The JS hook pushes the complete `assignments` array, and the handler sanitizes and persists it. All add/remove/update logic lives in JS.

**Sanitization is important:** Since the data comes from the client, `Map.take/2` ensures only known keys are stored. This prevents injection of unexpected fields into node data.

---

### A6. Properties Panel + Show.ex Integration

**Modify:** `lib/storyarn_web/live/flow_live/components/properties_panels.ex`

Add alias and dispatch:

```elixir
alias StoryarnWeb.FlowLive.Components.Panels.InstructionPanel

# In node_properties_form/1, add before the default form wrapper:
<%= if @node.type == "condition" do %>
  <ConditionPanel.condition_properties ... />
<% else %>
  <%= if @node.type == "instruction" do %>
    <InstructionPanel.instruction_properties
      form={@form}
      node={@node}
      can_edit={@can_edit}
      project_variables={@project_variables}
    />
  <% else %>
    <.form for={@form} phx-change="update_node_data" phx-debounce="500">
      ...existing dispatch...
    </.form>
  <% end %>
<% end %>
```

**Key:** Instruction panel, like condition panel, renders OUTSIDE the `<.form>` wrapper because the builder uses its own hook-based event system (`this.pushEvent`).

**Modify:** `lib/storyarn_web/live/flow_live/show.ex`

Add the new event handler:

```elixir
# After the condition builder events:
def handle_event("update_instruction_builder", params, socket) do
  with_auth(:edit_content, socket, fn ->
    InstructionEventHandlers.handle_update_instruction_builder(params, socket)
  end)
end
```

Add alias: `alias StoryarnWeb.FlowLive.Handlers.InstructionEventHandlers`

---

### A7. Canvas Rendering

**Modify:** `assets/js/hooks/flow_canvas/components/node_formatters.js`

The canvas preview uses the same sentence-style format as the builder, but as plain text (no interactive inputs). Import `SENTENCE_TEMPLATES` from the shared module or duplicate the formatting logic.

Update `getPreviewText`:

```javascript
case "instruction": {
  const assignments = nodeData.assignments || [];
  if (assignments.length === 0) return "";
  return assignments
    .slice(0, 3)  // max 3 lines on canvas
    .map(a => formatAssignment(a))
    .filter(Boolean)
    .join("\n");
}
```

Add helper:

```javascript
function formatAssignment(assignment) {
  if (!assignment.page || !assignment.variable) return null;
  const ref = `${assignment.page}.${assignment.variable}`;

  // Sentence-style format matching the builder UI
  const op = assignment.operator || "set";

  // Value-less operators
  if (op === "set_true") return `Set ${ref} to true`;
  if (op === "set_false") return `Set ${ref} to false`;
  if (op === "toggle") return `Toggle ${ref}`;
  if (op === "clear") return `Clear ${ref}`;

  // Determine value display
  let valueDisplay;
  if (assignment.value_type === "variable_ref" && assignment.value_page && assignment.value) {
    valueDisplay = `${assignment.value_page}.${assignment.value}`;
  } else {
    valueDisplay = assignment.value || "?";
  }

  // Sentence templates
  if (op === "set") return `Set ${ref} to ${valueDisplay}`;
  if (op === "add") return `Add ${valueDisplay} to ${ref}`;
  if (op === "subtract") return `Subtract ${valueDisplay} from ${ref}`;

  return `Set ${ref} to ${valueDisplay}`;
}
```

**Modify:** `assets/js/hooks/flow_canvas/components/storyarn_node.js`

The existing rendering should handle multi-line preview text already. If not, ensure the instruction node body uses the same multi-line rendering as condition nodes (pre-wrap or line breaks). The instruction node uses the default `config.color` (zap yellow from the icon).

---

### A8. Remove from SimplePanels

**Modify:** `lib/storyarn_web/live/flow_live/components/panels/simple_panels.ex`

Remove the `"instruction"` case from `simple_properties/1`. It was:

```elixir
<% "instruction" -> %>
  <.input field={@form[:action]} ... />
  <.input field={@form[:parameters]} ... />
```

This is no longer needed since instruction routing goes to `InstructionPanel`.

---

### A9. Tests

**Add to:** `test/storyarn/flows_test.exs`

```elixir
describe "instruction nodes" do
  test "create instruction node with assignments"
  test "update instruction node assignments"
  test "delete instruction node"
  test "duplicate instruction node clears nothing (assignments are shared logic)"
end
```

**New file:** `test/storyarn/flows/instruction_test.exs`

```elixir
describe "Instruction" do
  test "new/0 returns empty list"
  test "add_assignment/1 appends with generated id and value_type literal"
  test "remove_assignment/2 removes by id"
  test "update_assignment/4 updates a field"
  test "update_assignment/4 clears value and value_page when toggling value_type"
  test "operators_for_type/1 returns correct operators per type"
  test "operator_requires_value?/1"
  test "valid_value_type?/1 accepts literal and variable_ref"
  test "format_assignment_short/1 formats literal value correctly"
  test "format_assignment_short/1 formats variable_ref as page.variable"
  test "format_assignment_short/1 formats no-value operators"
end
```

---

## Phase B: Variable Reference Tracking

### B1. Migration

**New file:** `priv/repo/migrations/XXXXXXXX_create_variable_references.exs`

```elixir
defmodule Storyarn.Repo.Migrations.CreateVariableReferences do
  use Ecto.Migration

  def change do
    create table(:variable_references) do
      add :flow_node_id, references(:flow_nodes, on_delete: :delete_all), null: false
      add :block_id, references(:blocks, on_delete: :delete_all), null: false
      add :kind, :string, null: false  # "read" or "write"

      timestamps()
    end

    create index(:variable_references, [:block_id, :kind])
    create index(:variable_references, [:flow_node_id])
    create unique_index(:variable_references, [:flow_node_id, :block_id, :kind])
  end
end
```

**Why `on_delete: :delete_all`:**
- When a flow node is deleted → its refs auto-delete (no orphans)
- When a block is deleted → refs to it auto-delete (no orphans)
- No manual cleanup needed for these cases

**Scalability note:** With 10,000 pages × ~5 variables = 50,000 blocks, and ~4,000 referencing nodes × ~2 refs each = ~8,000 rows. The `(block_id, kind)` index handles lookups in microseconds even at 100x this scale.

---

### B2. Schema

**New file:** `lib/storyarn/flows/variable_reference.ex`

```elixir
defmodule Storyarn.Flows.VariableReference do
  use Ecto.Schema
  import Ecto.Changeset

  schema "variable_references" do
    belongs_to :flow_node, Storyarn.Flows.FlowNode
    belongs_to :block, Storyarn.Pages.Block
    field :kind, :string  # "read" | "write"

    timestamps()
  end

  def changeset(ref, attrs) do
    ref
    |> cast(attrs, [:flow_node_id, :block_id, :kind])
    |> validate_required([:flow_node_id, :block_id, :kind])
    |> validate_inclusion(:kind, ["read", "write"])
    |> unique_constraint([:flow_node_id, :block_id, :kind])
  end
end
```

---

### B3. Tracker Module

**New file:** `lib/storyarn/flows/variable_reference_tracker.ex`

```elixir
defmodule Storyarn.Flows.VariableReferenceTracker do
  @moduledoc """
  Tracks which flow nodes read/write which variables (blocks).

  Called after every node data save. Extracts variable references from
  the node's structured data (condition rules → reads, instruction
  assignments → writes) and upserts them into the variable_references table.
  """

  import Ecto.Query
  alias Storyarn.Flows.{FlowNode, VariableReference}
  alias Storyarn.Pages.{Block, Page}
  alias Storyarn.Repo

  @doc """
  Updates variable references for a node after its data changes.
  Dispatches to the correct extractor based on node type.
  """
  @spec update_references(FlowNode.t()) :: :ok
  def update_references(%FlowNode{} = node) do
    refs =
      case node.type do
        "instruction" -> extract_write_refs(node)
        "condition" -> extract_read_refs(node)
        _ -> []
      end

    replace_references(node.id, refs)
  end

  @doc """
  Deletes all variable references for a node.
  Called when a node is deleted (as backup — DB cascade handles this too).
  """
  @spec delete_references(integer()) :: :ok
  def delete_references(node_id) do
    from(vr in VariableReference, where: vr.flow_node_id == ^node_id)
    |> Repo.delete_all()
    :ok
  end

  @doc """
  Returns all variable references for a block, with flow/node info.
  Used by the page editor's variable usage section.
  """
  @spec get_variable_usage(integer(), integer()) :: [map()]
  def get_variable_usage(block_id, project_id) do
    from(vr in VariableReference,
      join: n in FlowNode, on: n.id == vr.flow_node_id,
      join: f in assoc(n, :flow),
      where: vr.block_id == ^block_id,
      where: f.project_id == ^project_id,
      where: is_nil(f.deleted_at),
      select: %{
        kind: vr.kind,
        flow_id: f.id,
        flow_name: f.name,
        flow_shortcut: f.shortcut,
        node_id: n.id,
        node_type: n.type,
        node_data: n.data
      },
      order_by: [asc: vr.kind, asc: f.name]
    )
    |> Repo.all()
  end

  @doc """
  Counts variable references for a block, grouped by kind.
  Returns %{"read" => N, "write" => M}.
  """
  @spec count_variable_usage(integer()) :: map()
  def count_variable_usage(block_id) do
    from(vr in VariableReference,
      where: vr.block_id == ^block_id,
      group_by: vr.kind,
      select: {vr.kind, count(vr.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  # Private implementation

  defp extract_write_refs(node) do
    assignments = node.data["assignments"] || []

    Enum.flat_map(assignments, fn assign ->
      # Write ref for target variable
      write_ref =
        case resolve_block(node.flow_id, assign["page"], assign["variable"]) do
          nil -> []
          block_id -> [%{block_id: block_id, kind: "write"}]
        end

      # Read ref for source variable (when value_type == "variable_ref")
      read_ref =
        if assign["value_type"] == "variable_ref" do
          case resolve_block(node.flow_id, assign["value_page"], assign["value"]) do
            nil -> []
            block_id -> [%{block_id: block_id, kind: "read"}]
          end
        else
          []
        end

      write_ref ++ read_ref
    end)
  end

  defp extract_read_refs(node) do
    rules = get_in(node.data, ["condition", "rules"]) || []

    Enum.flat_map(rules, fn rule ->
      case resolve_block(node.flow_id, rule["page"], rule["variable"]) do
        nil -> []
        block_id -> [%{block_id: block_id, kind: "read"}]
      end
    end)
  end

  defp resolve_block(flow_id, page_shortcut, variable_name)
       when is_binary(page_shortcut) and page_shortcut != "" and
            is_binary(variable_name) and variable_name != "" do
    # Get project_id from flow
    flow = Repo.get!(Storyarn.Flows.Flow, flow_id)

    from(b in Block,
      join: p in Page, on: p.id == b.page_id,
      where: p.project_id == ^flow.project_id,
      where: p.shortcut == ^page_shortcut,
      where: b.variable_name == ^variable_name,
      where: is_nil(p.deleted_at),
      where: is_nil(b.deleted_at),
      select: b.id,
      limit: 1
    )
    |> Repo.one()
  end

  defp resolve_block(_, _, _), do: nil

  defp replace_references(node_id, refs) do
    # Atomic: delete old → insert new
    Repo.transaction(fn ->
      from(vr in VariableReference, where: vr.flow_node_id == ^node_id)
      |> Repo.delete_all()

      # Deduplicate (same block + kind should only appear once)
      unique_refs = Enum.uniq_by(refs, fn r -> {r.block_id, r.kind} end)

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      entries =
        Enum.map(unique_refs, fn ref ->
          %{
            flow_node_id: node_id,
            block_id: ref.block_id,
            kind: ref.kind,
            inserted_at: now,
            updated_at: now
          }
        end)

      if entries != [] do
        Repo.insert_all(VariableReference, entries, on_conflict: :nothing)
      end
    end)

    :ok
  end
end
```

**Performance note on `resolve_block`:** This runs a query per assignment/rule. For a node with 5 assignments, that's 5 queries. This is fine because:
1. Nodes rarely have >10 assignments
2. It only runs on save (not on every render)
3. The query uses indexed columns (shortcut, variable_name)

If performance becomes an issue later, batch-resolve all shortcuts in one query.

---

### B4. Integration in NodeCrud

**Modify:** `lib/storyarn/flows/node_crud.ex`

Add alias:

```elixir
alias Storyarn.Flows.VariableReferenceTracker
```

In `do_update_node_data/2`, after `ReferenceTracker.update_flow_node_references(updated_node)`:

```elixir
defp do_update_node_data(node, data) do
  result =
    node
    |> FlowNode.data_changeset(%{data: data})
    |> Repo.update()

  case result do
    {:ok, updated_node} ->
      ReferenceTracker.update_flow_node_references(updated_node)
      VariableReferenceTracker.update_references(updated_node)
      {:ok, updated_node}

    error ->
      error
  end
end
```

In `delete_node/1`, the variable references are auto-cleaned by `ON DELETE CASCADE` on the FK. But for safety, you can also call `VariableReferenceTracker.delete_references(node.id)` alongside `ReferenceTracker.delete_flow_node_references(node.id)`.

---

### B5. Facade Delegates

**Modify:** `lib/storyarn/flows.ex`

Add delegates:

```elixir
defdelegate get_variable_usage(block_id, project_id),
  to: Storyarn.Flows.VariableReferenceTracker

defdelegate count_variable_usage(block_id),
  to: Storyarn.Flows.VariableReferenceTracker
```

---

### B6. Tests

**New file:** `test/storyarn/flows/variable_reference_tracker_test.exs`

```elixir
describe "VariableReferenceTracker" do
  test "instruction node creates write references"
  test "instruction node with variable_ref creates write AND read references"
  test "condition node creates read references"
  test "updating node replaces old references"
  test "deleting node cascades reference deletion"
  test "deleting block cascades reference deletion"
  test "unresolvable variable creates no reference"
  test "unresolvable variable_ref source creates write ref but no read ref"
  test "get_variable_usage returns reads and writes with flow info"
  test "count_variable_usage returns grouped counts"
  test "references from deleted flows are excluded from usage"
end
```

---

## Phase C: Variable Usage UI

### C1. Variable Usage Component

**New file:** `lib/storyarn_web/live/page_live/components/variable_usage_section.ex`

This is a `Phoenix.LiveComponent` (like `BacklinksSection`) for lazy loading.

```elixir
defmodule StoryarnWeb.PageLive.Components.VariableUsageSection do
  use StoryarnWeb, :live_component
  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Flows

  # Attrs from parent:
  # :page — current page
  # :project — current project
  # :blocks — list of variable blocks for this page

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:usage_map, fn -> nil end)

    socket =
      if is_nil(socket.assigns.usage_map) do
        load_usage(socket)
      else
        socket
      end

    {:ok, socket}
  end

  defp load_usage(socket) do
    blocks = socket.assigns.blocks
    project_id = socket.assigns.project.id

    # Build a map: block_id => %{reads: [...], writes: [...]}
    usage_map =
      blocks
      |> Enum.filter(&is_variable?/1)
      |> Map.new(fn block ->
        usage = Flows.get_variable_usage(block.id, project_id)
        reads = Enum.filter(usage, &(&1.kind == "read"))
        writes = Enum.filter(usage, &(&1.kind == "write"))
        {block.id, %{reads: reads, writes: writes}}
      end)

    assign(socket, :usage_map, usage_map)
  end

  defp is_variable?(block) do
    block.variable_name != nil and
      block.variable_name != "" and
      not block.is_constant
  end
end
```

**Render each variable block:**

```heex
<div :for={block <- @variable_blocks} class="mb-4">
  <h4 class="text-sm font-medium">{block.config["label"] || block.variable_name}</h4>
  <p class="text-xs text-base-content/50">{@page.shortcut}.{block.variable_name} ({block.type})</p>

  <%= if usage = @usage_map[block.id] do %>
    <!-- Writes -->
    <div :if={usage.writes != []} class="mt-2">
      <span class="text-xs font-semibold text-warning">{gettext("Modified by")}</span>
      <div :for={ref <- usage.writes} class="ml-2">
        <.link
          navigate={flow_node_path(@project, ref.flow_id, ref.node_id)}
          class="text-xs link link-hover"
        >
          {ref.flow_name} → {ref.node_type}
          <span class="text-base-content/40">{format_ref_detail(ref)}</span>
        </.link>
      </div>
    </div>

    <!-- Reads -->
    <div :if={usage.reads != []} class="mt-2">
      <span class="text-xs font-semibold text-info">{gettext("Read by")}</span>
      <div :for={ref <- usage.reads} class="ml-2">
        <.link
          navigate={flow_node_path(@project, ref.flow_id, ref.node_id)}
          class="text-xs link link-hover"
        >
          {ref.flow_name} → {ref.node_type}
        </.link>
      </div>
    </div>

    <p :if={usage.reads == [] and usage.writes == []}
       class="text-xs text-base-content/40 italic mt-1">
      {gettext("Not used in any flow.")}
    </p>
  <% end %>
</div>
```

**`format_ref_detail/1`** — for instruction nodes, extract the assignment that matches this variable and show the operator + value (e.g., `"+= 10"`).

---

### C2. Navigation Helper

**`flow_node_path/3`:**

```elixir
defp flow_node_path(project, flow_id, node_id) do
  ~p"/workspaces/#{project.workspace_slug}/projects/#{project.slug}/flows/#{flow_id}?node=#{node_id}"
end
```

**Modify:** `lib/storyarn_web/live/flow_live/show.ex`

On mount, check for `?node=X` query param:

```elixir
# In handle_params or setup_flow_view:
socket =
  case params["node"] do
    nil -> socket
    node_id -> push_event(socket, "navigate_to_node", %{node_db_id: node_id})
  end
```

This reuses the existing `navigate_to_node` JS handler that zooms and highlights a node.

---

### C3. Page Editor Integration

**Modify:** `lib/storyarn_web/live/page_live/components/references_tab.ex`

Add the variable usage section alongside existing backlinks:

```elixir
def render(assigns) do
  ~H"""
  <div class="space-y-6">
    <.live_component
      module={VariableUsageSection}
      id="variable-usage"
      page={@page}
      project={@project}
      blocks={@blocks}
    />

    <.live_component
      module={BacklinksSection}
      id="backlinks"
      page={@page}
      project={@project}
    />

    <.live_component
      module={VersionsSection}
      ...existing attrs...
    />
  </div>
  """
end
```

The `@blocks` assign needs to be passed from `page_live/show.ex`. It should already be available (check the existing assigns). If not, add `blocks: Pages.list_blocks(page.id)` to the tab component.

---

### C4. Tests

**Add to:** page live tests or create new test file.

```elixir
describe "variable usage" do
  test "shows instruction nodes that write to a variable"
  test "shows condition nodes that read a variable"
  test "navigate link goes to correct flow with node param"
  test "variables with no usage show empty state"
end
```

---

## Phase D: Robustness

### D1. Stale Reference Detection

When rendering variable usage, the `variable_references` table has `block_id` (still valid), but the node's JSON might have stale `page` or `variable` strings.

**Add to `VariableReferenceTracker`:**

```elixir
@spec check_stale_references(integer(), integer()) :: [map()]
def check_stale_references(block_id, project_id) do
  # Get the block's current page shortcut and variable name
  block_info =
    from(b in Block,
      join: p in Page, on: p.id == b.page_id,
      where: b.id == ^block_id,
      select: %{page_shortcut: p.shortcut, variable_name: b.variable_name}
    )
    |> Repo.one()

  if block_info do
    # Get all references to this block
    refs = get_variable_usage(block_id, project_id)

    Enum.map(refs, fn ref ->
      # Check if the node's JSON still matches
      stale =
        case ref.node_type do
          "instruction" ->
            assignments = ref.node_data["assignments"] || []
            not Enum.any?(assignments, fn a ->
              # Check target variable match
              target_match =
                a["page"] == block_info.page_shortcut and
                  a["variable"] == block_info.variable_name

              # Check source variable match (for variable_ref assignments)
              source_match =
                a["value_type"] == "variable_ref" and
                  a["value_page"] == block_info.page_shortcut and
                  a["value"] == block_info.variable_name

              target_match or source_match
            end)

          "condition" ->
            rules = get_in(ref.node_data, ["condition", "rules"]) || []
            not Enum.any?(rules, fn r ->
              r["page"] == block_info.page_shortcut and
                r["variable"] == block_info.variable_name
            end)

          _ ->
            false
        end

      Map.put(ref, :stale, stale)
    end)
  else
    []
  end
end
```

In the variable usage UI, stale references get a warning badge: "Reference may be outdated".

---

### D2. Bulk Repair

**Add to `VariableReferenceTracker`:**

```elixir
@spec repair_stale_references(integer()) :: {:ok, non_neg_integer()}
def repair_stale_references(project_id) do
  # 1. Get all variable references for this project
  # 2. For each, check if the node's JSON matches the block's current shortcut/name
  # 3. If stale, update the node's data to use current values
  # 4. Return count of repaired references
end
```

This is a project-level action, accessible from project settings or via a maintenance task.

---

### D3. Canvas Indicator

When a flow node has stale variable references, show a warning indicator on the canvas. This is lower priority and can be deferred.

---

## File Summary

### New Files (11)

| File | Phase | Purpose |
|------|-------|---------|
| `lib/storyarn/flows/instruction.ex` | A | Domain logic |
| `lib/storyarn_web/components/instruction_builder.ex` | A | Thin HEEx wrapper (renders hook container) |
| `assets/js/hooks/instruction_builder/instruction_builder_hook.js` | A | LiveView hook (entry point, state management) |
| `assets/js/hooks/instruction_builder/assignment_row.js` | A | Sentence-flow row rendering |
| `assets/js/hooks/instruction_builder/combobox.js` | A | Searchable combobox widget |
| `assets/js/hooks/instruction_builder/sentence_templates.js` | A | Operator → sentence template mapping |
| `lib/storyarn_web/live/flow_live/components/panels/instruction_panel.ex` | A | Panel UI |
| `lib/storyarn_web/live/flow_live/handlers/instruction_event_handlers.ex` | A | Event handler (receives full state from JS) |
| `priv/repo/migrations/XXXXXXXX_create_variable_references.exs` | B | DB migration |
| `lib/storyarn/flows/variable_reference.ex` | B | Ecto schema |
| `lib/storyarn/flows/variable_reference_tracker.ex` | B | Tracking logic |
| `lib/storyarn_web/live/page_live/components/variable_usage_section.ex` | C | Page UI |

### Modified Files (~14)

| File | Phase | Changes |
|------|-------|---------|
| `lib/storyarn_web/live/flow_live/node_type_registry.ex` | A | default_data, extract_form_data |
| `lib/storyarn_web/live/flow_live/components/panels/simple_panels.ex` | A | Remove instruction case |
| `lib/storyarn_web/live/flow_live/components/properties_panels.ex` | A | Route to InstructionPanel |
| `lib/storyarn_web/live/flow_live/show.ex` | A+C | New event + node query param |
| `assets/js/hooks/flow_canvas/components/node_formatters.js` | A | Sentence-style instruction preview |
| `assets/js/hooks/flow_canvas/components/storyarn_node.js` | A | Instruction rendering (if needed) |
| `assets/js/hooks/index.js` | A | Register InstructionBuilder hook |
| `assets/css/app.css` | A | Instruction builder styles |
| `lib/storyarn/flows/node_crud.ex` | B | Integrate variable tracker |
| `lib/storyarn/flows.ex` | B | Facade delegates |
| `lib/storyarn_web/live/page_live/components/references_tab.ex` | C | Add variable usage |
| `lib/storyarn_web/live/page_live/show.ex` | C | Pass blocks to tab |
| `test/storyarn/flows_test.exs` | A | Instruction node tests |
| New test files | A+B | Domain + tracker tests |

---

## Execution Order

```
Phase A (Instruction Node):
  A1 → A2 → A3 → A4 → A5 → A6 → A7 → A8 → A9

Phase B (Variable Tracking):
  B1 → B2 → B3 → B4 → B5 → B6

Phase C (Variable Usage UI):
  C1 → C2 → C3 → C4

Phase D (Robustness):
  D1 → D2 → D3
```

Each phase should be committed separately.

---

## Verification Checklist

### Phase A ✅
- [x] `mix test` — all tests pass (576 tests, 0 failures + 35 new instruction tests)
- [x] Create instruction node → panel shows sentence-flow assignment builder
- [x] Builder renders as inline sentence: "Set _page_ · _variable_ to _value_"
- [x] All inputs are borderless with bottom border only (sentence-flow style)
- [x] Input width auto-adjusts to content
- [x] **Combobox search:** Type in page input → filters pages by title and shortcut
- [x] **Combobox search:** Type in variable input → filters variables by name and label
- [x] **Combobox dropdown:** Options grouped by page with sticky headers
- [x] **Auto-advance:** Selecting a page → auto-focuses variable combobox
- [x] **Auto-advance:** Selecting a variable → auto-selects operator and focuses value input
- [x] **Auto-advance:** Completing last input → focuses "+ Add assignment" button
- [x] Select variable → sentence template changes based on variable type (operator auto-selected)
- [x] Boolean variable → sentence reads "Set _page_ · _variable_ to true" (no value input, no toggle)
- [x] Number variable → shows set/add/subtract; "Add _value_ to _page_ · _variable_"
- [x] Value type toggle `[123]`/`[{x}]` visible for operators that require a value
- [x] Toggle to `{x}` → value slot becomes two comboboxes (source page + source variable)
- [x] Toggle back to `123` → clears source and shows typed value input
- [x] Canvas preview uses sentence format: "Set mc.link.hasMasterSword to global.quests.masterSwordDone"
- [x] Canvas preview for literal: "Add 10 to mc.jaime.health"
- [x] Description field saves via blur
- [x] Duplicate instruction node preserves assignments (including value_type)
- [x] Collaboration: external update via `handleEvent("node_updated")` refreshes builder

### Phase B ✅
- [x] `mix ecto.migrate` — migration runs (20260207004821_create_variable_references)
- [x] Save instruction node (literal) → variable_references table has write entry
- [x] Save instruction node (variable_ref) → variable_references table has write entry AND read entry (for source variable)
- [x] Save condition node → variable_references table has read entries
- [x] Delete node → references cascade deleted
- [x] Delete block → references cascade deleted
- [x] Unresolvable variable (bad shortcut) → no reference created, no error
- [x] `mix test` — 592 tests, 0 failures (15 new tracker tests)

### Phase C ✅
- [x] Page editor → References tab → variable usage section visible
- [x] Shows "Modified by" (warning/yellow) for variables written by instruction nodes
- [x] Shows "Read by" (info/blue) for variables read by condition nodes
- [x] Click navigate → opens flow editor zoomed to the node (`?node=X` param)
- [x] Variables with no usage show "No variables on this page are used in any flow yet."
- [x] Pages without variables don't show the section at all
- [x] Inline detail for write refs shows operator + value (e.g., `+= 10`, `= true`)
- [x] `mix test` — 597 tests, 0 failures (5 new LiveView tests)

### Phase D
- [ ] Rename page shortcut → variable usage still shows (block_id FK intact)
- [ ] Node JSON is stale → UI shows warning badge
- [ ] Repair action updates node JSON to current values

---

## Future Work (Out of Scope)

These are NOT part of this plan but should be noted. See `FUTURE_FEATURES.md` for detailed design docs on items marked with *.

1. **Dialogue `output_instruction` → structured builder** — Currently plain text. When converted to structured data, reuse `instruction_builder` hook and add write tracking.
2. **Dialogue `input_condition` → structured builder** — Currently plain text. When converted, reuse `condition_builder` and add read tracking.
3. **Cross-flow variable analysis** — "Show me all flows that touch this variable" as a project-level view.
4. **Variable rename propagation** — When a page shortcut or variable name changes, auto-update all referencing node data (not just the reference table).
5. **Export integration** — Include variable reference graph in export format.
6. ***Expression text mode** — Alternative text input for power users (articy:expresso-like). See FUTURE_FEATURES.md.
7. ***Conditional assignments ("When...change...to")** — Inline conditions on assignments. See FUTURE_FEATURES.md.
8. ***Slash commands in value input** — `/page` to switch to variable selector. See FUTURE_FEATURES.md.
