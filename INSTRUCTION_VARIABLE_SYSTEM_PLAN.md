# Instruction Node + Variable Reference System

> **Status**: Pending
> **Date**: February 6, 2026
> **Scope**: Instruction node visual builder, variable write/read tracking, variable usage UI on pages

---

## Overview

Four phases that build on each other:

| Phase | What | Effort | Depends on |
|-------|------|--------|------------|
| **A** | Instruction Node (visual builder) | Medium | Nothing |
| **B** | Variable Reference Tracking (DB + tracker) | Medium | A |
| **C** | Variable Usage UI (page editor) | Small | B |
| **D** | Robustness (stale refs, repair) | Small | C |

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

  @spec new() :: list()
  # Returns [] (empty assignments list)

  @spec add_assignment(list()) :: list()
  # Appends %{"id" => "assign_#{unique_int}", "page" => nil, "variable" => nil, "operator" => "set", "value" => nil}

  @spec remove_assignment(list(), String.t()) :: list()
  # Filters out assignment with matching id

  @spec update_assignment(list(), String.t(), String.t(), any()) :: list()
  # Updates a single field of an assignment by its id
  # Fields: "page", "variable", "operator", "value"

  @spec format_assignment_short(map()) :: String.t()
  # Returns human-readable string, e.g.:
  # %{"page" => "mc.jaime", "variable" => "health", "operator" => "add", "value" => "10"}
  # → "mc.jaime.health += 10"
  # %{"page" => "mc.jaime", "variable" => "alive", "operator" => "set_true"}
  # → "mc.jaime.alive = true"
end
```

**Assignment data structure:**

```elixir
%{
  "id" => "assign_12345",        # unique, auto-generated
  "page" => "mc.jaime",          # page shortcut (string)
  "variable" => "health",        # variable_name (string)
  "operator" => "add",           # write operator
  "value" => "10"                # value (string, parsed by game engine)
}
```

**Operator labels for UI:**

| Operator | Label | Example |
|----------|-------|---------|
| `set` | `=` | `health = 100` |
| `add` | `+=` | `health += 10` |
| `subtract` | `-=` | `health -= 20` |
| `set_true` | `= true` | `alive = true` |
| `set_false` | `= false` | `alive = false` |
| `toggle` | `toggle` | `toggle alive` |
| `clear` | `clear` | `clear name` |

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

### A3. Builder Component

**New file:** `lib/storyarn_web/components/instruction_builder.ex`

Mirror `lib/storyarn_web/components/condition_builder.ex` structure. This is a reusable component (could later be used for dialogue `output_instruction`).

```elixir
defmodule StoryarnWeb.Components.InstructionBuilder do
  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents, only: [icon: 1]

  alias Storyarn.Flows.Instruction

  # Reuse the grouping helper from ConditionBuilder
  import StoryarnWeb.Components.ConditionBuilder,
    only: [group_variables_by_page: 1, find_variable: 3]

  # Main component
  attr :id, :string, required: true
  attr :assignments, :list, default: []
  attr :variables, :list, default: []
  attr :on_change, :string, required: true
  attr :can_edit, :boolean, default: true
  def instruction_builder(assigns)

  # Sub-components (private):
  # assignment_row/1 — one row per assignment
  # value_input/1 — typed input (same pattern as condition_builder)
end
```

**Component layout:**

```
┌──────────────────────────────────────────────────────────────────┐
│  Assignment 1:                                                    │
│  ┌─────────────────────┐  ┌─────────────────────┐               │
│  │ [Page dropdown ▼]   │  │ [Variable dropdown ▼]│               │
│  └─────────────────────┘  └─────────────────────┘               │
│  ┌─────────────────────┐  ┌─────────────────────┐  ┌───┐       │
│  │ [Operator dropdown ▼]│  │ [Value input]       │  │ ✕ │       │
│  └─────────────────────┘  └─────────────────────┘  └───┘       │
├──────────────────────────────────────────────────────────────────┤
│  Assignment 2: ...                                               │
├──────────────────────────────────────────────────────────────────┤
│  [+ Add assignment]                                              │
└──────────────────────────────────────────────────────────────────┘
```

**Event dispatch pattern** — same as condition_builder:

| Action | Dispatch | Key params |
|--------|----------|------------|
| Add assignment | `phx-click={@on_change}` + `phx-value-action="add_assignment"` | `action: "add_assignment"` |
| Remove assignment | `phx-click={@on_change}` + `phx-value-action="remove_assignment"` + `phx-value-assignment-id={id}` | `action: "remove_assignment", assignment-id: "assign_123"` |
| Change field | `phx-change={@on_change}` on wrapping form | Input names: `assign_page_{id}`, `assign_variable_{id}`, `assign_operator_{id}`, `assign_value_{id}` |

**Value input** — same typed pattern as condition_builder's `value_input/1`:
- `select` / `multi_select` → dropdown from variable options
- `number` → `<input type="number">`
- `boolean` → dropdown `["true", "false"]`
- `date` → `<input type="date">`
- `text` (default) → `<input type="text">`
- Hidden for value-less operators (`set_true`, `set_false`, `toggle`, `clear`)

**Reuse from condition_builder:** Import `group_variables_by_page/1` and `find_variable/3` directly from `StoryarnWeb.Components.ConditionBuilder` — they are public functions. This avoids code duplication.

---

### A4. Panel Component

**New file:** `lib/storyarn_web/live/flow_live/components/panels/instruction_panel.ex`

Mirror `condition_panel.ex`:

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
│ │   assignments={node.data["assignments"]} │ │
│ │   variables={@project_variables}         │ │
│ │   on_change="update_instruction_builder" │ │
│ │   can_edit={@can_edit}                   │ │
│ │ />                                       │ │
│ └──────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

**Key detail:** The description field uses the standard `<.form>` with `phx-change="update_node_data"`. The assignments use their own event `"update_instruction_builder"` (same pattern as condition: builder events are separate from form events).

Actually, simpler approach: put the description field INSIDE the instruction_builder's wrapper, or handle it separately via `update_node_field` with `phx-blur`. Use the same pattern as the exit node's `technical_id` field (plain input with `phx-blur="update_node_field"` + `phx-value-field="description"`).

---

### A5. Event Handlers

**New file:** `lib/storyarn_web/live/flow_live/handlers/instruction_event_handlers.ex`

Mirror `condition_event_handlers.ex`:

```elixir
defmodule StoryarnWeb.FlowLive.Handlers.InstructionEventHandlers do
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias Storyarn.Flows
  alias Storyarn.Flows.Instruction
  alias StoryarnWeb.FlowLive.Helpers.FormHelpers

  import StoryarnWeb.FlowLive.Helpers.SocketHelpers

  @spec handle_update_instruction_builder(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_update_instruction_builder(params, socket)
end
```

**Core dispatch logic** (mirrors `apply_condition_update/2`):

```elixir
defp apply_assignment_update(current_assignments, params) do
  cond do
    params["action"] == "add_assignment" ->
      Instruction.add_assignment(current_assignments)

    params["action"] == "remove_assignment" ->
      Instruction.remove_assignment(current_assignments, params["assignment-id"])

    true ->
      apply_assignment_field_update(current_assignments, params)
  end
end
```

**Field update logic** — same `_target` pattern as condition:

```elixir
defp apply_assignment_field_update(assignments, params) do
  target = List.first(params["_target"] || [])

  {field, assignment_id} =
    cond do
      match?("assign_page_" <> _, target) ->
        {"page", String.replace_prefix(target, "assign_page_", "")}
      match?("assign_variable_" <> _, target) ->
        {"variable", String.replace_prefix(target, "assign_variable_", "")}
      match?("assign_operator_" <> _, target) ->
        {"operator", String.replace_prefix(target, "assign_operator_", "")}
      match?("assign_value_" <> _, target) ->
        {"value", String.replace_prefix(target, "assign_value_", "")}
      true ->
        {nil, nil}
    end

  if field && assignment_id do
    value = params[target]
    Instruction.update_assignment(assignments, assignment_id, field, value)
  else
    assignments
  end
end
```

**Save flow** — same pattern as condition handler:

```elixir
defp handle_instruction_node_update(socket, updated_assignments) do
  node = socket.assigns.selected_node
  updated_data = Map.put(node.data, "assignments", updated_assignments)

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
```

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

**Key:** Instruction panel, like condition panel, renders OUTSIDE the `<.form>` wrapper because the builder uses its own `phx-change` event targeting `"update_instruction_builder"`.

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

Update `getPreviewText`:

```javascript
case "instruction": {
  const assignments = nodeData.assignments || [];
  if (assignments.length === 0) return "";
  return assignments
    .slice(0, 3)  // max 3 lines
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
  const opLabels = {
    set: "=", add: "+=", subtract: "-=",
    set_true: "= true", set_false: "= false",
    toggle: "⟲", clear: "∅"
  };
  const op = opLabels[assignment.operator] || "=";
  if (["set_true", "set_false", "toggle", "clear"].includes(assignment.operator)) {
    return `${ref} ${op}`;
  }
  return `${ref} ${op} ${assignment.value || "?"}`;
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
  test "add_assignment/1 appends with generated id"
  test "remove_assignment/2 removes by id"
  test "update_assignment/4 updates a field"
  test "operators_for_type/1 returns correct operators per type"
  test "operator_requires_value?/1"
  test "format_assignment_short/1 formats correctly"
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
      case resolve_block(node.flow_id, assign["page"], assign["variable"]) do
        nil -> []
        block_id -> [%{block_id: block_id, kind: "write"}]
      end
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
  test "condition node creates read references"
  test "updating node replaces old references"
  test "deleting node cascades reference deletion"
  test "deleting block cascades reference deletion"
  test "unresolvable variable creates no reference"
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
              a["page"] == block_info.page_shortcut and
                a["variable"] == block_info.variable_name
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

### New Files (8)

| File | Phase | Purpose |
|------|-------|---------|
| `lib/storyarn/flows/instruction.ex` | A | Domain logic |
| `lib/storyarn_web/components/instruction_builder.ex` | A | Reusable builder component |
| `lib/storyarn_web/live/flow_live/components/panels/instruction_panel.ex` | A | Panel UI |
| `lib/storyarn_web/live/flow_live/handlers/instruction_event_handlers.ex` | A | Event handlers |
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
| `assets/js/hooks/flow_canvas/components/node_formatters.js` | A | Instruction preview |
| `assets/js/hooks/flow_canvas/components/storyarn_node.js` | A | Instruction rendering (if needed) |
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

### Phase A
- [ ] `mix test` — all tests pass
- [ ] Create instruction node → panel shows assignment builder
- [ ] Add assignment → page dropdown populated with project variables
- [ ] Select page → variable dropdown filters to that page's variables
- [ ] Select variable → operator dropdown shows type-appropriate operators
- [ ] Boolean variable → shows set_true/set_false/toggle (no value input)
- [ ] Number variable → shows set/add/subtract with number input
- [ ] Canvas shows assignment preview: `mc.jaime.health += 10`
- [ ] Description field saves via blur
- [ ] Duplicate instruction node preserves assignments

### Phase B
- [ ] `mix ecto.migrate` — migration runs
- [ ] Save instruction node → variable_references table has write entries
- [ ] Save condition node → variable_references table has read entries
- [ ] Delete node → references cascade deleted
- [ ] Delete block → references cascade deleted
- [ ] Unresolvable variable (bad shortcut) → no reference created, no error

### Phase C
- [ ] Page editor → References tab → variable usage section visible
- [ ] Shows "Modified by" for variables written by instruction nodes
- [ ] Shows "Read by" for variables read by condition nodes
- [ ] Click navigate → opens flow editor zoomed to the node
- [ ] Variables with no usage show "Not used in any flow"

### Phase D
- [ ] Rename page shortcut → variable usage still shows (block_id FK intact)
- [ ] Node JSON is stale → UI shows warning badge
- [ ] Repair action updates node JSON to current values

---

## Future Work (Out of Scope)

These are NOT part of this plan but should be noted:

1. **Dialogue `output_instruction` → structured builder** — Currently plain text. When converted to structured data, reuse `instruction_builder` and add write tracking.
2. **Dialogue `input_condition` → structured builder** — Currently plain text. When converted, reuse `condition_builder` and add read tracking.
3. **Cross-flow variable analysis** — "Show me all flows that touch this variable" as a project-level view.
4. **Variable rename propagation** — When a page shortcut or variable name changes, auto-update all referencing node data (not just the reference table).
5. **Export integration** — Include variable reference graph in export format.
