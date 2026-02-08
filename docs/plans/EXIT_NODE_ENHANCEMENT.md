# Plan: Exit Node Enhancement — Outcome Tags, Flow References & Exit Modes

## Context

Exit nodes currently serve as terminal points in a flow. They have a label, a binary success/failure flag, and a technical ID — but no way to **connect to another flow**. This means flows are isolated; the only way to link them is through Subflow nodes (call-and-return pattern).

**Two problems to solve:**

### 1. Flow connectivity
For narrative designers, the most natural flow is **linear progression**: Scene A ends → Scene B begins. This doesn't need a "call and return" — it needs a simple **transition**. Think of it like screenplay scene changes: `CUT TO: INT. TAVERN - NIGHT`.

This enhancement adds an `exit_mode` to Exit nodes:
1. **Terminal** — end the story/branch (current behavior)
2. **Flow reference** — continue to another flow (linear progression, GOTO)
3. **Caller return** — return to the Subflow that invoked this flow (RETURN)

### 2. Outcome flexibility
The current `is_success: true/false` is too deterministic. Many games (The Witcher 3, Disco Elysium) have outcomes that aren't simply "success" or "failure" — they have a wide spectrum of grays: pyrrhic victories, sacrifices, bittersweet endings, moral compromises.

This enhancement **replaces `is_success`** with:
- **`outcome_tags`** — a list of free-form string tags (e.g., `["partial_success", "sacrifice", "loss"]`)
- **`outcome_color`** — a color picked from a preset palette for visual representation

Tags are **semantically meaningful** — game engines can consume them programmatically (`if exit.outcome_tags.includes("sacrifice")`). Tags autocomplete from previously used tags in the same project, giving consistency without requiring upfront configuration.

**No backward compatibility.** Existing exit nodes with `is_success` will lose that field. No migration path.

---

## Current Exit Node State

**Data structure (to be replaced):**
```elixir
%{
  "label" => "Victory",
  "technical_id" => "game_victory_1",
  "is_success" => true
}
```

**Behavior:**
- Single input pin, no output pins
- Color: green (success) or red (failure)
- Preview: `✓ Victory` or `✕ Defeat`
- Cannot delete last exit in a flow
- Technical ID auto-generated from flow shortcut + label

**Key files:**
| File | Purpose |
|------|---------|
| `lib/storyarn_web/live/flow_live/nodes/exit/node.ex` | Metadata, handlers, technical ID generation |
| `lib/storyarn_web/live/flow_live/nodes/exit/config_sidebar.ex` | Sidebar UI (label, success toggle, tech ID) |
| `assets/js/flow_canvas/nodes/exit.js` | Canvas rendering, color logic |
| `lib/storyarn/flows/node_crud.ex` | CRUD, deletion constraints, `list_exit_nodes_for_flow/1` |
| `lib/storyarn/flows.ex` | Serialization, facade delegates |

**All files referencing `is_success` (to be updated):**
| File | Usage |
|------|-------|
| `lib/storyarn_web/live/flow_live/nodes/exit/node.ex` | Default data, form extraction |
| `lib/storyarn_web/live/flow_live/nodes/exit/config_sidebar.ex` | Checkbox form field |
| `assets/js/flow_canvas/nodes/exit.js` | Icon/color rendering logic |
| `lib/storyarn/flows/node_crud.ex` | Ecto select fragment in queries |
| `lib/storyarn/flows/flow_crud.ex` | Default data on flow creation |
| `assets/js/flow_canvas/nodes/subflow.js` | Icon in exit labels list |
| `lib/storyarn_web/live/flow_live/nodes/subflow/config_sidebar.ex` | Badge color & icon |
| `test/storyarn/flows_test.exs` | Test assertions |

---

## Exit Node Data Structure (Final)

**Stored in DB (data map):**
```elixir
%{
  "label" => "Ciri survives, Vesemir dies",
  "technical_id" => "act3_ciri_survives",
  "outcome_tags" => ["partial_success", "sacrifice", "loss"],
  "outcome_color" => "amber",
  "exit_mode" => "terminal",
  "referenced_flow_id" => nil
}
```

**Outcome color palette** (preset, not free-form):
```
green | red | gray | amber | purple | blue | cyan | rose
```

**Resolved at serialization (added for canvas, NOT stored):**
```elixir
%{
  "label" => "Ciri survives, Vesemir dies",
  "technical_id" => "act3_ciri_survives",
  "outcome_tags" => ["partial_success", "sacrifice", "loss"],
  "outcome_color" => "amber",
  "exit_mode" => "flow_reference",
  "referenced_flow_id" => 42,
  "referenced_flow_name" => "Tavern Talk",       # resolved
  "referenced_flow_shortcut" => "tavern-talk",    # resolved
  "stale_reference" => false                      # resolved
}
```

---

## Phase 1: Schema & Domain (Backend)

### 1.1 Replace `is_success` with outcome tags + color in Exit data

**File:** `lib/storyarn_web/live/flow_live/nodes/exit/node.ex`
- Update `default_data/0`:
  ```elixir
  def default_data do
    %{
      "label" => "",
      "technical_id" => "",
      "outcome_tags" => [],
      "outcome_color" => "green",
      "exit_mode" => "terminal",
      "referenced_flow_id" => nil
    }
  end
  ```
- Update `extract_form_data/1`:
  - Remove `is_success` boolean parsing
  - Add `outcome_tags` — parse from comma-separated string or list
  - Add `outcome_color` — validate against preset palette
  - Add `exit_mode` — validate against `["terminal", "flow_reference", "caller_return"]`
  - Add `referenced_flow_id` — parse as integer or nil

### 1.2 Add project-wide tag autocomplete query

**File:** `lib/storyarn/flows/node_crud.ex`
- Add `list_outcome_tags_for_project/1`:
  ```elixir
  def list_outcome_tags_for_project(project_id) do
    from(n in FlowNode,
      join: f in assoc(n, :flow),
      where: f.project_id == ^project_id and n.type == "exit",
      select: fragment("jsonb_array_elements_text(?->'outcome_tags')", n.data)
    )
    |> Repo.all()
    |> Enum.uniq()
    |> Enum.sort()
  end
  ```
- Add facade delegate in `lib/storyarn/flows.ex`

### 1.3 Add exit flow reference validation

**File:** `lib/storyarn/flows/node_crud.ex`
- When updating an exit node with `exit_mode: "flow_reference"`:
  - Validate `referenced_flow_id` is not nil
  - Validate referenced flow exists and belongs to the same project
  - Validate no self-reference (referenced flow != current flow)
  - Validate no circular references using existing `has_circular_reference?/2`
- When `exit_mode` is `"terminal"` or `"caller_return"`, clear `referenced_flow_id` to nil

### 1.4 Extend serialization for exit flow references

**File:** `lib/storyarn/flows.ex` (in `resolve_node_colors/2`)
- Add `resolve_node_colors("exit", data)` clause:
  - If `exit_mode == "flow_reference"` and `referenced_flow_id` is set:
    - Load referenced flow name and shortcut (reuse `get_flow_brief/2` from flow_crud.ex)
    - Add `referenced_flow_name` and `referenced_flow_shortcut` to resolved data
    - If flow not found or deleted → set `stale_reference: true`
  - If `exit_mode` is `"terminal"` or `"caller_return"` → pass through unchanged

### 1.5 Update default exit node on flow creation

**File:** `lib/storyarn/flows/flow_crud.ex`
- Update the default exit node data to use `outcome_tags` and `outcome_color` instead of `is_success`
- Default exit: `outcome_tags: [], outcome_color: "green"`

### 1.6 Update exit node queries

**File:** `lib/storyarn/flows/node_crud.ex`
- Update `list_exit_nodes_for_flow/1` select to replace `is_success` with:
  ```elixir
  select: %{
    id: n.id,
    label: fragment("?->>'label'", n.data),
    outcome_tags: fragment("?->'outcome_tags'", n.data),
    outcome_color: fragment("coalesce(?->>'outcome_color', 'green')", n.data),
    exit_mode: fragment("coalesce(?->>'exit_mode', 'terminal')", n.data)
  }
  ```

### 1.7 Update tests

**File:** `test/storyarn/flows_test.exs`
- Replace `is_success` assertions with `outcome_tags` / `outcome_color` assertions

---

## Phase 2: LiveView (Sidebar UI)

### 2.1 Redesign Exit sidebar

**File:** `lib/storyarn_web/live/flow_live/nodes/exit/config_sidebar.ex`

Replace the `is_success` checkbox with outcome tags + color picker + exit mode:

```
┌─────────────────────────────────┐
│  LABEL                          │
│  [___Ciri survives__________]   │
│                                 │
│  OUTCOME TAGS                   │
│  [sacrifice] [loss] [+___]      │  ← tag input with autocomplete
│                                 │
│  COLOR                          │
│  ● ● ● ● ● ● ● ●              │  ← 8-color palette (green red gray amber purple blue cyan rose)
│                                 │
│  EXIT MODE                      │
│  ○ Terminal (end)               │
│  ○ Continue to flow →           │
│  ○ Return to caller ↩           │
│                                 │
│  [Flow selector dropdown]       │  ← only when "Continue to flow" selected
│                                 │
│  TECHNICAL ID                   │
│  [act3_ciri_survives___] [↻]    │
└─────────────────────────────────┘
```

**Outcome tags input:**
- Text input that adds tags on Enter or comma
- Each tag shown as a removable chip/badge
- Autocomplete dropdown with tags already used in the project (from `list_outcome_tags_for_project/1`)
- Tags are lowercase, trimmed, underscored (auto-normalized)

**Color palette:**
- 8 colored circles in a row
- Click to select, selected one has a ring/border
- Colors: `green`, `red`, `gray`, `amber`, `purple`, `blue`, `cyan`, `rose`

**Exit mode radio buttons:**
- Same as original plan
- Flow selector only visible when `exit_mode == "flow_reference"`

### 2.2 Update Exit node.ex with on_select for tag + flow loading

**File:** `lib/storyarn_web/live/flow_live/nodes/exit/node.ex`
- Update `on_select/2` to:
  - Always load project-wide outcome tags for autocomplete
  - Load available flows when `exit_mode == "flow_reference"`
  ```elixir
  def on_select(node, socket) do
    project_id = socket.assigns.project.id
    existing_tags = Flows.list_outcome_tags_for_project(project_id)
    socket = assign(socket, :outcome_tags_suggestions, existing_tags)

    case node.data["exit_mode"] do
      "flow_reference" ->
        current_flow_id = socket.assigns.flow.id
        available_flows = Flows.list_flows(project_id)
                          |> Enum.reject(&(&1.id == current_flow_id))
        assign(socket, :available_flows, available_flows)
      _ ->
        socket
    end
  end
  ```

### 2.3 Add event handlers

**File:** `lib/storyarn_web/live/flow_live/show.ex`

- `handle_event("update_exit_mode", %{"mode" => mode}, socket)`:
  - Update node data with new `exit_mode`
  - If changing TO `flow_reference` → load available flows
  - If changing FROM `flow_reference` → clear `referenced_flow_id`
  - Persist node update

- `handle_event("update_exit_reference", %{"flow-id" => flow_id}, socket)`:
  - Validate flow exists and belongs to project
  - Validate no circular reference
  - Update `referenced_flow_id` in node data
  - Persist node update

- `handle_event("add_outcome_tag", %{"tag" => tag}, socket)`:
  - Normalize tag (lowercase, trim, replace spaces with underscores)
  - Append to `outcome_tags` list (if not already present)
  - Persist node update

- `handle_event("remove_outcome_tag", %{"tag" => tag}, socket)`:
  - Remove tag from `outcome_tags` list
  - Persist node update

- `handle_event("update_outcome_color", %{"color" => color}, socket)`:
  - Validate against preset palette
  - Update `outcome_color` in node data
  - Persist node update

- `handle_event("navigate_to_exit_flow", %{"flow-id" => flow_id}, socket)`:
  - Validate flow belongs to project
  - Navigate with `push_navigate` including `?from=` breadcrumb param

### 2.4 Update PropertiesPanels

**File:** `lib/storyarn_web/live/flow_live/components/properties_panels.ex`
- Add `outcome_tags_suggestions` attr (default: `[]`)
- The `available_flows` attr already exists (added for Subflow)

---

## Phase 3: JavaScript (Canvas Rendering)

### 3.1 Update exit node color logic

**File:** `assets/js/flow_canvas/nodes/exit.js`

Replace `is_success`-based color with `outcome_color`-based:

```javascript
const colorMap = {
  green:  "#22c55e",
  red:    "#ef4444",
  gray:   "#6b7280",
  amber:  "#f59e0b",
  purple: "#8b5cf6",
  blue:   "#3b82f6",
  cyan:   "#06b6d4",
  rose:   "#f43f5e"
};

getColor(data) {
  return colorMap[data.outcome_color] || colorMap.green;
}
```

### 3.2 Update exit node rendering

**File:** `assets/js/flow_canvas/nodes/exit.js`

Update the `render()` function to show exit mode + outcome tags:

```
Terminal:           Victory ■              (with stop icon, colored by outcome_color)
Flow reference:     Victory → Tavern       (with nav link to referenced flow)
Caller return:      Victory ↩              (with return icon)

Tags shown as small text below label:
                    sacrifice, loss
```

**For flow_reference mode:**
- Use `renderNavLink()` (same helper used by subflow.js) to show `→ FlowName` as clickable link
- Dispatch `"navigate-to-exit-flow"` custom event on click

**For caller_return mode:**
- Show `↩` icon after the label

**For terminal mode:**
- Show `■` icon

**Tags rendering:**
- Show outcome tags as small comma-separated text below the label
- Truncate if too many tags (show first 2-3 + `+N more`)

### 3.3 Update exit node indicators

**File:** `assets/js/flow_canvas/nodes/exit.js`

```javascript
getIndicators(data) {
  const indicators = [];
  if (data.exit_mode === "flow_reference" && !data.referenced_flow_id) {
    indicators.push({ type: "error", title: "No flow referenced" });
  }
  if (data.stale_reference) {
    indicators.push({ type: "error", title: "Referenced flow was deleted" });
  }
  return indicators;
}
```

### 3.4 Update preview text

**File:** `assets/js/flow_canvas/nodes/exit.js`

```javascript
getPreviewText(data) {
  const label = data.label || "Exit";
  const modeIcon = data.exit_mode === "caller_return" ? " ↩"
                 : data.exit_mode === "flow_reference" ? ""
                 : " ■";
  return `${label}${modeIcon}`;
}
```

No more `✓`/`✕` icons — color alone conveys the tone.

### 3.5 Update needsRebuild

**File:** `assets/js/flow_canvas/nodes/exit.js`

```javascript
needsRebuild(oldData, newData) {
  if (oldData?.exit_mode !== newData.exit_mode) return true;
  if (oldData?.referenced_flow_id !== newData.referenced_flow_id) return true;
  if (oldData?.outcome_color !== newData.outcome_color) return true;
  if (JSON.stringify(oldData?.outcome_tags) !== JSON.stringify(newData.outcome_tags)) return true;
  return false;
}
```

### 3.6 Add navigation event binding

**File:** `assets/js/flow_canvas/event_bindings.js`
- Add listener for `"navigate-to-exit-flow"` custom event:
  ```javascript
  hook.el.addEventListener("navigate-to-exit-flow", (e) => {
    hook.pushEvent("navigate_to_exit_flow", { "flow-id": String(e.detail.flowId) });
  });
  ```

---

## Phase 4: Subflow Integration Update

### 4.1 Update Subflow output pin behavior with exit modes

The Subflow node reads Exit nodes from the referenced flow via `list_exit_nodes_for_flow/1`. Currently ALL exits generate output pins.

**New behavior:**
- Only exits with `exit_mode == "caller_return"` should generate output pins on the Subflow node
- Exits with `exit_mode == "flow_reference"` handle their own routing — they should NOT appear as Subflow outputs
- Exits with `exit_mode == "terminal"` are dead ends — show them as Subflow outputs with a `■` indicator so the designer sees all possible outcomes

### 4.2 Update list_exit_nodes_for_flow/1

Already covered in Phase 1.6 — the query now returns `outcome_tags`, `outcome_color`, and `exit_mode`.

### 4.3 Update Subflow JS output rendering

**File:** `assets/js/flow_canvas/nodes/subflow.js`
- In `createOutputs(data)`: Filter or include based on `exit_mode`
- In `formatOutputLabel(key, data)`: Replace `is_success` icon logic with:
  - `caller_return`: `↩ Victory` (using outcome_color for the pin color)
  - `terminal`: `■ Defeat` (using outcome_color for the pin color)
  - `flow_reference`: skip (these route themselves)

### 4.4 Update Subflow sidebar exit preview

**File:** `lib/storyarn_web/live/flow_live/nodes/subflow/config_sidebar.ex`
- Replace `is_success` badge with `exit_mode` + `outcome_color` badge:
  - `caller_return` → `↩ Return` badge with outcome_color
  - `terminal` → `■ Terminal` badge with outcome_color
  - `flow_reference` → `→ FlowName` badge with outcome_color
- Show outcome tags as small text under each exit entry

---

## Phase 5: Stale Reference Detection

### 5.1 Detect stale exit flow references at serialization

Already covered in Phase 1.4 — load referenced flow, flag if missing/deleted.

### 5.2 Circular reference detection for exit references

**File:** `lib/storyarn/flows/node_crud.ex`
- Reuse existing `has_circular_reference?/2` — it already walks the subflow graph
- Extend it to also consider exit flow references:
  - From a flow, collect both:
    - Subflow nodes → their `referenced_flow_id`
    - Exit nodes with `exit_mode == "flow_reference"` → their `referenced_flow_id`
  - Walk the graph considering both types of references
- This prevents: Flow A → (exit) → Flow B → (exit) → Flow A

### 5.3 Update has_circular_reference? to include exit references

**File:** `lib/storyarn/flows/node_crud.ex`

Current function only checks subflow nodes. Update to also check exit nodes:
```elixir
defp get_referenced_flow_ids(flow_id) do
  # Subflow references
  subflow_refs = from(n in FlowNode,
    where: n.flow_id == ^flow_id and n.type == "subflow",
    select: fragment("(?->>'referenced_flow_id')::integer", n.data)
  ) |> Repo.all()

  # Exit flow references
  exit_refs = from(n in FlowNode,
    where: n.flow_id == ^flow_id and n.type == "exit",
    where: fragment("?->>'exit_mode'", n.data) == "flow_reference",
    select: fragment("(?->>'referenced_flow_id')::integer", n.data)
  ) |> Repo.all()

  (subflow_refs ++ exit_refs) |> Enum.reject(&is_nil/1) |> Enum.uniq()
end
```

---

## Phase 6: Referencing Flows (Bidirectional Navigation)

When a flow is used by other flows (via Subflow nodes or Exit nodes with `flow_reference`), the exit nodes should show **who is calling this flow**. This enables bidirectional navigation: from a Subflow node you can dive into the referenced flow, and from an exit node you can jump back to the caller.

### 6.1 Extend `list_subflow_nodes_referencing` to include exit references

**File:** `lib/storyarn/flows/node_crud.ex`

The existing `list_subflow_nodes_referencing/2` only finds Subflow nodes. Create a new function that finds **all nodes** (Subflow + Exit with `flow_reference`) that reference the current flow, including the flow name for display:

```elixir
@doc """
Finds all nodes (subflow and exit with flow_reference) that reference a given flow.
Returns a list of maps with :node_id, :node_type, :flow_id, :flow_name, :flow_shortcut.
Used by exit nodes to show "Referenced by" section.
"""
def list_nodes_referencing_flow(flow_id, project_id) do
  flow_id_str = to_string(flow_id)

  from(n in FlowNode,
    join: f in Flow, on: n.flow_id == f.id,
    where: f.project_id == ^project_id,
    where:
      (n.type == "subflow" and fragment("?->>'referenced_flow_id' = ?", n.data, ^flow_id_str)) or
      (n.type == "exit" and fragment("?->>'exit_mode'", n.data) == "flow_reference" and
        fragment("?->>'referenced_flow_id' = ?", n.data, ^flow_id_str)),
    select: %{
      node_id: n.id,
      node_type: n.type,
      flow_id: f.id,
      flow_name: f.name,
      flow_shortcut: f.shortcut
    },
    order_by: [asc: f.name]
  )
  |> Repo.all()
end
```

Add facade delegate in `lib/storyarn/flows.ex`.

### 6.2 Load referencing flows on exit node select

**File:** `lib/storyarn_web/live/flow_live/nodes/exit/node.ex`

Update `on_select/2` to also load referencing flows:

```elixir
def on_select(node, socket) do
  project_id = socket.assigns.project.id
  flow_id = socket.assigns.flow.id

  # Load tag autocomplete suggestions
  existing_tags = Flows.list_outcome_tags_for_project(project_id)

  # Load flows that reference the current flow (via subflow or exit flow_reference)
  referencing_flows = Flows.list_nodes_referencing_flow(flow_id, project_id)

  socket =
    socket
    |> assign(:outcome_tags_suggestions, existing_tags)
    |> assign(:referencing_flows, referencing_flows)

  # Load available flows if exit_mode is flow_reference
  case node.data["exit_mode"] do
    "flow_reference" ->
      available_flows = Flows.list_flows(project_id)
                        |> Enum.reject(&(&1.id == flow_id))
      assign(socket, :available_flows, available_flows)
    _ ->
      socket
  end
end
```

### 6.3 Add "Referenced By" section to Exit sidebar

**File:** `lib/storyarn_web/live/flow_live/nodes/exit/config_sidebar.ex`

Add a section at the bottom of the sidebar (similar to Hub's "Referencing Jumps"):

```
┌─────────────────────────────────┐
│  ...existing fields...          │
│                                 │
│  REFERENCED BY (2)              │
│  ┌─ 🔀 Main Quest Flow         │  ← subflow node, click to navigate
│  └─ → Tavern Scene             │  ← exit flow_reference, click to navigate
│                                 │
│  No nodes reference this flow.  │  ← empty state
└─────────────────────────────────┘
```

Each entry shows:
- Icon: `🔀` for subflow references, `→` for exit flow_reference references
- Flow name (clickable, navigates to that flow)
- The navigation uses `push_navigate` with `?from=` breadcrumb

### 6.4 Add navigation event handler

**File:** `lib/storyarn_web/live/flow_live/show.ex`

Reuse the existing `navigate_to_subflow` pattern:

```elixir
def handle_event("navigate_to_referencing_flow", %{"flow-id" => flow_id_str}, socket) do
  case Integer.parse(flow_id_str) do
    {flow_id, ""} ->
      case Flows.get_flow_brief(socket.assigns.project.id, flow_id) do
        nil ->
          {:noreply, put_flash(socket, :error, gettext("Flow not found."))}
        _flow ->
          {:noreply,
           push_navigate(socket,
             to:
               ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/flows/#{flow_id}?from=#{socket.assigns.flow.id}"
           )}
      end
    _ ->
      {:noreply, put_flash(socket, :error, gettext("Invalid flow ID."))}
  end
end
```

### 6.5 Update PropertiesPanels and socket assigns

**File:** `lib/storyarn_web/live/flow_live/components/properties_panels.ex`
- Add `referencing_flows` attr (default: `[]`)

**File:** `lib/storyarn_web/live/flow_live/show.ex` (mount)
- Initialize `referencing_flows: []` in socket assigns

---

## Files to Modify

| File | Change |
|------|--------|
| `lib/storyarn_web/live/flow_live/nodes/exit/node.ex` | Replace `is_success` with `outcome_tags` + `outcome_color`, add `exit_mode` + `referenced_flow_id`, update on_select to load tags + referencing flows |
| `lib/storyarn_web/live/flow_live/nodes/exit/config_sidebar.ex` | Replace checkbox with tag input + color palette + exit mode radios + flow dropdown + "Referenced By" section |
| `assets/js/flow_canvas/nodes/exit.js` | Replace is_success color/icon logic with outcome_color, add tags rendering, exit mode icons, needsRebuild, indicators |
| `lib/storyarn/flows/node_crud.ex` | Replace is_success in queries, add list_outcome_tags_for_project, add list_nodes_referencing_flow, validate exit references, extend circular detection |
| `lib/storyarn/flows/flow_crud.ex` | Replace is_success in default exit data |
| `lib/storyarn/flows.ex` | Add resolve_node_colors("exit", data), add facade delegates for list_outcome_tags_for_project + list_nodes_referencing_flow |
| `lib/storyarn_web/live/flow_live/show.ex` | Add update_exit_mode, update_exit_reference, add/remove_outcome_tag, update_outcome_color, navigate_to_exit_flow, navigate_to_referencing_flow events; init referencing_flows assign |
| `lib/storyarn_web/live/flow_live/components/properties_panels.ex` | Add outcome_tags_suggestions + referencing_flows attrs |
| `assets/js/flow_canvas/event_bindings.js` | Add navigate-to-exit-flow event listener |
| `assets/js/flow_canvas/nodes/subflow.js` | Replace is_success icon logic with outcome_color, filter by exit_mode |
| `lib/storyarn_web/live/flow_live/nodes/subflow/config_sidebar.ex` | Replace is_success badge with outcome_color + exit_mode badges |
| `test/storyarn/flows_test.exs` | Replace is_success assertions |

## No New Files Needed

All changes are modifications to existing files.

---

## Visual Summary

```
Canvas representation:

  ┌──────────────────────┐
  │  EXIT  ■             │  Terminal (colored by outcome_color: amber)
  │  Ciri survives       │
  │  sacrifice, loss     │  ← outcome tags as small text
  └──────────────────────┘

  ┌──────────────────────┐
  │  EXIT  →             │  Flow reference (colored by outcome_color + nav link)
  │  Victory             │
  │  → Tavern Talk       │  ← clickable, navigates to flow
  └──────────────────────┘

  ┌──────────────────────┐
  │  EXIT  ↩             │  Caller return (colored by outcome_color + return icon)
  │  Quest Complete      │
  │  success             │  ← outcome tags
  └──────────────────────┘
```

```
Exit sidebar — "Referenced By" section:

  ┌─────────────────────────────────┐
  │  REFERENCED BY (2)              │
  │  ┌───────────────────────────┐  │
  │  │ 🔀 Main Quest Flow       │  │  ← subflow node referencing this flow
  │  │ →  Tavern Scene           │  │  ← exit node (flow_reference) pointing here
  │  └───────────────────────────┘  │
  │                                 │
  │  Click any to navigate →        │
  └─────────────────────────────────┘
```

## Implementation Order

1. **Phase 1** (Backend) — replace is_success, new data structure, validation, serialization
2. **Phase 2** (LiveView) — sidebar UI with tags + color + exit mode
3. **Phase 3** (JavaScript) — canvas rendering with new colors and tags
4. **Phase 4** (Subflow integration) — update output pin behavior
5. **Phase 5** (Stale detection) — circular references, stale flags
6. **Phase 6** (Referencing flows) — bidirectional navigation from exit nodes to callers

## Verification

1. **Create exit node** — verify default: `outcome_tags: [], outcome_color: "green", exit_mode: "terminal"`
2. **Add outcome tags** — type tag, press Enter, verify chip appears; type another, verify autocomplete suggests existing tags
3. **Change outcome color** — click amber circle, verify node turns amber on canvas
4. **Tag autocomplete** — create tag "sacrifice" on one exit, open another exit, verify "sacrifice" appears in suggestions
5. **Change to flow_reference** — verify flow dropdown appears, can select a flow
6. **Canvas rendering** — verify `→ FlowName` link appears on the exit node, colored by outcome_color
7. **Click nav link** — verify navigation to referenced flow with breadcrumb
8. **Change to caller_return** — verify `↩` icon appears, no flow dropdown
9. **Subflow integration** — verify only `caller_return` exits generate Subflow output pins
10. **Terminal in Subflow** — verify terminal exits show with `■` indicator on Subflow
11. **Circular detection** — verify A →(exit)→ B →(exit)→ A is prevented
12. **Delete referenced flow** — verify stale indicator on exit node
13. **Export check** — verify `outcome_tags` array is present in serialized node data for game engine consumption
14. **Referencing flows** — create Subflow in Flow A pointing to Flow B, open exit in Flow B, verify "Referenced By: Flow A" appears
15. **Exit flow_reference back-link** — create exit in Flow C with flow_reference to Flow B, open exit in Flow B, verify "Referenced By: Flow C" also appears
16. **Navigate to caller** — click a referencing flow entry, verify navigation with breadcrumb
