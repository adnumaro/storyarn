# Phase 5: Interaction Player — Story Player Integration

> **Goal:** Make interaction nodes playable in the Story Player. When the player reaches an interaction node, it renders the map image with clickable zones. Instruction zones execute and update variables. Display zones show live variable values. Event zones advance the flow.
>
> **Depends on:** Phase 4 (interaction node), Phase 1 (number constraints for clamping)
>
> **Estimated scope:** ~10 files, evaluator + player UI

---

## Concept

The Story Player already handles two interactive states:
1. **Dialogue** — shows text, waits for response selection
2. **Exit** — shows outcome summary

The interaction node adds a third:
3. **Interaction** — shows map image with clickable zones, waits for event zone click

### Player flow

```
Flow reaches interaction node
         │
         ▼
┌─────────────────────────────────────────┐
│  ┌───────────────────────────────────┐  │
│  │                                   │  │
│  │   [Map background image]          │  │
│  │                                   │  │
│  │   ┌─────┐          ┌───────────┐  │  │
│  │   │ +1  │  STR: 12 │  Accept   │  │  │
│  │   └─────┘          └───────────┘  │  │
│  │   ┌─────┐                         │  │
│  │   │ -1  │  Points: 5              │  │
│  │   └─────┘                         │  │
│  │                                   │  │
│  └───────────────────────────────────┘  │
│                                         │
│  Variables panel shows live updates     │
└─────────────────────────────────────────┘
         │
    User clicks "Accept" (event zone)
         │
         ▼
   Flow continues through "accept" output
```

### Interaction state machine

```
1. Engine evaluates interaction node → {:waiting_input, state}
   state.pending_choices = %{
     type: :interaction,
     node_id: node_id,
     map_id: map_id,
     zones: [zone_data...]
   }

2. Player renders map with zones
   - Instruction zones: clickable, execute assignments
   - Display zones: show variable values (update live)
   - Event zones: clickable, advance flow

3. User clicks instruction zone:
   - Execute assignments → update state.variables
   - Re-render display zones with new values
   - Console log: "⚡ Executed: STR += 1, Points -= 1"
   - Stay in waiting_input

4. User clicks event zone:
   - Engine.choose_interaction_event(state, event_name, connections)
   - Find connection from event_name pin → target node
   - Advance to target node
   - Console log: "📤 Event: accept"
```

---

## Visual Mock — Player Interaction View

```
┌─────────────────────────────────────────────────────────────┐
│  Story Player                                    [▶] [⏹]    │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │                                                     │    │
│  │            [Background Image]                       │    │
│  │                                                     │    │
│  │    ┌───┐                              ┌───┐         │    │
│  │    │ + │   ┌─────┐              ┌───┐ │ + │         │    │
│  │    └───┘   │ STR │              │WIS│ └───┘         │    │
│  │    ┌───┐   │  9  │              │ 9 │ ┌───┐         │    │
│  │    │ - │   └─────┘              └───┘ │ - │         │    │
│  │    └───┘                              └───┘         │    │
│  │                                                     │    │
│  │          ┌──────────┐  ┌──────────┐                 │    │
│  │          │  Accept  │  │  Cancel  │                 │    │
│  │          └──────────┘  └──────────┘                 │    │
│  │                                                     │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  ┌─ Console ────────────────────────────────────────────┐   │
│  │ 12:01 ⚡ Character Creation — STR: 9 → 10 (add)       │   │
│  │ 12:01 ⚡ Character Creation — Points: 21 → 20 (sub)   │   │
│  │ 12:02 📤 Character Creation — Event: accept          │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## Files to Create/Modify

| File                                                                                 | Change                            |
|--------------------------------------------------------------------------------------|-----------------------------------|
| **CREATE** `lib/storyarn/flows/evaluator/node_evaluators/interaction_evaluator.ex`   | Evaluator                         |
| `lib/storyarn/flows/evaluator/engine.ex`                                             | Dispatch to interaction evaluator |
| `lib/storyarn/flows/evaluator/state.ex`                                              | pending_choices interaction type  |
| `lib/storyarn_web/live/flow_live/player/slide.ex`                                    | Build interaction slide           |
| **CREATE** `lib/storyarn_web/live/flow_live/player/components/player_interaction.ex` | Player UI                         |
| `lib/storyarn_web/live/flow_live/player/components/player_slide.ex`                  | Render interaction slide          |
| `lib/storyarn_web/live/flow_live/player/player_engine.ex`                            | NOT non-interactive               |
| `lib/storyarn_web/live/flow_live/handlers/debug_execution_handlers.ex`               | Handle zone clicks                |
| **CREATE** `assets/js/hooks/interaction_player.js`                                   | Map rendering in player           |
| `test/storyarn/flows/evaluator/interaction_evaluator_test.exs`                       | Tests                             |

---

## Task 1 — Evaluator

### 1a — Interaction evaluator

**CREATE `lib/storyarn/flows/evaluator/node_evaluators/interaction_evaluator.ex`:**

```elixir
defmodule Storyarn.Flows.Evaluator.NodeEvaluators.InteractionEvaluator do
  @moduledoc """
  Evaluates interaction nodes.

  Puts the engine in :waiting_input state with map zone data.
  The player UI renders the map and handles zone clicks.
  """

  alias Storyarn.Flows.Evaluator.Helpers, as: EngineHelpers
  alias Storyarn.Flows.Evaluator.InstructionExec

  @doc """
  First evaluation: set up waiting_input with zone data.
  """
  def evaluate(node, state, _connections) do
    data = node.data || %{}
    label = EngineHelpers.node_label(node) || data["label"] || "Interaction"
    map_id = data["map_id"]

    if is_nil(map_id) do
      state = EngineHelpers.add_console(state, :error, node.id, label, "No map assigned")
      {:error, state, :no_map}
    else
      # Zone data is loaded and passed by the player handler (not queried here)
      # The evaluator is pure — no DB access
      pending = %{
        type: :interaction,
        node_id: node.id,
        map_id: map_id,
        label: label
      }

      state =
        state
        |> Map.put(:pending_choices, pending)
        |> Map.put(:status, :waiting_input)
        |> EngineHelpers.add_console(:info, node.id, label, "Interaction — waiting for input")

      {:waiting_input, state}
    end
  end

  @doc """
  Execute an instruction zone's assignments.
  Returns updated state (still waiting_input).
  """
  def execute_instruction(state, assignments, node_id, label) do
    case InstructionExec.execute(assignments, state.variables) do
      {:ok, new_variables, changes, errors} ->
        state = %{state | variables: new_variables}

        # Log changes
        state =
          Enum.reduce(changes, state, fn change, acc ->
            msg = "#{change.variable_ref}: #{format_val(change.old_value)} → #{format_val(change.new_value)} (#{change.operator})"
            EngineHelpers.add_console(acc, :info, node_id, label, msg)
          end)

        # Log errors
        state =
          Enum.reduce(errors, state, fn error, acc ->
            EngineHelpers.add_console(acc, :error, node_id, label, error.reason)
          end)

        # Update history
        state = EngineHelpers.add_history_entries(state, node_id, label, changes, :instruction)

        {:ok, state}

      _ ->
        {:ok, state}
    end
  end

  @doc """
  Handle event zone trigger — find connection and advance.
  """
  def choose_event(state, event_name, connections) do
    node_id = state.pending_choices.node_id
    label = state.pending_choices.label

    state = EngineHelpers.add_console(state, :info, node_id, label, "Event: #{event_name}")

    # Clear pending
    state = %{state | pending_choices: nil, status: :paused}

    # Find connection from event pin
    case EngineHelpers.find_connection(connections, node_id, event_name) do
      nil ->
        state = EngineHelpers.add_console(state, :warning, node_id, label, "No connection for event '#{event_name}'")
        {:finished, %{state | status: :finished}}

      conn ->
        EngineHelpers.advance_to(state, conn.target_node_id)
    end
  end

  defp format_val(nil), do: "nil"
  defp format_val(val), do: to_string(val)
end
```

### 1b — Engine dispatch

**`lib/storyarn/flows/evaluator/engine.ex`** — Add pattern match:

```elixir
defp evaluate_node(%{type: "interaction"} = node, state, connections, _nodes) do
  InteractionEvaluator.evaluate(node, state, connections)
end
```

Add alias:

```elixir
alias Storyarn.Flows.Evaluator.NodeEvaluators.InteractionEvaluator
```

### 1c — Engine public API: instruction execution + event choice

Add public functions to the Engine for the player to call:

```elixir
@doc """
Execute an instruction zone in an interaction node.
Does not advance the flow — stays in waiting_input.
"""
def execute_interaction_instruction(state, assignments) do
  %{node_id: node_id, label: label} = state.pending_choices
  InteractionEvaluator.execute_instruction(state, assignments, node_id, label)
end

@doc """
Choose an event zone in an interaction node.
Advances the flow through the event's output pin.
"""
def choose_interaction_event(state, event_name, connections) do
  InteractionEvaluator.choose_event(state, event_name, connections)
end
```

---

## Task 2 — Player Engine

### 2a — NOT non-interactive

**`lib/storyarn_web/live/flow_live/player/player_engine.ex`** — The interaction node is NOT in `@non_interactive_types`. It's already excluded because only listed types auto-advance:

```elixir
@non_interactive_types ~w(entry hub condition instruction jump scene subflow)
# "interaction" is NOT here → player stops at it
```

No change needed. When the engine returns `{:waiting_input, state}`, the player stops and shows the interaction UI.

---

## Task 3 — Slide Builder

### 3a — Build interaction slide

**`lib/storyarn_web/live/flow_live/player/slide.ex`** — Add clause:

```elixir
def build(%{type: "interaction"} = node, state, _sheets_map, project_id) do
  data = node.data || %{}
  map_id = data["map_id"]

  # Load map with zones for rendering
  # Note: this is the only place where the slide builder needs DB access
  # via the project_id. The map data is loaded here for the player UI.
  {map_data, zones} =
    if map_id do
      map = Storyarn.Maps.get_map(project_id, map_id)
      zones = if map, do: Storyarn.Maps.list_zones(map_id), else: []
      {map, zones}
    else
      {nil, []}
    end

  %{
    type: :interaction,
    node_id: node.id,
    label: data["label"] || (map_data && map_data.name) || "Interaction",
    map_id: map_id,
    map_name: map_data && map_data.name,
    background_url: map_data && extract_background_url(map_data),
    map_width: map_data && map_data.width,
    map_height: map_data && map_data.height,
    zones: Enum.map(zones, &serialize_zone_for_player(&1, state))
  }
end

defp serialize_zone_for_player(zone, state) do
  base = %{
    id: zone.id,
    name: zone.name,
    vertices: zone.vertices,
    fill_color: zone.fill_color,
    border_color: zone.border_color,
    opacity: zone.opacity,
    action_type: zone.action_type,
    action_data: zone.action_data
  }

  # For display zones, resolve current variable value
  case zone.action_type do
    "display" ->
      variable_ref = zone.action_data["variable_ref"]
      current_value = get_variable_value(state, variable_ref)
      Map.put(base, :display_value, current_value)

    _ ->
      base
  end
end

defp get_variable_value(state, variable_ref) when is_binary(variable_ref) do
  case Map.get(state.variables, variable_ref) do
    %{value: val} -> val
    nil -> nil
  end
end

defp get_variable_value(_state, _), do: nil

defp extract_background_url(%{background_asset: %{url: url}}), do: url
defp extract_background_url(_), do: nil
```

---

## Task 4 — Player UI Component

### 4a — Interaction slide component

**CREATE `lib/storyarn_web/live/flow_live/player/components/player_interaction.ex`:**

```elixir
defmodule StoryarnWeb.FlowLive.Player.Components.PlayerInteraction do
  use StoryarnWeb, :html

  import StoryarnWeb.Gettext

  attr :slide, :map, required: true
  attr :variables, :map, default: %{}

  def player_interaction(assigns) do
    zones = assigns.slide.zones || []

    # Separate zones by type for rendering
    instruction_zones = Enum.filter(zones, & &1.action_type == "instruction")
    display_zones = Enum.filter(zones, & &1.action_type == "display")
    event_zones = Enum.filter(zones, & &1.action_type == "event")
    navigate_zones = Enum.filter(zones, & &1.action_type == "navigate")

    assigns =
      assigns
      |> assign(:instruction_zones, instruction_zones)
      |> assign(:display_zones, display_zones)
      |> assign(:event_zones, event_zones)

    ~H"""
    <div class="interaction-player">
      <h3 class="text-lg font-bold mb-3">{@slide.label}</h3>

      <div
        id={"interaction-canvas-#{@slide.node_id}"}
        phx-hook="InteractionPlayer"
        data-background-url={@slide.background_url}
        data-map-width={@slide.map_width}
        data-map-height={@slide.map_height}
        data-zones={Jason.encode!(@slide.zones)}
        data-variables={Jason.encode!(serialize_display_variables(@variables, @display_zones))}
        class="relative w-full rounded-lg overflow-hidden bg-base-300"
        style={"aspect-ratio: #{@slide.map_width || 16} / #{@slide.map_height || 9}"}
      >
        <%!-- The hook renders zones as overlays on the background image --%>
      </div>
    </div>
    """
  end

  defp serialize_display_variables(variables, display_zones) do
    Enum.reduce(display_zones, %{}, fn zone, acc ->
      ref = zone.action_data["variable_ref"]
      case Map.get(variables, ref) do
        %{value: val} -> Map.put(acc, ref, val)
        _ -> acc
      end
    end)
  end
end
```

### 4b — Integrate into player_slide

**`lib/storyarn_web/live/flow_live/player/components/player_slide.ex`** — Add clause:

```heex
<%= case @slide.type do %>
  <% :dialogue -> %>
    <%!-- existing --%>
  <% :interaction -> %>
    <.player_interaction slide={@slide} variables={@variables} />
  <% :outcome -> %>
    <%!-- existing --%>
  <% _ -> %>
    <%!-- empty --%>
<% end %>
```

---

## Task 5 — JS Hook: Interaction Player

### 5a — Hook

**CREATE `assets/js/hooks/interaction_player.js`:**

```javascript
/**
 * InteractionPlayer hook
 *
 * Renders a map background with interactive zone overlays.
 * Zones are rendered as positioned div overlays on the image.
 *
 * Events pushed to server:
 * - "interaction_zone_click" with {zone_id, action_type, action_data}
 *
 * Events received from server:
 * - "interaction_variables_updated" with {variables: {...}}
 */
export default {
  mounted() {
    this.backgroundUrl = this.el.dataset.backgroundUrl;
    this.mapWidth = parseInt(this.el.dataset.mapWidth) || 800;
    this.mapHeight = parseInt(this.el.dataset.mapHeight) || 600;
    this.zones = JSON.parse(this.el.dataset.zones || "[]");
    this.variables = JSON.parse(this.el.dataset.variables || "{}");

    this.render();

    // Listen for variable updates (after instruction zone execution)
    this.handleEvent("interaction_variables_updated", ({ variables }) => {
      this.variables = variables;
      this.updateDisplayZones();
    });
  },

  render() {
    // Clear
    this.el.innerHTML = "";

    // Background image
    if (this.backgroundUrl) {
      const img = document.createElement("img");
      img.src = this.backgroundUrl;
      img.className = "absolute inset-0 w-full h-full object-contain";
      img.draggable = false;
      this.el.appendChild(img);
    }

    // Zone overlays
    this.zones.forEach((zone) => {
      const overlay = this.createZoneOverlay(zone);
      this.el.appendChild(overlay);
    });
  },

  createZoneOverlay(zone) {
    // Calculate bounding box from vertices (percentages)
    const xs = zone.vertices.map((v) => v.x);
    const ys = zone.vertices.map((v) => v.y);
    const minX = Math.min(...xs);
    const minY = Math.min(...ys);
    const maxX = Math.max(...xs);
    const maxY = Math.max(...ys);

    const div = document.createElement("div");
    div.className = `interaction-zone interaction-zone-${zone.action_type}`;
    div.style.position = "absolute";
    div.style.left = `${minX}%`;
    div.style.top = `${minY}%`;
    div.style.width = `${maxX - minX}%`;
    div.style.height = `${maxY - minY}%`;
    div.dataset.zoneId = zone.id;
    div.dataset.actionType = zone.action_type;

    // Visual styling
    if (zone.fill_color) {
      div.style.backgroundColor = zone.fill_color;
    }
    div.style.opacity = zone.opacity || 0.6;

    // Content based on action type
    switch (zone.action_type) {
      case "instruction":
        div.innerHTML = `<span class="zone-label">${zone.action_data?.label || zone.name}</span>`;
        div.style.cursor = "pointer";
        div.addEventListener("click", () => this.onInstructionClick(zone));
        break;

      case "display":
        const ref = zone.action_data?.variable_ref;
        const val = this.variables[ref] ?? "—";
        const label = zone.action_data?.label || "";
        div.innerHTML = `<span class="zone-display-label">${label}</span><span class="zone-display-value" data-ref="${ref}">${val}</span>`;
        break;

      case "event":
        div.innerHTML = `<span class="zone-label">${zone.action_data?.label || zone.action_data?.event_name}</span>`;
        div.style.cursor = "pointer";
        div.addEventListener("click", () => this.onEventClick(zone));
        break;

      case "navigate":
        // In player context, navigate zones could be clickable too
        // but for now, they're inert
        div.innerHTML = `<span class="zone-label">${zone.name}</span>`;
        break;
    }

    return div;
  },

  onInstructionClick(zone) {
    this.pushEvent("interaction_zone_instruction", {
      zone_id: zone.id,
      assignments: zone.action_data?.assignments || [],
    });
  },

  onEventClick(zone) {
    this.pushEvent("interaction_zone_event", {
      zone_id: zone.id,
      event_name: zone.action_data?.event_name,
    });
  },

  updateDisplayZones() {
    this.el.querySelectorAll(".zone-display-value").forEach((el) => {
      const ref = el.dataset.ref;
      el.textContent = this.variables[ref] ?? "—";
    });
  },

  destroyed() {
    // Cleanup
  },
};
```

### 5b — CSS for interaction zones

```css
.interaction-zone {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  border-radius: 4px;
  transition: all 0.15s ease;
  user-select: none;
}

.interaction-zone-instruction:hover,
.interaction-zone-event:hover {
  filter: brightness(1.2);
  transform: scale(1.02);
}

.zone-label {
  font-size: 12px;
  font-weight: 700;
  color: white;
  text-shadow: 0 1px 2px rgba(0, 0, 0, 0.8);
  pointer-events: none;
}

.zone-display-label {
  font-size: 10px;
  font-weight: 600;
  color: white;
  text-shadow: 0 1px 2px rgba(0, 0, 0, 0.8);
  pointer-events: none;
}

.zone-display-value {
  font-size: 18px;
  font-weight: 900;
  color: white;
  text-shadow: 0 1px 3px rgba(0, 0, 0, 0.9);
  pointer-events: none;
}
```

---

## Task 6 — Debug Handlers

### 6a — Instruction zone click

**`lib/storyarn_web/live/flow_live/handlers/debug_execution_handlers.ex`** — Add handlers:

```elixir
def handle_interaction_zone_instruction(params, socket) do
  assignments = params["assignments"] || []
  state = socket.assigns.debug_state

  case Engine.execute_interaction_instruction(state, assignments) do
    {:ok, new_state} ->
      # Push updated variables to the interaction player hook
      display_vars = extract_display_variables(new_state)

      socket
      |> assign(:debug_state, new_state)
      |> push_event("interaction_variables_updated", %{variables: display_vars})
      |> then(&{:noreply, &1})

    _ ->
      {:noreply, socket}
  end
end

defp extract_display_variables(state) do
  state.variables
  |> Enum.map(fn {ref, %{value: val}} -> {ref, val} end)
  |> Map.new()
end
```

### 6b — Event zone click

```elixir
def handle_interaction_zone_event(params, socket) do
  event_name = params["event_name"]
  state = socket.assigns.debug_state
  connections = socket.assigns.flow_connections  # or however connections are accessed

  case Engine.choose_interaction_event(state, event_name, connections) do
    {:ok, new_state} ->
      # Continue stepping (auto-advance to next interactive node)
      continue_stepping(socket, new_state)

    {:finished, new_state} ->
      socket
      |> assign(:debug_state, new_state)
      |> then(&{:noreply, &1})

    _ ->
      {:noreply, socket}
  end
end
```

### 6c — Wire events in show.ex

```elixir
def handle_event("interaction_zone_instruction", params, socket) do
  DebugHandlers.handle_interaction_zone_instruction(params, socket)
end

def handle_event("interaction_zone_event", params, socket) do
  DebugHandlers.handle_interaction_zone_event(params, socket)
end
```

---

## Task 7 — Constraint Enforcement

When an instruction zone executes `STR += 1`, the evaluator's `InstructionExec.execute/2` applies the operator. With Phase 1 complete, `clamp_to_constraints/2` automatically enforces min/max. No additional work needed here — it flows through the same code path as regular instruction nodes.

The console will log:
```
⚡ Character Creation — STR: 18 → 18 (clamped at max 18)
```

---

## Task 8 — Tests

### Evaluator tests

```elixir
describe "interaction evaluator" do
  test "evaluate sets waiting_input with pending choices" do
    node = %{id: 1, type: "interaction", data: %{"map_id" => 42, "label" => "Test"}}
    {:waiting_input, state} = InteractionEvaluator.evaluate(node, init_state(), [])
    assert state.status == :waiting_input
    assert state.pending_choices.type == :interaction
    assert state.pending_choices.map_id == 42
  end

  test "evaluate without map_id returns error" do
    node = %{id: 1, type: "interaction", data: %{"map_id" => nil}}
    {:error, _state, :no_map} = InteractionEvaluator.evaluate(node, init_state(), [])
  end

  test "execute_instruction updates variables" do
    state = init_state_with_variable("mc.str", 10, "number")
    state = %{state | pending_choices: %{node_id: 1, label: "Test"}}
    assignments = [%{"sheet" => "mc", "variable" => "str", "operator" => "add", "value" => "1", "value_type" => "literal"}]
    {:ok, new_state} = InteractionEvaluator.execute_instruction(state, assignments, 1, "Test")
    assert new_state.variables["mc.str"].value == 11
  end

  test "execute_instruction respects constraints" do
    state = init_state_with_constrained_variable("mc.str", 18, "number", %{"max" => 18})
    state = %{state | pending_choices: %{node_id: 1, label: "Test"}}
    assignments = [%{"sheet" => "mc", "variable" => "str", "operator" => "add", "value" => "1", "value_type" => "literal"}]
    {:ok, new_state} = InteractionEvaluator.execute_instruction(state, assignments, 1, "Test")
    assert new_state.variables["mc.str"].value == 18  # clamped
  end

  test "choose_event advances through connection" do
    state = %{
      init_state()
      | pending_choices: %{node_id: 1, label: "Test"},
        status: :waiting_input
    }
    connections = [%{source_node_id: 1, source_pin: "accept", target_node_id: 2}]
    {:ok, new_state} = InteractionEvaluator.choose_event(state, "accept", connections)
    assert new_state.current_node_id == 2
    assert new_state.pending_choices == nil
  end

  test "choose_event with no connection finishes" do
    state = %{
      init_state()
      | pending_choices: %{node_id: 1, label: "Test"},
        status: :waiting_input
    }
    {:finished, _state} = InteractionEvaluator.choose_event(state, "nonexistent", [])
  end
end
```

---

## Verification

```bash
mix test test/storyarn/flows/evaluator/
mix test test/storyarn/flows/
just quality
```

Manual:
1. Create a map with:
   - Background image (character creation screen)
   - Instruction zone "+1 STR" with assignments: `character.str += 1, character.points -= 1`
   - Instruction zone "-1 STR" with assignments: `character.str -= 1, character.points += 1`
   - Display zone bound to `character.str`, label "STR"
   - Display zone bound to `character.points`, label "Points"
   - Event zone "accept"
   - Event zone "cancel"

2. Create a flow:
   - Entry → Dialogue "Welcome to character creation" → Interaction (linked to map) → Dialogue "Your character is ready"
   - Connect "accept" output to the final dialogue
   - Connect "cancel" output to a different path

3. Run Story Player:
   - Advance past the welcome dialogue
   - Verify the map renders with clickable zones
   - Click "+1 STR" → STR display updates, Points decreases
   - Click "-1 STR" → STR decreases, Points increases
   - Verify constraints (if STR has max 18, clicking + at 18 does nothing)
   - Click "Accept" → flow continues to "Your character is ready"
   - Verify console shows all actions logged

4. Run again, click "Cancel" → verify different path taken
