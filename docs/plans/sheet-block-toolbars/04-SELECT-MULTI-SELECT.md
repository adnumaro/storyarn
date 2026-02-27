# Plan 4: Select / Multi-Select Config Popover

> **Scope:** Config popover for `select` and `multi_select` block types.
>
> **Depends on:** Plan 0 (Universal Toolbar), Plan 1 (save infrastructure)
>
> **Complexity:** Medium-High (most complex popover due to dynamic options list)

---

## Goal

Clicking the config gear (⚙) in the **toolbar** opens a floating **popover** with:

1. **Options list** — Each option has key (slug) + label, with remove button. Add button at bottom.
2. **Placeholder** — text input
3. **Max Selections** — number input (multi_select only)
4. **Advanced section** — `<.block_advanced_config>`

---

## Config Fields

| Field | Control | Config key | Default | Types |
|-------|---------|-----------|---------|-------|
| Options | List of `{key, value}` | `config.options` | `[]` | both |
| Placeholder | `<input type="text">` | `config.placeholder` | `""` | both |
| Max Selections | `<input type="number">` | `config.max_options` | `nil` | multi_select only |

---

## Files to Create

### 1. `lib/storyarn_web/components/block_components/config_popovers/select_config.ex`

```elixir
defmodule StoryarnWeb.Components.BlockComponents.ConfigPopovers.SelectConfig do
  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext
  import StoryarnWeb.Components.CoreComponents, only: [icon: 1]
  import StoryarnWeb.Components.BlockComponents.BlockAdvancedConfig

  attr :block, :map, required: true
  attr :is_inherited, :boolean, default: false
  attr :target, :any, default: nil

  def select_config(assigns) do
    config = assigns.block.config || %{}
    assigns =
      assigns
      |> assign(:options, config["options"] || [])
      |> assign(:placeholder, config["placeholder"] || "")
      |> assign(:max_options, config["max_options"])
      |> assign(:is_multi, assigns.block.type == "multi_select")

    ~H"""
    <div class="p-3 space-y-3 w-72">
      <%!-- Options list --%>
      <div>
        <label class="text-xs font-medium text-base-content/70">
          {dgettext("sheets", "Options")}
        </label>
        <div class="space-y-1 mt-1 max-h-48 overflow-y-auto">
          <div :for={{opt, idx} <- Enum.with_index(@options)} class="flex items-center gap-1">
            <input type="text" class="input input-bordered input-xs w-16 font-mono"
              value={opt["key"]} placeholder={dgettext("sheets", "key")}
              data-blur-event="update_select_option"
              data-params={Jason.encode!(%{block_id: @block.id, index: idx, key_field: "key"})} />
            <input type="text" class="input input-bordered input-xs flex-1"
              value={opt["value"]} placeholder={dgettext("sheets", "Label")}
              data-blur-event="update_select_option"
              data-params={Jason.encode!(%{block_id: @block.id, index: idx, key_field: "value"})} />
            <button class="btn btn-ghost btn-xs btn-square text-error"
              data-event="remove_select_option"
              data-params={Jason.encode!(%{block_id: @block.id, index: idx})}
              data-close-on-click="false">
              <.icon name="x" class="size-3" />
            </button>
          </div>
        </div>
        <button class="btn btn-ghost btn-xs mt-1"
          data-event="add_select_option"
          data-params={Jason.encode!(%{block_id: @block.id})}
          data-close-on-click="false">
          <.icon name="plus" class="size-3" />
          {dgettext("sheets", "Add option")}
        </button>
      </div>

      <%!-- Placeholder --%>
      <div>
        <label class="text-xs font-medium text-base-content/70">
          {dgettext("sheets", "Placeholder")}
        </label>
        <input type="text" class="input input-bordered input-sm w-full mt-1"
          value={@placeholder} placeholder={dgettext("sheets", "Select...")}
          data-blur-event="save_block_config"
          data-params={Jason.encode!(%{block_id: @block.id, field: "placeholder"})} />
      </div>

      <%!-- Max Selections (multi_select only) --%>
      <div :if={@is_multi}>
        <label class="text-xs font-medium text-base-content/70">
          {dgettext("sheets", "Max Selections")}
        </label>
        <input type="number" class="input input-bordered input-sm w-full mt-1"
          value={@max_options} placeholder={dgettext("sheets", "No limit")} min="1"
          data-blur-event="save_block_config"
          data-params={Jason.encode!(%{block_id: @block.id, field: "max_options"})} />
      </div>

      <.block_advanced_config block={@block} is_inherited={@is_inherited} target={@target} />
    </div>
    """
  end
end
```

---

## Event Refactoring

The current `add_select_option`, `remove_select_option`, `update_select_option` events in `content_tab.ex` use `socket.assigns.configuring_block`. These need to be refactored to accept `block_id` as a parameter:

### Modify: `lib/storyarn_web/live/sheet_live/handlers/block_toolbar_handlers.ex`

Add:
```elixir
def handle_add_option(block_id, socket, helpers) do
  block = Sheets.get_block_in_project(block_id, socket.assigns.project.id)
  options = get_in(block.config, ["options"]) || []
  new_option = %{"key" => "option-#{length(options) + 1}", "value" => ""}
  new_config = Map.put(block.config || %{}, "options", options ++ [new_option])
  # ... save with undo
end

def handle_remove_option(block_id, index, socket, helpers)
def handle_update_option(block_id, index, key_field, value, socket, helpers)
```

### Modify: `content_tab.ex`

Update event routing:
```elixir
# Old (references configuring_block):
def handle_event("add_select_option", _params, socket) do
  ConfigHelpers.add_select_option(socket)
end

# New (references block_id from params):
def handle_event("add_select_option", %{"block_id" => block_id}, socket) do
  with_edit_authorization(socket, fn socket ->
    BlockToolbarHandlers.handle_add_option(block_id, socket, content_helpers())
  end)
end
```

---

## Complexity: Popover re-render on option add/remove

When options are added/removed, the server re-renders the block toolbar template. The `ToolbarPopover` hook's `updated()` callback detects this, destroys the old popover, re-clones the updated template, and re-opens if it was open. This means:

1. Add option → server adds to config → block toolbar re-renders → popover re-opens with new option row
2. Remove option → same flow

This works because `ToolbarPopover.updated()` preserves `wasOpen` state.

---

## Tests

### Unit: Select Config Component

**File:** `test/storyarn_web/components/config_popovers/select_config_test.exs`

```elixir
describe "select_config/1" do
  test "renders empty options list"
  test "renders existing options with key and label inputs"
  test "renders add option button"
  test "renders remove button for each option"
  test "renders placeholder input"
  test "hides max_selections for select type"
  test "shows max_selections for multi_select type"
  test "renders advanced section"
  test "scrollable when many options"
end
```

### Integration

**File:** `test/storyarn_web/live/sheet_live/handlers/select_config_integration_test.exs`

```elixir
describe "select block config via toolbar" do
  test "add_select_option adds new option with default key"
  test "remove_select_option removes option at index"
  test "update_select_option updates key field"
  test "update_select_option updates value field"
  test "saving placeholder updates config"
  test "undo reverts option add"
  test "undo reverts option remove"
end

describe "multi_select block config via toolbar" do
  test "max_selections field is present"
  test "saving max_selections updates config"
  test "add/remove options work same as select"
end
```

---

## Post-Implementation Audit

- [ ] All tests pass
- [ ] Manual: click gear on select → popover with options list
- [ ] Manual: add option → new row appears in popover
- [ ] Manual: edit option key/label → blur → saved
- [ ] Manual: remove option → row disappears
- [ ] Manual: multi_select shows max selections field
- [ ] Manual: popover stays open after add/remove (data-close-on-click="false")
- [ ] Manual: undo/redo for all option operations
- [ ] Manual: options list scrollable when > 6 options
