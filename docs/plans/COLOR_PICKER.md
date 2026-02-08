# Plan: vanilla-colorful Color Picker — Universal Color Selection

## Context

All color selection in Storyarn uses preset swatches (8-10 colors). This limits creative expression. The goal is to replace all color pickers with a Figma-like full-spectrum picker using **vanilla-colorful** (2.7 KB gzip, Web Components).

**Three areas use color:**
1. **Hub nodes** — `data["color"]` stores preset name (`"purple"`), resolved to hex via `HubColors.to_hex/2`
2. **Exit nodes** — `data["outcome_color"]` stores preset name (`"green"`), JS resolves to hex locally
3. **Sheets** — `sheets.color` stores hex string (`"#3b82f6"`), already supports custom hex

---

## Current State

| Feature | DB Field | Format | UI | Hex Resolution |
|---------|----------|--------|----|----------------|
| Hub node | `data["color"]` | Preset name | Select dropdown | Backend (`resolve_node_colors`) |
| Exit node | `data["outcome_color"]` | Preset name | Circular swatches | JS (`colorMap`) |
| Sheet | `sheets.color` | Hex string | Circular swatches (LiveComponent) | None needed |

### Key Files

| File | Purpose |
|------|---------|
| `assets/js/app.js` | Hook registration |
| `assets/js/hooks/*.js` | All hooks (flat, no subdirs) |
| `lib/storyarn/flows/hub_colors.ex` | Hub color name → hex mapping |
| `lib/storyarn/flows.ex` | `resolve_node_colors/3` — serialization |
| `lib/storyarn_web/live/flow_live/nodes/hub/config_sidebar.ex` | Hub sidebar — select dropdown |
| `lib/storyarn_web/live/flow_live/nodes/exit/config_sidebar.ex` | Exit sidebar — swatches + `@color_hex` map |
| `lib/storyarn_web/live/flow_live/nodes/exit/node.ex` | Exit `@valid_colors`, `validate_color/1` |
| `assets/js/flow_canvas/nodes/hub.js` | Hub canvas — reads `data.color_hex` |
| `assets/js/flow_canvas/nodes/exit.js` | Exit canvas — has own `colorMap` |
| `lib/storyarn_web/live/sheet_live/components/sheet_color.ex` | Sheet color LiveComponent |
| `lib/storyarn/sheets/sheet.ex` | Sheet schema — validates hex format |

---

## Architecture Decision: Hex Everywhere

**After migration, ALL colors stored as hex strings.** No more preset names.

- Hub: `data["color"]` = `"#8b5cf6"` (was `"purple"`)
- Exit: `data["outcome_color"]` = `"#22c55e"` (was `"green"`)
- Sheet: `sheets.color` = `"#3b82f6"` (already hex)

**Backward compat:** Hub and Exit resolvers must handle both old preset names AND new hex values for existing data. No DB migration needed — resolved at read time.

---

## Phase 1: Install vanilla-colorful + Create Hook

### 1.1 Install package

```bash
cd assets && npm install vanilla-colorful
```

### 1.2 Create hook `assets/js/hooks/color_picker.js`

```javascript
/**
 * ColorPicker hook — wraps vanilla-colorful's <hex-color-picker>.
 *
 * Usage in HEEX:
 *   <div id="color-X" phx-hook="ColorPicker" data-color="#3b82f6" data-event="update_color" data-field="color">
 *     <!-- picker injected here by hook -->
 *   </div>
 *
 * Attributes:
 *   data-color   — initial hex color
 *   data-event   — LiveView event to push (e.g., "update_hub_color")
 *   data-field    — field name sent in event payload
 */
import "vanilla-colorful/hex-color-picker.js";
import "vanilla-colorful/hex-input.js";

export const ColorPicker = {
  mounted() {
    this.render();
  },

  updated() {
    // Sync server-pushed color back to picker (if changed externally)
    const serverColor = this.el.dataset.color;
    if (this.picker && this.picker.color !== serverColor) {
      this.picker.color = serverColor;
    }
    if (this.input && this.input.color !== serverColor) {
      this.input.color = serverColor;
    }
  },

  render() {
    const color = this.el.dataset.color || "#8b5cf6";
    const event = this.el.dataset.event;
    const field = this.el.dataset.field || "color";

    // Create picker
    this.picker = document.createElement("hex-color-picker");
    this.picker.color = color;
    this.picker.style.width = "100%";

    // Create hex input row
    const inputRow = document.createElement("div");
    inputRow.style.cssText = "display:flex;align-items:center;gap:6px;margin-top:6px;";

    const swatch = document.createElement("div");
    swatch.style.cssText = `width:24px;height:24px;border-radius:6px;border:1px solid rgba(0,0,0,0.15);background:${color};flex-shrink:0;`;
    this.swatch = swatch;

    const label = document.createElement("span");
    label.textContent = "#";
    label.style.cssText = "font-size:12px;opacity:0.5;";

    this.input = document.createElement("hex-input");
    this.input.color = color;
    this.input.setAttribute("alpha", "");
    this.input.style.cssText = "flex:1;";

    // Style the inner input
    const innerInput = document.createElement("input");
    innerInput.style.cssText = "width:100%;font-family:monospace;font-size:12px;border:1px solid rgba(0,0,0,0.15);border-radius:4px;padding:2px 6px;background:transparent;color:inherit;";
    this.input.appendChild(innerInput);

    inputRow.append(swatch, label, this.input);
    this.el.append(this.picker, inputRow);

    // Debounce pushEvent to avoid flooding server
    let debounceTimer;
    const pushColor = (hex) => {
      swatch.style.background = hex;
      clearTimeout(debounceTimer);
      debounceTimer = setTimeout(() => {
        this.pushEvent(event, { [field]: hex });
      }, 150);
    };

    this.picker.addEventListener("color-changed", (e) => {
      this.input.color = e.detail.value;
      pushColor(e.detail.value);
    });

    this.input.addEventListener("color-changed", (e) => {
      this.picker.color = e.detail.value;
      pushColor(e.detail.value);
    });
  },

  destroyed() {
    // Web components clean up automatically
  }
};
```

### 1.3 Register hook in `assets/js/app.js`

Add import and register in hooks object:
```javascript
import { ColorPicker } from "./hooks/color_picker";
// ... in hooks: { ..., ColorPicker }
```

---

## Phase 2: Reusable Phoenix Component

### 2.1 Create `lib/storyarn_web/components/color_picker.ex`

A thin function component that renders the hook container:

```elixir
defmodule StoryarnWeb.Components.ColorPicker do
  use Phoenix.Component

  @doc """
  Renders a full-spectrum color picker using vanilla-colorful.

  ## Attributes
    * `id` — required, unique DOM id
    * `color` — current hex color (e.g., "#3b82f6")
    * `event` — LiveView event name to push on change
    * `field` — field name in event payload (default: "color")
    * `disabled` — disable interaction
  """
  attr :id, :string, required: true
  attr :color, :string, default: "#8b5cf6"
  attr :event, :string, required: true
  attr :field, :string, default: "color"
  attr :disabled, :boolean, default: false

  def color_picker(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="ColorPicker"
      phx-update="ignore"
      data-color={@color || "#8b5cf6"}
      data-event={@event}
      data-field={@field}
      class={[@disabled && "pointer-events-none opacity-50"]}
    />
    """
  end
end
```

---

## Phase 3: Hub Node — Replace Select Dropdown

### 3.1 Update `hub/config_sidebar.ex`

Replace `<.input type="select" ...>` with:
```heex
<.color_picker
  id={"hub-color-#{@node.id}"}
  color={@node.data["color"]}
  event="update_hub_color"
  field="color"
  disabled={!@can_edit}
/>
```

Remove `hub_color_options/0` function and `HubColors` alias.

Add import: `import StoryarnWeb.Components.ColorPicker`

### 3.2 Add event handler in `show.ex`

```elixir
def handle_event("update_hub_color", %{"color" => color}, socket) do
  with_auth(:edit_content, socket, fn ->
    node = socket.assigns.selected_node
    NodeHelpers.persist_node_update(socket, node.id, fn data ->
      Map.put(data, "color", color)
    end)
  end)
end
```

### 3.3 Update `hub_colors.ex` — Support hex passthrough

Update `to_hex/2` to handle hex strings directly:

```elixir
def to_hex(name, default) do
  cond do
    String.starts_with?(name || "", "#") -> name  # Already hex
    true -> Map.get(@colors, name, default)        # Preset name
  end
end
```

This provides backward compatibility: old `"purple"` values still resolve, new `"#8b5cf6"` values pass through.

### 3.4 Update `hub.js` — Add needsRebuild for color

```javascript
needsRebuild(oldData, newData) {
  if (oldData?.color_hex !== newData.color_hex) return true;
  return false;
}
```

---

## Phase 4: Exit Node — Replace Swatches

### 4.1 Update `exit/config_sidebar.ex`

Replace the `@outcome_colors` swatches section with:
```heex
<.color_picker
  id={"exit-color-#{@node.id}"}
  color={@node.data["outcome_color"]}
  event="update_outcome_color"
  field="color"
  disabled={!@can_edit}
/>
```

Remove `@outcome_colors`, `@color_hex` module attrs and related assigns.

Add import: `import StoryarnWeb.Components.ColorPicker`

### 4.2 Update `exit/node.ex`

Remove `@valid_colors` and `validate_color/1`. Replace with hex validation:

```elixir
defp validate_color(color) when is_binary(color) do
  if String.match?(color, ~r/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/) do
    color
  else
    # Backward compat: try preset name → hex
    preset_to_hex(color)
  end
end
defp validate_color(_), do: "#22c55e"

@legacy_colors %{
  "green" => "#22c55e", "red" => "#ef4444", "gray" => "#6b7280",
  "amber" => "#f59e0b", "purple" => "#8b5cf6", "blue" => "#3b82f6",
  "cyan" => "#06b6d4", "rose" => "#f43f5e"
}
defp preset_to_hex(name), do: Map.get(@legacy_colors, name, "#22c55e")
```

Update `handle_update_outcome_color` — accept raw hex, no validation against preset list.

### 4.3 Update `exit.js` — Use hex directly

Replace `colorMap` lookup with direct hex:

```javascript
nodeColor(data, _config) {
  const color = data.outcome_color || "#22c55e";
  return color.startsWith("#") ? color : (legacyMap[color] || "#22c55e");
}
```

Keep `legacyMap` for backward compat with old preset names in existing data.

### 4.4 Update `subflow.js` and `subflow/config_sidebar.ex`

Same pattern: use `outcome_color` as hex directly, with legacy fallback.

---

## Phase 5: Sheet — Replace Swatches

### 5.1 Update `sheet_color.ex`

Replace preset swatch buttons with `ColorPicker` component:

```heex
<.color_picker
  id={"sheet-color-#{@sheet.id}"}
  color={@sheet.color || "#3b82f6"}
  event="set_sheet_color"
  field="color"
  disabled={!@can_edit}
/>
```

Keep the "clear color" button (X) as a separate element below the picker.

The LiveComponent will handle `set_sheet_color` event internally (via `phx-target={@myself}`).

**Note:** Since the hook pushes to the parent LV by default, the SheetColor LiveComponent must use `attach_hook` or the parent `show.ex` must route the event. Simplest approach: let the parent `sheet_live/show.ex` receive the event and delegate.

### 5.2 No schema changes needed

Sheet already validates hex colors. No changes to `sheet.ex`.

---

## Phase 6: Cleanup

### 6.1 Files to keep (backward compat)

- `hub_colors.ex` — Keep but update `to_hex/2` for hex passthrough. Still used by serialization.

### 6.2 Constants to remove

- `exit/config_sidebar.ex`: `@outcome_colors`, `@color_hex`
- `exit/node.ex`: `@valid_colors`
- `sheet_color.ex`: `@preset_colors`

### 6.3 JS cleanup

- `exit.js`: Replace `colorMap` with `legacyMap` (only for backward compat)
- `subflow.js`: Same — `colorMap` → `legacyMap`

---

## Files to Modify

| File | Change |
|------|--------|
| `assets/package.json` | Add `vanilla-colorful` dependency |
| `assets/js/hooks/color_picker.js` | **NEW** — Hook wrapping vanilla-colorful |
| `assets/js/app.js` | Register `ColorPicker` hook |
| `lib/storyarn_web/components/color_picker.ex` | **NEW** — Reusable `<.color_picker>` component |
| `lib/storyarn/flows/hub_colors.ex` | Update `to_hex/2` for hex passthrough |
| `lib/storyarn_web/live/flow_live/nodes/hub/config_sidebar.ex` | Replace select with color_picker |
| `lib/storyarn_web/live/flow_live/show.ex` | Add `update_hub_color` event |
| `assets/js/flow_canvas/nodes/hub.js` | Add `needsRebuild` for color changes |
| `lib/storyarn_web/live/flow_live/nodes/exit/config_sidebar.ex` | Replace swatches with color_picker |
| `lib/storyarn_web/live/flow_live/nodes/exit/node.ex` | Hex validation + legacy preset fallback |
| `assets/js/flow_canvas/nodes/exit.js` | Direct hex + legacy fallback |
| `assets/js/flow_canvas/nodes/subflow.js` | Direct hex + legacy fallback |
| `lib/storyarn_web/live/flow_live/nodes/subflow/config_sidebar.ex` | Use hex directly for exit colors |
| `lib/storyarn_web/live/sheet_live/components/sheet_color.ex` | Replace swatches with color_picker |

## New Files

| File | Purpose |
|------|---------|
| `assets/js/hooks/color_picker.js` | LiveView hook for vanilla-colorful |
| `lib/storyarn_web/components/color_picker.ex` | Reusable Phoenix component |

---

## Verification

1. `cd assets && npm install` — vanilla-colorful installs
2. `mix compile` — no errors
3. `mix test test/storyarn/flows_test.exs` — all pass
4. **Hub node**: Select hub → sidebar shows spectrum picker → pick any color → canvas updates
5. **Exit node**: Select exit → sidebar shows spectrum picker → pick any color → canvas updates
6. **Sheet**: Open sheet → color section shows spectrum picker → pick any color → saves
7. **Backward compat**: Existing hub nodes with `"purple"` still render correctly
8. **Backward compat**: Existing exit nodes with `"green"` still render correctly
9. **Subflow exit list**: Shows exit colors correctly (hex or legacy)
