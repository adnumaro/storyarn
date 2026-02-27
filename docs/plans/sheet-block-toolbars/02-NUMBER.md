# Plan 2: Number Config Popover

> **Scope:** Config popover for `number` block type.
>
> **Depends on:** Plan 0 (Universal Toolbar), Plan 1 (save_block_config event + handle_save_field handler)

---

## Goal

Clicking the config gear (⚙) in the **toolbar** opens a floating **popover** with:

1. **Constraints** — Min, Max (side by side), Step
2. **Placeholder** — text input
3. **Advanced section** — `<.block_advanced_config>`

---

## Config Fields

| Field | Control | Config key | Default |
|-------|---------|-----------|---------|
| Min | `<input type="number">` | `config.min` | `nil` |
| Max | `<input type="number">` | `config.max` | `nil` |
| Step | `<input type="number" min="0.001">` | `config.step` | `nil` (default 1) |
| Placeholder | `<input type="text">` | `config.placeholder` | `""` |

---

## Files to Create

### 1. `lib/storyarn_web/components/block_components/config_popovers/number_config.ex`

```elixir
defmodule StoryarnWeb.Components.BlockComponents.ConfigPopovers.NumberConfig do
  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext
  import StoryarnWeb.Components.BlockComponents.BlockAdvancedConfig

  attr :block, :map, required: true
  attr :is_inherited, :boolean, default: false
  attr :target, :any, default: nil

  def number_config(assigns) do
    config = assigns.block.config || %{}
    assigns =
      assigns
      |> assign(:min, config["min"])
      |> assign(:max, config["max"])
      |> assign(:step, config["step"])
      |> assign(:placeholder, config["placeholder"] || "")

    ~H"""
    <div class="p-3 space-y-3 w-64">
      <%!-- Constraints --%>
      <div>
        <label class="text-xs font-medium text-base-content/70">
          {dgettext("sheets", "Constraints")}
        </label>
        <div class="grid grid-cols-2 gap-2 mt-1">
          <input type="number" class="input input-bordered input-sm w-full"
            value={@min} placeholder={dgettext("sheets", "Min")}
            data-blur-event="save_block_config"
            data-params={Jason.encode!(%{block_id: @block.id, field: "min"})} />
          <input type="number" class="input input-bordered input-sm w-full"
            value={@max} placeholder={dgettext("sheets", "Max")}
            data-blur-event="save_block_config"
            data-params={Jason.encode!(%{block_id: @block.id, field: "max"})} />
        </div>
        <input type="number" class="input input-bordered input-sm w-full mt-2"
          value={@step} placeholder={dgettext("sheets", "Step (default: 1)")} min="0.001"
          data-blur-event="save_block_config"
          data-params={Jason.encode!(%{block_id: @block.id, field: "step"})} />
      </div>

      <%!-- Placeholder --%>
      <div>
        <label class="text-xs font-medium text-base-content/70">
          {dgettext("sheets", "Placeholder")}
        </label>
        <input type="text" class="input input-bordered input-sm w-full mt-1"
          value={@placeholder} placeholder={dgettext("sheets", "Enter value...")}
          data-blur-event="save_block_config"
          data-params={Jason.encode!(%{block_id: @block.id, field: "placeholder"})} />
      </div>

      <.block_advanced_config block={@block} is_inherited={@is_inherited} target={@target} />
    </div>
    """
  end
end
```

---

## Files to Modify

### 2. `block_toolbar.ex`

Add number type routing in `toolbar_config_gear/1`.

---

## Tests

### Unit: Number Config Component

**File:** `test/storyarn_web/components/config_popovers/number_config_test.exs`

```elixir
describe "number_config/1" do
  test "renders min/max/step inputs with current values"
  test "renders min/max/step as empty when nil"
  test "renders placeholder input"
  test "renders advanced section"
  test "data-blur-event attributes set correctly"
end
```

### Integration

**File:** `test/storyarn_web/live/sheet_live/handlers/number_config_integration_test.exs`

```elixir
describe "number block config via toolbar" do
  test "saving min updates config"
  test "saving max updates config"
  test "saving step updates config"
  test "saving placeholder updates config"
  test "saving empty min sets nil"
  test "undo reverts config change"
end
```

---

## Post-Implementation Audit

- [ ] All existing + new tests pass
- [ ] Manual: click gear on number block → popover with min/max/step/placeholder
- [ ] Manual: edit min → blur → saved
- [ ] Manual: clear max → blur → sets nil
- [ ] Manual: advanced section works (scope, required, variable)
- [ ] Manual: popover closes on outside click
