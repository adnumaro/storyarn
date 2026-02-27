# Plan 6: Reference Config Popover

> **Scope:** Config popover for `reference` block type.
>
> **Depends on:** Plan 0 (Universal Toolbar), Plan 1 (save infrastructure)

---

## Goal

Clicking the config gear (⚙) in the **toolbar** opens a floating **popover** with:

1. **Allowed Types** — Checkboxes: Sheets, Flows
2. **Advanced section** — `<.block_advanced_config>`

---

## Config Fields

| Field | Control | Config key | Default |
|-------|---------|-----------|---------|
| Allowed Types | Checkboxes | `config.allowed_types` | `["sheet", "flow"]` |

---

## Files to Create

### 1. `lib/storyarn_web/components/block_components/config_popovers/reference_config.ex`

```elixir
defmodule StoryarnWeb.Components.BlockComponents.ConfigPopovers.ReferenceConfig do
  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext
  import StoryarnWeb.Components.BlockComponents.BlockAdvancedConfig

  attr :block, :map, required: true
  attr :is_inherited, :boolean, default: false
  attr :target, :any, default: nil

  def reference_config(assigns) do
    config = assigns.block.config || %{}
    assigns = assign(assigns, :allowed_types, config["allowed_types"] || ["sheet", "flow"])

    ~H"""
    <div class="p-3 space-y-3 w-56">
      <div>
        <label class="text-xs font-medium text-base-content/70">
          {dgettext("sheets", "Allowed Types")}
        </label>
        <div class="flex flex-col gap-2 mt-1">
          <label class="flex items-center gap-2 cursor-pointer text-sm">
            <input type="checkbox"
              class="checkbox checkbox-sm"
              checked={"sheet" in @allowed_types}
              data-event="toggle_allowed_type"
              data-params={Jason.encode!(%{block_id: @block.id, type: "sheet"})}
              data-close-on-click="false" />
            <span>{dgettext("sheets", "Sheets")}</span>
          </label>
          <label class="flex items-center gap-2 cursor-pointer text-sm">
            <input type="checkbox"
              class="checkbox checkbox-sm"
              checked={"flow" in @allowed_types}
              data-event="toggle_allowed_type"
              data-params={Jason.encode!(%{block_id: @block.id, type: "flow"})}
              data-close-on-click="false" />
            <span>{dgettext("sheets", "Flows")}</span>
          </label>
        </div>
      </div>

      <.block_advanced_config block={@block} is_inherited={@is_inherited} target={@target} />
    </div>
    """
  end
end
```

---

## Event Handler

### New event in `content_tab.ex`:

```elixir
def handle_event("toggle_allowed_type", %{"block_id" => block_id, "type" => type}, socket) do
  with_edit_authorization(socket, fn socket ->
    BlockToolbarHandlers.handle_toggle_allowed_type(block_id, type, socket, content_helpers())
  end)
end
```

### In `block_toolbar_handlers.ex`:

```elixir
def handle_toggle_allowed_type(block_id, type, socket, helpers) do
  block = Sheets.get_block_in_project(block_id, socket.assigns.project.id)
  current = get_in(block.config, ["allowed_types"]) || ["sheet", "flow"]

  new_types =
    if type in current,
      do: List.delete(current, type),
      else: current ++ [type]

  # Ensure at least one type remains
  new_types = if new_types == [], do: current, else: new_types

  new_config = Map.put(block.config || %{}, "allowed_types", new_types)
  # ... save with undo
end
```

**Note:** The checkbox uses `data-event` (click) not `data-blur-event` because checkboxes toggle on click. The `ToolbarPopover` hook handles this via its click delegation.

---

## Tests

### Unit

**File:** `test/storyarn_web/components/config_popovers/reference_config_test.exs`

```elixir
describe "reference_config/1" do
  test "renders sheets and flows checkboxes"
  test "both checked by default"
  test "shows unchecked when type not in allowed_types"
  test "renders advanced section"
end
```

### Integration

**File:** `test/storyarn_web/live/sheet_live/handlers/reference_config_integration_test.exs`

```elixir
describe "reference block config via toolbar" do
  test "toggling sheet off removes from allowed_types"
  test "toggling sheet back on adds to allowed_types"
  test "cannot remove all types (at least one must remain)"
  test "undo reverts allowed_types change"
end
```

---

## Post-Implementation Audit

- [ ] All tests pass
- [ ] Manual: click gear on reference block → popover with checkboxes
- [ ] Manual: toggle types → saved
- [ ] Manual: cannot uncheck both (last one stays checked)
- [ ] Manual: advanced section works
