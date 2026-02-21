# Phase 1: Number Constraints (min/max/step)

> **Goal:** Add min, max, and step constraints to number blocks (both standalone and table columns). These constraints are enforced at edit time, in cell validation, and during instruction execution in the Story Player.
>
> **Prerequisite for:** Interaction zones (Phase 2+). Without constraints, actionable zones that increment/decrement variables can't enforce bounds (e.g., character points 0-30).
>
> **Estimated scope:** ~12 files, self-contained feature

---

## Data Model

### Standalone number blocks

**Current config** (`block.ex:@default_configs`):
```elixir
"number" => %{"label" => "Label", "placeholder" => "0"}
```

**New config:**
```elixir
"number" => %{"label" => "Label", "placeholder" => "0", "min" => nil, "max" => nil, "step" => nil}
```

- `min` — minimum allowed value (number or nil = unbounded)
- `max` — maximum allowed value (number or nil = unbounded)
- `step` — increment/decrement step size (number or nil = 1)
- All three are optional (nil = no constraint)

### Table number columns

**Current config:** `%{"width" => 150}` (or empty)

**New config:**
```elixir
%{"width" => 150, "min" => nil, "max" => nil, "step" => nil}
```

Same semantics as standalone blocks.

### Variable metadata

**Current variable structure** (from `list_project_variables/1`):
```elixir
%{
  sheet_id: 1, sheet_name: "Jaime", sheet_shortcut: "mc.jaime",
  block_id: 10, variable_name: "health", block_type: "number",
  options: nil, table_name: nil, row_name: nil, column_name: nil
}
```

**New:** Add `constraints` field:
```elixir
%{
  ...,
  constraints: %{"min" => 0, "max" => 100, "step" => 1}  # or nil for non-number types
}
```

This propagates to the evaluator's variable state so instructions can enforce constraints during Story Player execution.

---

## Files to Modify

| File                                                           | Change                                                    |
|----------------------------------------------------------------|-----------------------------------------------------------|
| `lib/storyarn/sheets/block.ex`                                 | Add min/max/step to default number config                 |
| `lib/storyarn/sheets/sheet_queries.ex`                         | Extract constraints from config, add to variable metadata |
| `lib/storyarn_web/components/block_components/text_blocks.ex`  | Add min/max/step HTML attrs to number input               |
| `lib/storyarn_web/components/block_components/table_blocks.ex` | Number settings panel + cell input attrs                  |
| `lib/storyarn_web/live/sheet_live/handlers/table_handlers.ex`  | Handle config update events + cell clamping               |
| `lib/storyarn_web/live/sheet_live/handlers/block_handlers.ex`  | Handle standalone block config update                     |
| `lib/storyarn/flows/evaluator/instruction_exec.ex`             | Clamp values after instruction execution                  |
| `lib/storyarn/flows/evaluator/engine.ex`                       | Pass constraints when setting variables                   |
| `lib/storyarn_web/components/block_components/config_panel.ex` | Number settings in block config panel                     |
| `test/storyarn/sheets/table_crud_test.exs`                     | Constraint tests                                          |
| `test/storyarn/flows/evaluator/instruction_exec_test.exs`      | Clamping tests                                            |

---

## Task 1 — Backend: Config Defaults + Variable Metadata

### 1a — Block default config

**`lib/storyarn/sheets/block.ex`** — Update `@default_configs`:

```elixir
"number" => %{"label" => "Label", "placeholder" => "0", "min" => nil, "max" => nil, "step" => nil}
```

No migration needed — config is JSONB. Existing blocks without these keys simply have no constraints (nil = unbounded).

### 1b — Variable metadata: extract constraints

**`lib/storyarn/sheets/sheet_queries.ex`** — Modify both `list_block_variables` and `list_table_variables` to include constraints.

**For block variables** — after `extract_variable_options/1`, add constraints extraction:

```elixir
defp extract_variable_constraints(%{block_type: "number", config: config} = var) when is_map(config) do
  constraints = %{
    "min" => config["min"],
    "max" => config["max"],
    "step" => config["step"]
  }
  # Only include if at least one constraint is set
  if Enum.all?(Map.values(constraints), &is_nil/1) do
    Map.put(var, :constraints, nil)
  else
    Map.put(var, :constraints, constraints)
  end
end

defp extract_variable_constraints(var), do: Map.put(var, :constraints, nil)
```

Add this step in the pipeline for both `list_block_variables/1` and `list_table_variables/1`:

```elixir
# In list_block_variables:
|> Enum.map(&extract_variable_options/1)
|> Enum.map(&extract_variable_constraints/1)  # NEW
|> Enum.map(&Map.merge(&1, %{table_name: nil, row_name: nil, column_name: nil}))

# In list_table_variables:
raw_vars
|> Enum.map(&remap_reference_type(&1, sheet_options))
|> Enum.map(&extract_variable_options/1)
|> Enum.map(&extract_variable_constraints/1)  # NEW
```

**Important:** For table columns, the config with min/max/step lives in `tc.config`. The query already selects `config: tc.config`, so constraints extraction works identically.

### 1c — Evaluator: include constraints in variable state

**`lib/storyarn_web/live/flow_live/handlers/debug_session_handlers.ex`** (or wherever variables are loaded into the evaluator state) — When building the variable map for `Engine.init/2`, include constraints:

```elixir
# Current pattern:
%{
  value: initial_value,
  initial_value: initial_value,
  block_type: var.block_type,
  ...
}

# Add:
constraints: var[:constraints]  # nil for non-number, %{"min" => ..., "max" => ..., "step" => ...} for number
```

### 1d — Evaluator: clamp values during instruction execution

**`lib/storyarn/flows/evaluator/instruction_exec.ex`** — After applying an operator to a number variable, clamp the result.

Find where the new value is computed (after `apply_operator/4` or equivalent). Add clamping:

```elixir
defp clamp_to_constraints(value, %{constraints: constraints}) when is_map(constraints) do
  value
  |> clamp_min(constraints["min"])
  |> clamp_max(constraints["max"])
end

defp clamp_to_constraints(value, _variable_meta), do: value

defp clamp_min(value, nil), do: value
defp clamp_min(value, min) when is_number(value) and is_number(min), do: max(value, min)
defp clamp_min(value, _), do: value

defp clamp_max(value, nil), do: value
defp clamp_max(value, max) when is_number(value) and is_number(max), do: min(value, max)
defp clamp_max(value, _), do: value
```

Apply this after computing the new value in `execute_assignment/2`:

```elixir
new_value = apply_operator(operator, current_value, resolved_value, block_type)
new_value = clamp_to_constraints(new_value, variable_meta)
```

When clamped, log to console: `"mc.jaime.str: 18 → 18 (clamped at max 18)"`.

---

## Task 2 — UI: Table Column Number Settings

### 2a — Settings panel

**`lib/storyarn_web/components/block_components/table_blocks.ex`** — Add a "Number Settings" panel in the column dropdown, visible only for number columns.

Add navigation button in the main panel (alongside existing "Options" for select and "Settings" for reference):

```heex
<li :if={@column.type == "number"}>
  <button type="button" data-navigate="number-settings">
    <.icon name="sliders-horizontal" class="size-3.5 opacity-60" />
    <span class="flex-1 text-sm">{dgettext("sheets", "Constraints")}</span>
    <.icon name="chevron-right" class="size-3.5 opacity-40" />
  </button>
</li>
```

Add the settings panel:

```
┌─────────────────────────────────┐
│ ← Constraints                   │
│─────────────────────────────────│
│                                 │
│  Min value                      │
│  ┌─────────────────────────┐    │
│  │ (empty = no limit)      │    │
│  └─────────────────────────┘    │
│                                 │
│  Max value                      │
│  ┌─────────────────────────┐    │
│  │ (empty = no limit)      │    │
│  └─────────────────────────┘    │
│                                 │
│  Step                           │
│  ┌─────────────────────────┐    │
│  │ (empty = 1)             │    │
│  └─────────────────────────┘    │
│                                 │
└─────────────────────────────────┘
```

HEEx template:

```heex
<%!-- ========== Number Settings Panel ========== --%>
<div class="col-dropdown-panel" data-panel="number-settings">
  <ul class="menu p-0">
    <li class="mb-1">
      <button type="button" data-back class="text-xs font-medium opacity-70">
        <.icon name="arrow-left" class="size-3.5" />
        <span>{dgettext("sheets", "Constraints")}</span>
      </button>
    </li>
  </ul>
  <div class="border-t border-base-300 mb-2"></div>
  <div class="space-y-2 px-2 pb-2">
    <div>
      <label class="text-xs font-medium opacity-70">{dgettext("sheets", "Min value")}</label>
      <input
        type="number"
        value={@column.config["min"]}
        placeholder={dgettext("sheets", "No limit")}
        class="input input-xs input-bordered w-full mt-0.5"
        phx-blur="update_number_constraint"
        phx-value-column-id={@column.id}
        phx-value-field="min"
        phx-target={@target}
      />
    </div>
    <div>
      <label class="text-xs font-medium opacity-70">{dgettext("sheets", "Max value")}</label>
      <input
        type="number"
        value={@column.config["max"]}
        placeholder={dgettext("sheets", "No limit")}
        class="input input-xs input-bordered w-full mt-0.5"
        phx-blur="update_number_constraint"
        phx-value-column-id={@column.id}
        phx-value-field="max"
        phx-target={@target}
      />
    </div>
    <div>
      <label class="text-xs font-medium opacity-70">{dgettext("sheets", "Step")}</label>
      <input
        type="number"
        value={@column.config["step"]}
        placeholder="1"
        min="0.001"
        class="input input-xs input-bordered w-full mt-0.5"
        phx-blur="update_number_constraint"
        phx-value-column-id={@column.id}
        phx-value-field="step"
        phx-target={@target}
      />
    </div>
  </div>
</div>
```

### 2b — Cell input attributes

In the editable `table_cell` for number type, add HTML5 constraints:

```heex
<% "number" -> %>
  <input
    type="number"
    value={@value}
    min={@column.config["min"]}
    max={@column.config["max"]}
    step={@column.config["step"] || "any"}
    class="absolute inset-0 px-2 text-sm bg-transparent border-0 rounded-none outline-none focus:outline-none"
    phx-blur="update_table_cell"
    phx-value-row-id={@row.id}
    phx-value-column-slug={@column.slug}
    phx-target={@target}
  />
```

### 2c — Server-side cell validation

**`lib/storyarn_web/live/sheet_live/handlers/table_handlers.ex`** — In the cell update handler, clamp values when constraints exist:

```elixir
defp validate_cell_value("number", value, column) do
  case parse_number(value) do
    nil -> nil
    num ->
      num
      |> clamp_min(column.config["min"])
      |> clamp_max(column.config["max"])
  end
end
```

### 2d — Handler for constraint config updates

**`table_handlers.ex`** — Add handler:

```elixir
def handle_update_number_constraint(params, socket, helpers) do
  column_id = ContentTabHelpers.to_integer(params["column-id"])
  field = params["field"]  # "min", "max", or "step"
  value = params["value"]
  column = Sheets.get_table_column!(column_id)

  with :ok <- verify_column_ownership(socket, column),
       true <- field in ~w(min max step) do
    parsed = parse_constraint_value(value)
    new_config = Map.put(column.config || %{}, field, parsed)

    case Sheets.update_table_column(column, %{config: new_config}) do
      {:ok, _} -> save_and_reload(socket, helpers)
      {:error, _} -> {:noreply, err(socket, :column_update)}
    end
  end
end

defp parse_constraint_value(nil), do: nil
defp parse_constraint_value(""), do: nil
defp parse_constraint_value(val) when is_binary(val) do
  case Float.parse(val) do
    {num, ""} -> num
    _ -> nil
  end
end
defp parse_constraint_value(val) when is_number(val), do: val
```

Wire in `content_tab.ex`:
```elixir
def handle_event("update_number_constraint", params, socket) do
  TableHandlers.handle_update_number_constraint(params, socket, helpers(socket))
end
```

---

## Task 3 — UI: Standalone Block Number Constraints

### 3a — Config panel

**`lib/storyarn_web/components/block_components/config_panel.ex`** — In the number block config section, add min/max/step inputs (same pattern as table column, but for standalone blocks):

```
┌─────────────────────────────────┐
│  Label: [Health        ]        │
│  Placeholder: [0       ]        │
│  ☐ Constant                     │
│                                 │
│  ─── Constraints ───            │
│  Min: [0       ] Max: [100    ] │
│  Step: [1      ]                │
└─────────────────────────────────┘
```

### 3b — Block input attributes

**`lib/storyarn_web/components/block_components/text_blocks.ex`** — In `number_block/1`, add HTML5 attrs:

```heex
<input
  type="number"
  ...existing attrs...
  min={@block.config["min"]}
  max={@block.config["max"]}
  step={@block.config["step"] || "any"}
/>
```

### 3c — Block value validation

**`lib/storyarn_web/live/sheet_live/handlers/block_handlers.ex`** — In the block value update handler, apply clamping for number blocks:

```elixir
defp validate_block_value(%{type: "number", config: config}, value) do
  case parse_number(value) do
    nil -> nil
    num ->
      num
      |> clamp_min(config["min"])
      |> clamp_max(config["max"])
  end
end
```

---

## Task 4 — Inheritance Sync

No additional work needed. The existing `sync_column_to_children` in `table_crud.ex` already syncs the full `config` map. When a parent column's constraints are updated, child columns inherit them automatically.

---

## Task 5 — Tests

### Table column constraints

```elixir
describe "number column constraints" do
  test "cell value clamped to min/max" do
    # Create table with number column, config: %{"min" => 0, "max" => 10}
    # Set cell value to 15 → stored as 10
    # Set cell value to -5 → stored as 0
  end

  test "constraint config persists" do
    # Create number column
    # Update config with min: 0, max: 100, step: 5
    # Reload column, verify config
  end

  test "nil constraints allow any value" do
    # Create number column with no constraints
    # Set cell to 999999 → stored as-is
  end
end
```

### Evaluator constraint enforcement

```elixir
describe "instruction execution with constraints" do
  test "add instruction clamped at max" do
    # Variable: health=95, constraints: {min: 0, max: 100}
    # Instruction: health += 10
    # Result: health = 100 (not 105)
  end

  test "subtract instruction clamped at min" do
    # Variable: health=5, constraints: {min: 0, max: 100}
    # Instruction: health -= 10
    # Result: health = 0 (not -5)
  end

  test "no constraints allows any value" do
    # Variable: health=100, constraints: nil
    # Instruction: health += 999
    # Result: health = 1099
  end
end
```

---

## Verification

```bash
mix test test/storyarn/sheets/table_crud_test.exs
mix test test/storyarn/flows/evaluator/
just quality
```

Manual:
1. Create a table block → add number column → open "Constraints" panel
2. Set min=0, max=100, step=5
3. Edit a cell → try typing 150 → should save as 100
4. In flow editor → create instruction: `sheet.table.row.col += 200`
5. Run Story Player → verify value clamped at 100
