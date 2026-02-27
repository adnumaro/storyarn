# Plan 3: Boolean Config Popover

> **Scope:** Config popover for `boolean` block type.
>
> **Depends on:** Plan 0 (Universal Toolbar), Plan 1 (save infrastructure)

---

## Goal

Clicking the config gear (⚙) in the **toolbar** opens a floating **popover** with:

1. **Mode** — Radio/select: "Two states (Yes/No)" vs "Three states (Yes/Neutral/No)"
2. **Custom Labels** — True label, False label, Neutral label (only shown when tri-state)
3. **Advanced section** — `<.block_advanced_config>`

---

## Config Fields

| Field | Control | Config key | Default |
|-------|---------|-----------|---------|
| Mode | `<select>` or radio buttons | `config.mode` | `"two_state"` |
| True Label | `<input type="text">` | `config.true_label` | `""` (default: "Yes") |
| False Label | `<input type="text">` | `config.false_label` | `""` (default: "No") |
| Neutral Label | `<input type="text">` (tri-state only) | `config.neutral_label` | `""` (default: "Neutral") |

---

## Files to Create

### 1. `lib/storyarn_web/components/block_components/config_popovers/boolean_config.ex`

```elixir
defmodule StoryarnWeb.Components.BlockComponents.ConfigPopovers.BooleanConfig do
  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext
  import StoryarnWeb.Components.BlockComponents.BlockAdvancedConfig

  attr :block, :map, required: true
  attr :is_inherited, :boolean, default: false
  attr :target, :any, default: nil

  def boolean_config(assigns) do
    config = assigns.block.config || %{}
    assigns =
      assigns
      |> assign(:mode, config["mode"] || "two_state")
      |> assign(:true_label, config["true_label"] || "")
      |> assign(:false_label, config["false_label"] || "")
      |> assign(:neutral_label, config["neutral_label"] || "")

    ~H"""
    <div class="p-3 space-y-3 w-64">
      <%!-- Mode --%>
      <div>
        <label class="text-xs font-medium text-base-content/70">
          {dgettext("sheets", "Mode")}
        </label>
        <div class="flex flex-col gap-1 mt-1">
          <button class={mode_btn_class(@mode == "two_state")}
            data-event="save_block_config"
            data-params={Jason.encode!(%{block_id: @block.id, field: "mode", value: "two_state"})}
            data-close-on-click="false">
            {dgettext("sheets", "Two states (Yes/No)")}
          </button>
          <button class={mode_btn_class(@mode == "tri_state")}
            data-event="save_block_config"
            data-params={Jason.encode!(%{block_id: @block.id, field: "mode", value: "tri_state"})}
            data-close-on-click="false">
            {dgettext("sheets", "Three states (Yes/Neutral/No)")}
          </button>
        </div>
      </div>

      <%!-- Custom Labels --%>
      <div>
        <label class="text-xs font-medium text-base-content/70">
          {dgettext("sheets", "Custom Labels")}
        </label>
        <div class="grid grid-cols-2 gap-2 mt-1">
          <div>
            <input type="text" class="input input-bordered input-sm w-full"
              value={@true_label} placeholder={dgettext("sheets", "Yes")}
              data-blur-event="save_block_config"
              data-params={Jason.encode!(%{block_id: @block.id, field: "true_label"})} />
            <span class="text-xs text-base-content/50">{dgettext("sheets", "True")}</span>
          </div>
          <div>
            <input type="text" class="input input-bordered input-sm w-full"
              value={@false_label} placeholder={dgettext("sheets", "No")}
              data-blur-event="save_block_config"
              data-params={Jason.encode!(%{block_id: @block.id, field: "false_label"})} />
            <span class="text-xs text-base-content/50">{dgettext("sheets", "False")}</span>
          </div>
        </div>
        <%!-- Neutral label (tri-state only) --%>
        <div :if={@mode == "tri_state"} class="mt-2">
          <input type="text" class="input input-bordered input-sm w-full"
            value={@neutral_label} placeholder={dgettext("sheets", "Neutral")}
            data-blur-event="save_block_config"
            data-params={Jason.encode!(%{block_id: @block.id, field: "neutral_label"})} />
          <span class="text-xs text-base-content/50">{dgettext("sheets", "Neutral/Unknown")}</span>
        </div>
      </div>

      <.block_advanced_config block={@block} is_inherited={@is_inherited} target={@target} />
    </div>
    """
  end

  defp mode_btn_class(active) do
    base = "btn btn-sm btn-block justify-start"
    if active, do: "#{base} btn-primary", else: "#{base} btn-ghost"
  end
end
```

---

## Complexity Note

The mode selector uses `data-event` (click) instead of `data-blur-event` because it's a button, not an input. The `ToolbarPopover` hook already handles `data-event` clicks. After clicking a mode button, the popover stays open (`data-close-on-click="false"`) so the user can see the neutral label field appear/disappear.

**Challenge:** The popover content is cloned from a `<template>` at mount time. When the mode changes, the tri-state neutral label field needs to show/hide. Two approaches:

- **Option A (server re-render):** After `save_block_config` for mode, LiveView re-renders the toolbar template. The `ToolbarPopover` hook's `updated()` callback re-clones and re-opens.
- **Option B (JS toggle):** Add a `data-show-if="tri_state"` attribute to the neutral label div. The hook's click handler toggles visibility client-side.

**Recommended:** Option A — simpler, no custom JS logic. The `ToolbarPopover` hook already preserves open state across `updated()`.

---

## Tests

### Unit: Boolean Config Component

**File:** `test/storyarn_web/components/config_popovers/boolean_config_test.exs`

```elixir
describe "boolean_config/1" do
  test "renders mode selector with two_state active by default"
  test "renders mode selector with tri_state active when configured"
  test "renders true/false label inputs"
  test "renders neutral label only when mode is tri_state"
  test "hides neutral label when mode is two_state"
  test "renders advanced section"
end
```

### Integration

**File:** `test/storyarn_web/live/sheet_live/handlers/boolean_config_integration_test.exs`

```elixir
describe "boolean block config via toolbar" do
  test "switching mode to tri_state saves and shows neutral label"
  test "switching mode to two_state saves and hides neutral label"
  test "saving true_label updates config"
  test "saving false_label updates config"
  test "saving neutral_label updates config (tri_state mode)"
  test "undo reverts mode change"
end
```

---

## Post-Implementation Audit

- [ ] All tests pass
- [ ] Manual: click gear on boolean block → popover with mode + labels
- [ ] Manual: switch mode → popover re-renders with/without neutral label
- [ ] Manual: edit labels → blur → saved
- [ ] Manual: advanced section works
- [ ] Manual: undo/redo for mode and label changes
