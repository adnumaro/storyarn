# Plan 5: Date Config Popover

> **Scope:** Config popover for `date` block type.
>
> **Depends on:** Plan 0 (Universal Toolbar), Plan 1 (save infrastructure)

---

## Goal

Clicking the config gear (⚙) in the **toolbar** opens a floating **popover** with:

1. **Date Range** — Min date, Max date (side by side)
2. **Advanced section** — `<.block_advanced_config>`

---

## Config Fields

| Field | Control | Config key | Default |
|-------|---------|-----------|---------|
| Min Date | `<input type="date">` | `config.min_date` | `nil` |
| Max Date | `<input type="date">` | `config.max_date` | `nil` |

---

## Files to Create

### 1. `lib/storyarn_web/components/block_components/config_popovers/date_config.ex`

```elixir
defmodule StoryarnWeb.Components.BlockComponents.ConfigPopovers.DateConfig do
  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext
  import StoryarnWeb.Components.BlockComponents.BlockAdvancedConfig

  attr :block, :map, required: true
  attr :is_inherited, :boolean, default: false
  attr :target, :any, default: nil

  def date_config(assigns) do
    config = assigns.block.config || %{}
    assigns =
      assigns
      |> assign(:min_date, config["min_date"])
      |> assign(:max_date, config["max_date"])

    ~H"""
    <div class="p-3 space-y-3 w-64">
      <div>
        <label class="text-xs font-medium text-base-content/70">
          {dgettext("sheets", "Date Range")}
        </label>
        <div class="grid grid-cols-2 gap-2 mt-1">
          <div>
            <span class="text-xs text-base-content/50">{dgettext("sheets", "Min")}</span>
            <input type="date" class="input input-bordered input-sm w-full"
              value={@min_date}
              data-blur-event="save_block_config"
              data-params={Jason.encode!(%{block_id: @block.id, field: "min_date"})} />
          </div>
          <div>
            <span class="text-xs text-base-content/50">{dgettext("sheets", "Max")}</span>
            <input type="date" class="input input-bordered input-sm w-full"
              value={@max_date}
              data-blur-event="save_block_config"
              data-params={Jason.encode!(%{block_id: @block.id, field: "max_date"})} />
          </div>
        </div>
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

Add date type routing in `toolbar_config_gear/1`.

---

## Tests

### Unit

**File:** `test/storyarn_web/components/config_popovers/date_config_test.exs`

```elixir
describe "date_config/1" do
  test "renders min_date and max_date inputs"
  test "renders empty when dates are nil"
  test "renders with existing date values"
  test "renders advanced section"
end
```

### Integration

**File:** `test/storyarn_web/live/sheet_live/handlers/date_config_integration_test.exs`

```elixir
describe "date block config via toolbar" do
  test "saving min_date updates config"
  test "saving max_date updates config"
  test "clearing min_date sets nil"
  test "undo reverts date change"
end
```

---

## Post-Implementation Audit

- [ ] All tests pass
- [ ] Manual: click gear on date block → popover with min/max date
- [ ] Manual: edit dates → blur → saved
- [ ] Manual: clear dates → saved as nil
- [ ] Manual: advanced section works
