# Plan 1: Text / Rich Text Config Popover

> **Scope:** Config popover for `text` and `rich_text` block types.
>
> **Depends on:** Plan 0 (Universal Toolbar)

---

## Goal

Clicking the config gear (⚙) in the **toolbar** opens a floating **popover** anchored to the gear button, containing:

1. **Placeholder** — text input
2. **Max Length** — number input (optional, `nil` = no limit)
3. **Advanced section** — `<.block_advanced_config>` (scope, required, variable name)

Auto-saves on change (blur or input event). Popover uses `ToolbarPopover` hook.

---

## Config Fields (from current `config_panel.ex`)

| Field | Control | Config key | Default |
|-------|---------|-----------|---------|
| Placeholder | `<input type="text">` | `config.placeholder` | `""` |
| Max Length | `<input type="number" min="1">` | `config.max_length` | `nil` (no limit) |

Both fields are identical for `text` and `rich_text`.

---

## Files to Create

### 1. `lib/storyarn_web/components/block_components/config_popovers/text_config.ex`

```elixir
defmodule StoryarnWeb.Components.BlockComponents.ConfigPopovers.TextConfig do
  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext
  import StoryarnWeb.Components.BlockComponents.BlockAdvancedConfig

  @doc """
  Popover content for text and rich_text block config.
  Rendered inside a <template> tag, cloned by ToolbarPopover hook.
  """
  attr :block, :map, required: true
  attr :is_inherited, :boolean, default: false
  attr :target, :any, default: nil

  def text_config(assigns) do
    config = assigns.block.config || %{}
    assigns =
      assigns
      |> assign(:placeholder, config["placeholder"] || "")
      |> assign(:max_length, config["max_length"])

    ~H"""
    <div class="p-3 space-y-3 w-64">
      <%!-- Placeholder --%>
      <div>
        <label class="text-xs font-medium text-base-content/70">
          {dgettext("sheets", "Placeholder")}
        </label>
        <input
          type="text"
          class="input input-bordered input-sm w-full mt-1"
          value={@placeholder}
          placeholder={dgettext("sheets", "Enter placeholder...")}
          data-blur-event="save_block_config"
          data-params={Jason.encode!(%{block_id: @block.id, field: "placeholder"})}
        />
      </div>

      <%!-- Max Length --%>
      <div>
        <label class="text-xs font-medium text-base-content/70">
          {dgettext("sheets", "Max Length")}
        </label>
        <input
          type="number"
          class="input input-bordered input-sm w-full mt-1"
          value={@max_length}
          placeholder={dgettext("sheets", "No limit")}
          min="1"
          data-blur-event="save_block_config"
          data-params={Jason.encode!(%{block_id: @block.id, field: "max_length"})}
        />
      </div>

      <%!-- Advanced --%>
      <.block_advanced_config block={@block} is_inherited={@is_inherited} target={@target} />
    </div>
    """
  end
end
```

---

## Files to Modify

### 2. `lib/storyarn_web/components/block_components/block_toolbar.ex`

Update `toolbar_config_gear/1` for text/rich_text blocks:
- Wrap gear button + `<template>` in a `ToolbarPopover`-hooked `<div>`
- The template renders `<.text_config>` when `block.type in ["text", "rich_text"]`

### 3. `lib/storyarn_web/live/sheet_live/components/content_tab.ex`

Add event handler:
```elixir
def handle_event("save_block_config", %{"block_id" => block_id, "field" => field, "value" => value}, socket) do
  with_edit_authorization(socket, fn socket ->
    BlockToolbarHandlers.handle_save_field(block_id, field, value, socket, content_helpers())
  end)
end
```

### 4. `lib/storyarn_web/live/sheet_live/handlers/block_toolbar_handlers.ex`

Add `handle_save_field/5`:
```elixir
def handle_save_field(block_id, field, value, socket, helpers) do
  block = Sheets.get_block_in_project(block_id, socket.assigns.project.id)
  prev_config = block.config
  new_config = Map.put(block.config || %{}, field, normalize_value(field, value))

  case Sheets.update_block_config(block, new_config) do
    {:ok, _updated} ->
      helpers.push_undo.({:update_block_config, block.id, prev_config, new_config})
      helpers.maybe_create_version.(socket)
      helpers.notify_parent.(socket, :saved)
      {:noreply, helpers.reload_blocks.(socket)}

    {:error, _} ->
      {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not save configuration."))}
  end
end
```

---

## Tests

### Unit: Text Config Component

**File:** `test/storyarn_web/components/config_popovers/text_config_test.exs`

```elixir
describe "text_config/1" do
  test "renders placeholder input with current value"
  test "renders max_length input with current value"
  test "renders max_length as empty when nil"
  test "renders advanced section"
  test "data-blur-event attributes are set correctly"
  test "data-params include block_id and field"
end
```

### Integration: Save Config via Popover

**File:** `test/storyarn_web/live/sheet_live/handlers/text_config_integration_test.exs`

```elixir
describe "text block config via toolbar" do
  test "saving placeholder updates block config"
  test "saving max_length updates block config"
  test "saving empty max_length sets nil"
  test "undo reverts config change"
  test "viewer cannot save config"
end

describe "rich_text block config via toolbar" do
  test "saving placeholder updates block config"
  test "saving max_length updates block config"
end
```

---

## Post-Implementation Audit

- [ ] All existing tests pass
- [ ] New tests pass
- [ ] `mix compile --warnings-as-errors`
- [ ] `mix credo --strict`
- [ ] Manual: click gear on text block → popover appears with placeholder + max_length
- [ ] Manual: edit placeholder → blur → value saved
- [ ] Manual: edit max_length → blur → value saved
- [ ] Manual: popover shows advanced section with scope, required, variable name
- [ ] Manual: same behavior for rich_text block
- [ ] Manual: undo reverts config change
- [ ] Manual: popover closes on outside click
- [ ] Manual: popover repositions on scroll
