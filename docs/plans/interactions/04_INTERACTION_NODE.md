# Phase 4: Interaction Node — Flow Integration

> **Goal:** Create a new flow node type ("interaction") that references a map and exposes its event zones as dynamic output pins. This is the bridge between the map editor (spatial design) and the flow editor (narrative design).
>
> **Depends on:** Phase 2 (zone action model), Phase 3 (zone action UI)
>
> **Estimated scope:** ~14 files, follows existing node type patterns exactly

---

## Concept

The interaction node is a **blocking node** in the flow — when the Story Player reaches it, execution pauses and the map is rendered with interactive zones. The player interacts freely until they trigger an event zone, which advances the flow through the corresponding output pin.

```
┌─────────────────────────────┐
│  🎮  Character Creation     │
│                             │
│  [Map: Character Sheet]     │
│                             │
│                    accept  ─┤──→ (continue to next scene)
│                    cancel  ─┤──→ (back to menu)
└─────────────────────────────┘
```

### Comparison with existing node types

| Feature                  | Dialogue              | Interaction         |
|--------------------------|-----------------------|---------------------|
| Blocks player            | Yes (waiting_input)   | Yes (waiting_input) |
| Dynamic outputs          | Per response          | Per event zone      |
| User interaction         | Select text response  | Click map zones     |
| Can execute instructions | Response instructions | Instruction zones   |
| Visual content           | Text + speaker        | Map image + zones   |

---

## Data Model

### Node data structure

```elixir
%{
  "map_id" => 42,           # reference to the map entity
  "description" => "",       # optional designer note
  "label" => ""              # optional display label (overrides map name on canvas)
}
```

### Dynamic outputs

The node's output pins are generated from the map's event zones:

```elixir
# Given a map with event zones:
#   zone 1: event_name = "accept", label = "Accept"
#   zone 2: event_name = "cancel", label = "Cancel"
#
# The node has outputs:
#   ["accept", "cancel"]
#
# Connection pins use event_name as the key
```

---

## Files to Create/Modify

| File                                                                             | Change                                    |
|----------------------------------------------------------------------------------|-------------------------------------------|
| **CREATE** `lib/storyarn_web/live/flow_live/nodes/interaction/node.ex`           | Node module                               |
| **CREATE** `lib/storyarn_web/live/flow_live/nodes/interaction/config_sidebar.ex` | Sidebar                                   |
| **CREATE** `assets/js/flow_canvas/nodes/interaction.js`                          | JS canvas rendering                       |
| `lib/storyarn_web/live/flow_live/node_type_registry.ex`                          | Register new type                         |
| `lib/storyarn/flows/flow_node.ex`                                                | Add "interaction" to valid types          |
| `assets/js/flow_canvas/nodes/index.js`                                           | Register JS module                        |
| `lib/storyarn_web/live/flow_live/show.ex`                                        | Event handlers                            |
| `lib/storyarn/maps.ex`                                                           | Query: get_map_brief for node sidebar     |
| `lib/storyarn/flows/flow_queries.ex` (or equivalent)                             | Backlink query: interaction nodes for map |
| `lib/storyarn_web/live/map_live/show.ex`                                         | Load + display referencing flows          |
| `lib/storyarn_web/live/map_live/components/map_header.ex` (or new component)     | Referencing flows UI in map editor        |

---

## Task 1 — Node Module (Elixir)

### 1a — Metadata + callbacks

**CREATE `lib/storyarn_web/live/flow_live/nodes/interaction/node.ex`:**

```elixir
defmodule StoryarnWeb.FlowLive.Nodes.Interaction.Node do
  @moduledoc """
  Interaction node — references a map with actionable zones.

  In the Story Player, this node pauses execution and renders the map
  with interactive zones. Event zones become output pins.
  """

  import StoryarnWeb.Gettext

  alias Storyarn.Maps
  alias StoryarnWeb.FlowLive.Helpers.NodeHelpers

  # ── Metadata ──────────────────────────────────────────────────

  def type, do: "interaction"
  def icon_name, do: "gamepad-2"
  def label, do: dgettext("flows", "Interaction")

  def default_data do
    %{
      "map_id" => nil,
      "description" => "",
      "label" => ""
    }
  end

  def extract_form_data(data) do
    %{
      "map_id" => data["map_id"],
      "description" => data["description"] || "",
      "label" => data["label"] || ""
    }
  end

  def on_select(node, socket) do
    # Load map info + event zones for sidebar display
    map_id = node.data["map_id"]
    project_id = socket.assigns.project.id

    {map_info, event_zones} =
      if map_id do
        map = Maps.get_map_brief(project_id, map_id)
        zones = if map, do: Maps.list_event_zones(map_id), else: []
        {map, zones}
      else
        {nil, []}
      end

    socket
    |> Phoenix.LiveView.assign(:interaction_map, map_info)
    |> Phoenix.LiveView.assign(:interaction_event_zones, event_zones)
  end

  def on_double_click(_node), do: :toolbar

  def duplicate_data_cleanup(data) do
    # Keep map_id reference (it's a shared resource, not unique per node)
    data
  end

  # ── Event Handlers ───────────────────────────────────────────

  @doc """
  Handle map selection for the interaction node.
  """
  def handle_select_map(%{"map-id" => map_id_str} = _params, socket) do
    map_id = String.to_integer(map_id_str)

    NodeHelpers.persist_node_update(socket, socket.assigns.selected_node.id, fn data ->
      Map.put(data, "map_id", map_id)
    end)
  end

  def handle_clear_map(_params, socket) do
    NodeHelpers.persist_node_update(socket, socket.assigns.selected_node.id, fn data ->
      Map.put(data, "map_id", nil)
    end)
  end
end
```

### 1b — Register in node type registry

**`lib/storyarn_web/live/flow_live/node_type_registry.ex`** — Add to `@node_modules`:

```elixir
@node_modules %{
  # ... existing ...
  "interaction" => Nodes.Interaction.Node
}
```

Add alias at top:

```elixir
alias StoryarnWeb.FlowLive.Nodes
```

### 1c — Add to valid node types

**`lib/storyarn/flows/flow_node.ex`** — Add `"interaction"` to the valid types list:

```elixir
~w(dialogue hub condition instruction jump entry exit subflow scene interaction)
```

---

## Task 2 — Config Sidebar

### 2a — Sidebar component

**CREATE `lib/storyarn_web/live/flow_live/nodes/interaction/config_sidebar.ex`:**

```
┌─────────────────────────────────┐
│  🎮 Interaction                 │
│─────────────────────────────────│
│                                 │
│  Map                            │
│  ┌─────────────────────────┐    │
│  │ Character Sheet      ✕  │    │
│  └─────────────────────────┘    │
│  (or)                           │
│  ┌─────────────────────────┐    │
│  │ Select a map...      ▼  │    │
│  └─────────────────────────┘    │
│                                 │
│  Description                    │
│  ┌─────────────────────────┐    │
│  │                         │    │
│  └─────────────────────────┘    │
│                                 │
│  ─── Event Outputs ───          │
│  📤 accept   "Accept"           │
│  📤 cancel   "Cancel"           │
│                                 │
│  ─── Info ───                   │
│  3 instruction zones            │
│  2 display zones                │
│  1 navigate zone                │
│                                 │
│  [Open Map Editor →]            │
└─────────────────────────────────┘
```

```elixir
defmodule StoryarnWeb.FlowLive.Nodes.Interaction.ConfigSidebar do
  use StoryarnWeb, :html

  import StoryarnWeb.Gettext

  attr :node, :map, required: true
  attr :form, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :project, :map, required: true
  attr :current_user, :map, required: true
  attr :interaction_map, :map, default: nil
  attr :interaction_event_zones, :list, default: []
  # Accept all other attrs from properties_panels (pass-through)
  attr :all_sheets, :list, default: []
  attr :flow_hubs, :list, default: []
  attr :project_variables, :list, default: []
  attr :panel_sections, :map, default: %{}
  attr :referencing_jumps, :list, default: []

  def config_sidebar(assigns) do
    map_name = if assigns.interaction_map, do: assigns.interaction_map.name, else: nil
    event_zones = assigns.interaction_event_zones || []

    assigns =
      assigns
      |> assign(:map_name, map_name)
      |> assign(:event_zones, event_zones)
      |> assign(:description, assigns.node.data["description"] || "")

    ~H"""
    <div class="space-y-4">
      <%!-- Map selector --%>
      <div>
        <label class="text-xs font-medium opacity-70 mb-1 block">
          {dgettext("flows", "Map")}
        </label>
        <div :if={@interaction_map} class="flex items-center gap-2 bg-base-200 rounded-lg px-3 py-2">
          <.icon name="map" class="size-4 opacity-60" />
          <span class="text-sm flex-1 truncate">{@map_name}</span>
          <button
            :if={@can_edit}
            type="button"
            phx-click="interaction_clear_map"
            class="btn btn-ghost btn-xs btn-circle"
          >
            <.icon name="x" class="size-3" />
          </button>
        </div>
        <div :if={!@interaction_map}>
          <.map_search_select
            project_id={@project.id}
            can_edit={@can_edit}
          />
        </div>
      </div>

      <%!-- Description --%>
      <div>
        <label class="text-xs font-medium opacity-70 mb-1 block">
          {dgettext("flows", "Description")}
        </label>
        <textarea
          rows="2"
          value={@description}
          placeholder={dgettext("flows", "Designer notes...")}
          class="textarea textarea-bordered textarea-sm w-full"
          phx-blur="update_node_field"
          phx-value-field="description"
          disabled={!@can_edit}
        />
      </div>

      <%!-- Event outputs --%>
      <div :if={@event_zones != []}>
        <h4 class="text-xs font-medium opacity-70 mb-1">
          {dgettext("flows", "Event Outputs")}
        </h4>
        <div class="space-y-1">
          <div :for={zone <- @event_zones} class="flex items-center gap-2 text-xs bg-base-200 rounded px-2 py-1.5">
            <.icon name="send" class="size-3 text-success" />
            <span class="font-mono">{zone.action_data["event_name"]}</span>
            <span :if={zone.action_data["label"]} class="opacity-50 ml-auto truncate">
              {zone.action_data["label"]}
            </span>
          </div>
        </div>
      </div>

      <%!-- Open map editor link --%>
      <div :if={@interaction_map}>
        <.link
          navigate={~p"/projects/#{@project.id}/maps/#{@interaction_map.id}"}
          class="btn btn-xs btn-ghost gap-1 w-full"
        >
          <.icon name="external-link" class="size-3" />
          {dgettext("flows", "Open Map Editor")}
        </.link>
      </div>
    </div>
    """
  end

  # Map search/select component (inline searchable dropdown)
  defp map_search_select(assigns) do
    ~H"""
    <div
      id="interaction-map-search"
      phx-hook="SearchableSelect"
      data-search-event="search_maps_for_interaction"
      data-select-event="interaction_select_map"
      data-placeholder={dgettext("flows", "Search maps...")}
    >
    </div>
    """
  end
end
```

### 2b — Properties panel delegation

**`lib/storyarn_web/live/flow_live/components/properties_panels.ex`** — The existing properties panel already delegates to `config_sidebar` for the selected node type. Ensure the new assigns (`interaction_map`, `interaction_event_zones`) are passed through:

```elixir
# In the config_sidebar call, pass the new assigns:
<.config_sidebar
  {Map.take(assigns, [
    :node, :form, :can_edit, :project, :current_user,
    :all_sheets, :flow_hubs, :project_variables, :panel_sections,
    :referencing_jumps,
    :interaction_map, :interaction_event_zones  # NEW
  ])}
/>
```

---

## Task 3 — Event Handlers (show.ex)

**`lib/storyarn_web/live/flow_live/show.ex`** — Add event dispatchers:

```elixir
def handle_event("interaction_select_map", params, socket) do
  with_auth(:edit_content, socket, fn ->
    Interaction.Node.handle_select_map(params, socket)
  end)
end

def handle_event("interaction_clear_map", _params, socket) do
  with_auth(:edit_content, socket, fn ->
    Interaction.Node.handle_clear_map(%{}, socket)
  end)
end

def handle_event("search_maps_for_interaction", %{"query" => query}, socket) do
  maps = Maps.search_maps(socket.assigns.project.id, query)
  results = Enum.map(maps, fn m -> %{id: m.id, label: m.name} end)
  {:reply, %{results: results}, socket}
end
```

---

## Task 4 — JS Canvas Rendering

### 4a — Node definition

**CREATE `assets/js/flow_canvas/nodes/interaction.js`:**

```javascript
import { html } from "lit";
import { unsafeSVG } from "lit/directives/unsafe-svg.js";
import { Gamepad2 } from "lucide";
import { createIconSvg, createIconHTML } from "../node_config.js";
import {
  nodeShell,
  defaultHeader,
  renderPreview,
} from "./render_helpers.js";

const ICON_SVG = createIconSvg(Gamepad2);
const MAP_ICON = createIconHTML(Gamepad2, { size: 12 });

export default {
  config: {
    label: "Interaction",
    color: "#f59e0b",  // amber — distinct from other node types
    icon: ICON_SVG,
    inputs: ["input"],
    outputs: ["output"],
    dynamicOutputs: true,
  },

  render(ctx) {
    const { node, nodeData, config, selected } = ctx;
    const color = config.color;
    const preview = this.getPreviewText(nodeData);

    return nodeShell(
      color,
      selected,
      html`
        ${defaultHeader(config, color, [])}
        ${preview ? renderPreview(preview) : ""}
      `
    );
  },

  getPreviewText(data) {
    if (data.label) return data.label;
    if (data.map_name) return data.map_name;
    if (data.map_id) return `Map #${data.map_id}`;
    return "No map selected";
  },

  createOutputs(data) {
    // Dynamic outputs from event zones
    // The server pushes event_zone_names in the node data
    const events = data.event_zone_names;
    if (events && events.length > 0) {
      return events;
    }
    return null; // fallback to config.outputs
  },

  formatOutputLabel(key, data) {
    // Event zone labels
    const labels = data.event_zone_labels || {};
    return labels[key] || key;
  },

  getOutputBadges(_key, _data) {
    return [];
  },

  needsRebuild(oldData, newData) {
    // Rebuild if map_id or event zones changed
    if (oldData.map_id !== newData.map_id) return true;
    if (JSON.stringify(oldData.event_zone_names) !== JSON.stringify(newData.event_zone_names))
      return true;
    return false;
  },
};
```

### 4b — Register in JS index

**`assets/js/flow_canvas/nodes/index.js`:**

```javascript
import interaction from "./interaction.js";

const NODE_DEFS = {
  // ... existing ...
  interaction,
};
```

---

## Task 5 — Push Event Zones to Canvas

The JS node needs `event_zone_names` and `event_zone_labels` in the node data to create dynamic outputs. These must be pushed from the server when the node data changes.

### 5a — Enrich node data on load

When loading flow nodes for the canvas, enrich interaction nodes with their event zone info:

**In the flow data loading** (wherever nodes are serialized for the JS canvas):

```elixir
defp enrich_node_data(%{type: "interaction", data: data} = node) do
  map_id = data["map_id"]

  if map_id do
    event_zones = Maps.list_event_zones(map_id)
    map_info = Maps.get_map_brief(node_project_id, map_id)

    enriched = data
    |> Map.put("event_zone_names", Enum.map(event_zones, & &1.action_data["event_name"]))
    |> Map.put("event_zone_labels",
      Map.new(event_zones, fn z ->
        {z.action_data["event_name"], z.action_data["label"] || z.action_data["event_name"]}
      end))
    |> Map.put("map_name", map_info && map_info.name)

    %{node | data: enriched}
  else
    node
  end
end

defp enrich_node_data(node), do: node
```

This enrichment happens at serialization time only (not stored in DB). The canonical data stays clean (`map_id` only).

### 5b — Re-enrich after map selection

When `handle_select_map` updates the node, the canvas push already reloads the flow data. The enrichment function runs on every canvas push, so the event zones update automatically.

---

## Task 6 — Map Search for Sidebar

The sidebar needs a searchable map picker. Options:

**Option A (simple):** Reuse the existing `SearchableSelect` hook pattern with a `search_maps_for_interaction` event (shown above).

**Option B (simpler):** A basic `<select>` with all project maps pre-loaded:

```heex
<select
  class="select select-sm select-bordered w-full"
  phx-change="interaction_select_map"
>
  <option value="">{dgettext("flows", "Select a map...")}</option>
  <option :for={map <- @project_maps} value={map.id}>
    {map.name}
  </option>
</select>
```

Recommendation: **Option B** for initial implementation (simpler, avoids hook complexity). The search event approach (Option A) can be added later if the map list grows large.

Load `project_maps` in the flow LiveView mount:

```elixir
project_maps = Maps.list_maps(project.id)
assign(socket, :project_maps, project_maps)
```

---

## Task 7 — Cross-Navigation: Map ↔ Flow

Bidirectional navigation between maps and the flows that reference them. Follows the same pattern as hub nodes showing "referencing jumps".

### 7a — Backlink query

**`lib/storyarn/flows/flow_queries.ex`** (or wherever flow queries live) — Query flow nodes of type "interaction" that reference a given map:

```elixir
@doc """
Lists all interaction nodes that reference a given map.
Returns node + flow info for navigation.
"""
@spec list_interaction_nodes_for_map(integer()) :: [map()]
def list_interaction_nodes_for_map(map_id) do
  map_id_str = to_string(map_id)

  from(n in FlowNode,
    join: f in Flow,
    on: n.flow_id == f.id,
    join: p in Project,
    on: f.project_id == p.id,
    where: n.type == "interaction",
    where: is_nil(n.deleted_at) and is_nil(f.deleted_at),
    where: fragment("?->>'map_id' = ?", n.data, ^map_id_str),
    select: %{
      node_id: n.id,
      flow_id: f.id,
      flow_name: f.name,
      project_id: p.id,
      node_label: fragment("COALESCE(NULLIF(?->>'label', ''), ?)", n.data, f.name)
    },
    order_by: [asc: f.name]
  )
  |> Repo.all()
end
```

Expose via facade:

```elixir
# lib/storyarn/flows.ex
defdelegate list_interaction_nodes_for_map(map_id), to: FlowQueries
```

### 7b — Map editor: load referencing flows on mount

**`lib/storyarn_web/live/map_live/show.ex`** — On mount, load referencing interaction nodes:

```elixir
# In mount or handle_params:
referencing_flows = Flows.list_interaction_nodes_for_map(map.id)
assign(socket, :referencing_flows, referencing_flows)
```

### 7c — Map editor: referencing flows UI

Display in the map header or as a collapsible panel. Shows which flows use this map with navigation links.

```
┌─────────────────────────────────────────┐
│ 🎮 Used in flows:                       │
│  ├── Character Creation (Main Quest)    │  ← click navigates to flow
│  └── Tutorial Flow                      │  ← click navigates to flow
└─────────────────────────────────────────┘
```

**Component (in map header or a dedicated panel):**

```heex
<div :if={@referencing_flows != []} class="flex items-center gap-2">
  <div class="dropdown dropdown-bottom dropdown-end">
    <label tabindex="0" class="btn btn-xs btn-ghost gap-1">
      <.icon name="git-branch" class="size-3.5 opacity-60" />
      <span class="text-xs">
        {dngettext("maps", "Used in %{count} flow", "Used in %{count} flows", length(@referencing_flows), count: length(@referencing_flows))}
      </span>
    </label>
    <ul tabindex="0" class="dropdown-content menu menu-xs bg-base-200 rounded-lg shadow-lg z-50 w-56">
      <li :for={ref <- @referencing_flows}>
        <.link navigate={~p"/projects/#{ref.project_id}/flows/#{ref.flow_id}"}>
          <.icon name="git-branch" class="size-3.5 opacity-60" />
          <span class="truncate">{ref.flow_name}</span>
        </.link>
      </li>
    </ul>
  </div>
</div>
```

### 7d — Event zone → flow destination preview

In the map editor, when selecting an event zone, show where the event connects in the flow (if resolvable). This requires knowing which interaction node references this map and what's connected to the event pin.

**In the floating toolbar for event zones:**

```heex
<div :if={@event_destination}>
  <p class="text-xs opacity-50 mt-1">
    <.icon name="arrow-right" class="size-3 inline" />
    {dgettext("maps", "Connects to:")}
    <.link
      navigate={~p"/projects/#{@project_id}/flows/#{@event_destination.flow_id}"}
      class="link link-primary"
    >
      {event_destination.target_label}
    </.link>
  </p>
</div>
```

This is optional / best-effort — if multiple flows reference the same map, show all destinations. If no connections exist for the event, show nothing.

**Query to resolve event destinations:**

```elixir
@spec list_event_zone_destinations(integer(), String.t()) :: [map()]
def list_event_zone_destinations(map_id, event_name) do
  # Find interaction nodes for this map
  # Then find connections from those nodes with source_pin = event_name
  # Return target node info
  from(c in FlowConnection,
    join: n in FlowNode,
    on: c.source_node_id == n.id,
    join: tn in FlowNode,
    on: c.target_node_id == tn.id,
    join: f in Flow,
    on: n.flow_id == f.id,
    where: n.type == "interaction",
    where: is_nil(n.deleted_at) and is_nil(f.deleted_at),
    where: fragment("?->>'map_id' = ?", n.data, ^to_string(map_id)),
    where: c.source_pin == ^event_name,
    select: %{
      flow_id: f.id,
      flow_name: f.name,
      target_node_id: tn.id,
      target_node_type: tn.type,
      target_label: fragment("COALESCE(NULLIF(?->>'label', ''), NULLIF(?->>'text', ''), ?)", tn.data, tn.data, tn.type)
    }
  )
  |> Repo.all()
end
```

---

## Verification

```bash
mix test test/storyarn/flows/
just quality
```

Manual:
1. Open flow editor → add an "Interaction" node from the palette
2. Select it → sidebar shows "Select a map" dropdown
3. Pick a map that has event zones → verify output pins appear on the node
4. Verify the node displays the map name as preview text
5. Verify "Open Map Editor" link navigates correctly
6. Connect event zone outputs to other nodes → verify connections work
7. Duplicate the node → verify map_id is preserved
8. Change the map → verify output pins update
9. **Open the referenced map** → verify "Used in N flows" badge appears in map header
10. **Click a flow link** → verify it navigates to the flow editor
11. **Select an event zone in map editor** → verify "Connects to: [node]" shows the flow destination
