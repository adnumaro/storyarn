# Phase 3: Actionable Zones — Map Editor UI

> **Goal:** Add UI controls in the map editor for creating and configuring actionable zones (instruction, display, event). This enables designers to visually set up interactive elements on their maps.
>
> **Depends on:** Phase 2 (zone action model)
>
> **Estimated scope:** ~10 files, UI-heavy

---

## Overview

The map editor already supports creating zones (polygon drawing), selecting zones (click), and configuring zones (floating toolbar). This phase extends the floating toolbar and zone editing to support the new action types.

### Current zone editing flow

```
1. User draws zone (polygon tool)
2. Zone appears on canvas
3. User clicks zone → floating toolbar appears
4. Floating toolbar: name, color, target picker, lock, delete
```

### New zone editing flow

```
1. User draws zone (polygon tool)
2. Zone appears on canvas
3. User clicks zone → floating toolbar appears
4. Floating toolbar: name, ACTION TYPE SELECTOR, type-specific config, color, lock, delete
   ├── navigate: target picker (existing)
   ├── instruction: assignment builder
   ├── display: variable picker + label
   └── event: event name input
```

---

## Visual Mocks

### Floating toolbar with action type selector

```
┌───────────────────────────────────────────────────────────────┐
│ [🔗 Navigate ▼]  Name: [Zone name     ]  🎨  🔒  🗑          │
│                                                               │
│ Target: [Select target...              ▼]                     │
└───────────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────────┐
│ [⚡ Action ▼]    Name: [+1 STR         ]  🎨  🔒  🗑           │
│                                                               │
│ ┌─────────────────────────────────────────────────────────┐   │
│ │ mc.jaime › str       [+=]  1                        ✕   │   │
│ │ mc.jaime › points    [-=]  1                        ✕   │   │
│ │ + Add assignment                                        │   │
│ └─────────────────────────────────────────────────────────┘   │
└───────────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────────┐
│ [📊 Display ▼]   Name: [STR Value      ]  🎨  🔒  🗑         │
│                                                               │
│ Variable: [mc.jaime.str               ▼]                      │
│ Label:    [STR                          ]                     │
└───────────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────────┐
│ [📤 Event ▼]     Name: [Accept Button   ]  🎨  🔒  🗑        │
│                                                               │
│ Event name: [accept                     ]                     │
│ Label:      [Accept                     ]                     │
└───────────────────────────────────────────────────────────────┘
```

### Action type dropdown

```
┌──────────────────┐
│ 🔗 Navigate      │ ← link to sheet/flow/map
│ ⚡ Action         │ ← execute instructions
│ 📊 Display       │ ← show variable value
│ 📤 Event         │ ← emit named event
└──────────────────┘
```

### Zone visual indicators on canvas

Zones display a small icon badge in their center based on action type:

```
Navigate zone:     🔗 (link icon, existing behavior)
Instruction zone:  ⚡ (zap icon)
Display zone:      📊 (bar-chart icon) + variable label text
Event zone:        📤 (send icon) + event name text
```

---

## Files to Modify

| File                                                            | Change                                         |
|-----------------------------------------------------------------|------------------------------------------------|
| `lib/storyarn_web/live/scene_live/components/floating_toolbar.ex` | Action type selector, type-specific panels     |
| `lib/storyarn_web/live/scene_live/components/toolbar_widgets.ex`  | New widget components                          |
| `lib/storyarn_web/live/scene_live/handlers/element_handlers.ex`   | Handle action type changes, assignment updates |
| `lib/storyarn_web/live/scene_live/show.ex`                        | New events, project_variables assign           |
| `assets/js/scene_canvas/handlers/zone_handler.js`                 | Zone badge rendering                           |
| `assets/js/scene_canvas/zone_renderer.js`                         | Action type visual indicators                  |
| `assets/js/hooks/scene_canvas.js`                                 | Pass action data to renderer                   |
| `lib/storyarn_web/live/scene_live/helpers/serializer.ex`          | Already done in Phase 2                        |

---

## Task 1 — Action Type Selector

### 1a — Floating toolbar: action type dropdown

**`lib/storyarn_web/live/scene_live/components/floating_toolbar.ex`** — When a zone is selected, show an action type selector before the name field.

The selector is a dropdown button showing the current action type with its icon:

```heex
<div :if={@selected_type == "zone"} class="flex items-center gap-1">
  <div class="dropdown dropdown-bottom">
    <label tabindex="0" class="btn btn-xs btn-ghost gap-1">
      <.icon name={action_type_icon(@selected_element.action_type)} class="size-3.5" />
      <span class="text-xs">{action_type_label(@selected_element.action_type)}</span>
      <.icon name="chevron-down" class="size-3" />
    </label>
    <ul tabindex="0" class="dropdown-content menu menu-xs bg-base-200 rounded-lg shadow-lg z-50 w-40">
      <li :for={type <- ~w(navigate instruction display event)}>
        <button
          phx-click="set_zone_action_type"
          phx-value-zone-id={@selected_element.id}
          phx-value-action-type={type}
          class={[@selected_element.action_type == type && "active"]}
        >
          <.icon name={action_type_icon(type)} class="size-3.5" />
          <span>{action_type_label(type)}</span>
        </button>
      </li>
    </ul>
  </div>
</div>
```

Helper functions:

```elixir
defp action_type_icon("navigate"), do: "link"
defp action_type_icon("instruction"), do: "zap"
defp action_type_icon("display"), do: "bar-chart-3"
defp action_type_icon("event"), do: "send"

defp action_type_label("navigate"), do: dgettext("maps", "Navigate")
defp action_type_label("instruction"), do: dgettext("maps", "Action")
defp action_type_label("display"), do: dgettext("maps", "Display")
defp action_type_label("event"), do: dgettext("maps", "Event")
```

### 1b — Type-specific config panels

Below the action type selector, render the appropriate config panel:

```heex
<%= case @selected_element.action_type do %>
  <% "navigate" -> %>
    <%!-- Existing target picker (sheet/flow/map) — no change --%>
    <.target_picker element={@selected_element} ... />

  <% "instruction" -> %>
    <.zone_instruction_editor
      zone={@selected_element}
      project_variables={@project_variables}
      can_edit={@can_edit}
      target={@myself}
    />

  <% "display" -> %>
    <.zone_display_editor
      zone={@selected_element}
      project_variables={@project_variables}
      target={@myself}
    />

  <% "event" -> %>
    <.zone_event_editor
      zone={@selected_element}
      target={@myself}
    />
<% end %>
```

---

## Task 2 — Instruction Zone Editor

### 2a — Assignment list

The instruction zone editor renders a simplified assignment list. Reuse the same data structure as instruction nodes but with an inline UI (not the full instruction builder hook).

```heex
defp zone_instruction_editor(assigns) do
  assignments = (assigns.zone.action_data || %{})["assignments"] || []
  assigns = assign(assigns, :assignments, assignments)

  ~H"""
  <div class="space-y-1 mt-2">
    <div :for={assignment <- @assignments} class="flex items-center gap-1 text-xs bg-base-300/50 rounded px-1.5 py-1">
      <span class="font-mono truncate">
        {format_assignment_short(assignment)}
      </span>
      <button
        type="button"
        phx-click="remove_zone_assignment"
        phx-value-zone-id={@zone.id}
        phx-value-assignment-id={assignment["id"]}
        phx-target={@target}
        class="btn btn-ghost btn-xs btn-circle ml-auto"
      >
        <.icon name="x" class="size-3" />
      </button>
    </div>
    <button
      type="button"
      phx-click="open_zone_assignment_editor"
      phx-value-zone-id={@zone.id}
      phx-target={@target}
      class="btn btn-xs btn-ghost gap-1 w-full"
    >
      <.icon name="plus" class="size-3" />
      <span>{dgettext("maps", "Add assignment")}</span>
    </button>
  </div>
  """
end
```

### 2b — Assignment editor modal

When "Add assignment" is clicked, open a modal with the full instruction builder (reusing the existing hook):

```heex
<.modal id="zone-assignment-modal">
  <div
    id={"zone-assignment-builder-#{@zone.id}"}
    phx-hook="InstructionBuilder"
    data-assignments={Jason.encode!(@assignments)}
    data-variables={Jason.encode!(@project_variables)}
    data-can-edit="true"
    data-event-name="update_zone_assignments"
    data-context={Jason.encode!(%{"zone-id" => @zone.id})}
  >
  </div>
</.modal>
```

The `InstructionBuilder` hook pushes `update_zone_assignments` with `{assignments: [...], "zone-id": id}`.

---

## Task 3 — Display Zone Editor

### 3a — Variable picker

```heex
defp zone_display_editor(assigns) do
  action_data = assigns.zone.action_data || %{}
  assigns =
    assigns
    |> assign(:variable_ref, action_data["variable_ref"] || "")
    |> assign(:label, action_data["label"] || "")

  ~H"""
  <div class="space-y-2 mt-2">
    <div>
      <label class="text-xs font-medium opacity-70">{dgettext("maps", "Variable")}</label>
      <select
        class="select select-xs select-bordered w-full"
        phx-change="update_zone_display_variable"
        phx-value-zone-id={@zone.id}
        phx-target={@target}
      >
        <option value="">{dgettext("maps", "Select variable...")}</option>
        <option
          :for={var <- @project_variables}
          value={var_ref(var)}
          selected={var_ref(var) == @variable_ref}
        >
          {var.sheet_shortcut}.{var.variable_name} ({var.block_type})
        </option>
      </select>
    </div>
    <div>
      <label class="text-xs font-medium opacity-70">{dgettext("maps", "Label")}</label>
      <input
        type="text"
        value={@label}
        placeholder={dgettext("maps", "Display label")}
        class="input input-xs input-bordered w-full"
        phx-blur="update_zone_display_label"
        phx-value-zone-id={@zone.id}
        phx-target={@target}
      />
    </div>
  </div>
  """
end

defp var_ref(var) do
  if var.table_name do
    "#{var.sheet_shortcut}.#{var.table_name}.#{var.row_name}.#{var.column_name}"
  else
    "#{var.sheet_shortcut}.#{var.variable_name}"
  end
end
```

---

## Task 4 — Event Zone Editor

```heex
defp zone_event_editor(assigns) do
  action_data = assigns.zone.action_data || %{}
  assigns =
    assigns
    |> assign(:event_name, action_data["event_name"] || "")
    |> assign(:label, action_data["label"] || "")

  ~H"""
  <div class="space-y-2 mt-2">
    <div>
      <label class="text-xs font-medium opacity-70">{dgettext("maps", "Event name")}</label>
      <input
        type="text"
        value={@event_name}
        placeholder="accept"
        class="input input-xs input-bordered w-full font-mono"
        phx-blur="update_zone_event_name"
        phx-value-zone-id={@zone.id}
        phx-target={@target}
      />
      <p class="text-xs opacity-50 mt-0.5">
        {dgettext("scenes", "This event zone triggers a flow transition")}
      </p>
    </div>
    <div>
      <label class="text-xs font-medium opacity-70">{dgettext("maps", "Label")}</label>
      <input
        type="text"
        value={@label}
        placeholder={dgettext("maps", "Button label")}
        class="input input-xs input-bordered w-full"
        phx-blur="update_zone_event_label"
        phx-value-zone-id={@zone.id}
        phx-target={@target}
      />
    </div>
  </div>
  """
end
```

---

## Task 5 — Event Handlers

### 5a — Action type change

**`lib/storyarn_web/live/scene_live/handlers/element_handlers.ex`** — Add handler:

```elixir
def handle_set_zone_action_type(socket, %{"zone-id" => zone_id, "action-type" => action_type}) do
  zone = Maps.get_zone(socket.assigns.map.id, parse_id(zone_id))

  # Reset action_data when changing types
  default_data = case action_type do
    "navigate" -> %{}
    "instruction" -> %{"assignments" => []}
    "display" -> %{"variable_ref" => "", "format" => "number", "label" => ""}
    "event" -> %{"event_name" => "", "label" => ""}
  end

  case Maps.update_zone(zone, %{action_type: action_type, action_data: default_data}) do
    {:ok, updated} ->
      socket
      |> assign(:selected_element, updated)
      |> reload_map()
      |> then(&{:noreply, &1})

    {:error, _} ->
      {:noreply, put_flash(socket, :error, gettext("Failed to update zone"))}
  end
end
```

### 5b — Instruction assignments update

```elixir
def handle_update_zone_assignments(socket, %{"zone-id" => zone_id, "assignments" => assignments}) do
  zone = Maps.get_zone(socket.assigns.map.id, parse_id(zone_id))
  new_data = Map.put(zone.action_data || %{}, "assignments", assignments)

  case Maps.update_zone(zone, %{action_data: new_data}) do
    {:ok, updated} ->
      {:noreply, socket |> assign(:selected_element, updated) |> reload_map()}
    {:error, _} ->
      {:noreply, put_flash(socket, :error, gettext("Failed to update zone"))}
  end
end
```

### 5c — Display variable update

```elixir
def handle_update_zone_display_variable(socket, %{"zone-id" => zone_id, "value" => variable_ref}) do
  zone = Maps.get_zone(socket.assigns.map.id, parse_id(zone_id))
  new_data = Map.put(zone.action_data || %{}, "variable_ref", variable_ref)

  case Maps.update_zone(zone, %{action_data: new_data}) do
    {:ok, updated} ->
      {:noreply, socket |> assign(:selected_element, updated) |> reload_map()}
    {:error, _} ->
      {:noreply, put_flash(socket, :error, gettext("Failed to update zone"))}
  end
end
```

### 5d — Event zone updates (similar pattern)

```elixir
def handle_update_zone_event_name(socket, %{"zone-id" => zone_id, "value" => event_name}) do
  # Same pattern: update action_data["event_name"]
end
```

### 5e — Wire events in show.ex

```elixir
def handle_event("set_zone_action_type", params, socket) do
  with_edit_mode(socket, fn ->
    ElementHandlers.handle_set_zone_action_type(socket, params)
  end)
end

def handle_event("update_zone_assignments", params, socket) do
  with_edit_mode(socket, fn ->
    ElementHandlers.handle_update_zone_assignments(socket, params)
  end)
end

# ... etc for display and event handlers
```

---

## Task 6 — Load Project Variables

**`lib/storyarn_web/live/scene_live/show.ex`** — On mount, load project variables for the assignment builder and variable picker:

```elixir
# In mount or reload:
project_variables = Sheets.list_project_variables(project.id)
assign(socket, :project_variables, project_variables)
```

Pass down to floating toolbar component.

---

## Task 7 — Canvas Visual Indicators

### 7a — Zone renderer badges

**`assets/js/scene_canvas/zone_renderer.js`** — When rendering a zone, add a small icon badge in the center based on `action_type`:

```javascript
function renderZoneBadge(zone, polygon) {
  if (zone.action_type === "navigate" || !zone.action_type) return;

  const center = polygon.getBounds().getCenter();
  const icons = {
    instruction: "⚡",
    display: "📊",
    event: "📤"
  };

  const label = zone.action_data?.label || zone.action_data?.event_name || "";
  const icon = icons[zone.action_type] || "";

  const marker = L.marker(center, {
    icon: L.divIcon({
      className: "zone-action-badge",
      html: `<span class="zone-badge zone-badge-${zone.action_type}">${icon} ${label}</span>`,
      iconSize: null
    }),
    interactive: false
  });

  marker.addTo(layerGroup);
}
```

### 7b — CSS for zone badges

```css
.zone-action-badge {
  pointer-events: none;
}
.zone-badge {
  font-size: 11px;
  font-weight: 600;
  padding: 2px 6px;
  border-radius: 4px;
  white-space: nowrap;
  background: rgba(0, 0, 0, 0.6);
  color: white;
}
.zone-badge-instruction { border-left: 3px solid #f59e0b; }
.zone-badge-display { border-left: 3px solid #3b82f6; }
.zone-badge-event { border-left: 3px solid #10b981; }
```

---

## Verification

```bash
mix test test/storyarn/maps/
just quality
```

Manual:
1. Open map editor → create a zone → verify "Navigate" is default in toolbar
2. Switch to "Action" → verify assignment list appears → add an assignment
3. Switch to "Display" → verify variable picker appears → select a variable
4. Switch to "Event" → verify event name input appears → type "accept"
5. Verify zone badges appear on canvas for non-navigate zones
6. Verify switching action type resets config appropriately
7. Verify existing navigate zones still work identically
