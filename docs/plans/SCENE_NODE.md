# Plan: Scene Node — Location-Linked Screenplay Scenes

## Context

Storyarn's flow editor models narrative structure with dialogue, condition, instruction, hub, jump, subflow, entry, and exit nodes. What's missing is **scene context** — the screenplay concept of establishing *where* and *when* action takes place.

In screenwriting, every scene starts with a slug line:

```
INT. WHIRLING-IN-RAGS HOTEL - LOBBY - NIGHT
```

This tells the reader: interior, location, sub-location, time of day. In Storyarn, location data already exists as **sheets** (e.g., `loc.hotel`). A scene node bridges the flow graph with the sheet system by referencing a location sheet and adding screenplay metadata.

The scene node is a **pass-through** node (1 input, 1 output) that acts as a visual scene break in the flow. It does not branch or merge — it establishes context for the dialogue and action nodes that follow it.

---

## Design Decisions

**Sheet-linked (Option B):** The node references an existing location sheet via `location_sheet_id`. This allows:
- Reusing location data (name, color, avatar) from sheets
- Canvas node inherits the location sheet's color (like dialogue inherits speaker color)
- Location selector dropdown populated from project sheets
- Future: auto-set `has_visited` on the sheet when the scene is entered

**Pass-through topology:** Single input pin, single output pin. No responses, no branching. Like a "chapter marker" in the flow.

**Screenplay formatting:** Fields map to standard screenplay format:
- `int_ext` → INT. / EXT. / INT./EXT.
- Location name → from referenced sheet
- `sub_location` → specific area within the location
- `time_of_day` → DAY / NIGHT / MORNING / etc.
- `description` → action lines / transition notes

---

## Current State

No scene node exists. The closest patterns to follow:
- **Dialogue node** — references a sheet (`speaker_sheet_id`), inherits its color on canvas, uses `sheetsMap` for display
- **Exit node** — simple data model, pass-through (input only), `technical_id` generation
- **Subflow node** — recently added, good template for the full node creation workflow

**Key files as reference:**
| Pattern | File |
|---------|------|
| Sheet reference (speaker) | `nodes/dialogue/node.ex`, `dialogue.js` |
| Sheet color on canvas | `dialogue.js:nodeColor()`, `render_helpers.js:speakerHeader()` |
| Simple sidebar | `nodes/exit/config_sidebar.ex` |
| Technical ID gen | `nodes/dialogue/node.ex:handle_generate_technical_id` |
| Sheet selector UI | `nodes/dialogue/config_sidebar.ex` (speaker dropdown) |
| sheets_map lookup | `helpers/form_helpers.ex:sheets_map/1` |

---

## Scene Node Data Structure

**Stored in DB (data map):**
```elixir
%{
  "location_sheet_id" => nil,       # integer | nil — reference to a location sheet
  "int_ext" => "int",              # "int" | "ext" | "int_ext"
  "sub_location" => "",            # specific area: "Lobby", "Room 1", "Rooftop"
  "time_of_day" => "",             # "day" | "night" | "morning" | "evening" | "continuous" | ""
  "description" => "",             # action lines / transition notes (plain text)
  "technical_id" => ""             # auto-generated or manual
}
```

**Resolved at serialization (added for canvas, NOT stored):**
The scene node does NOT need custom resolution in `resolve_node_colors` because the canvas already receives `sheetsMap` as a data attribute. The JS node looks up the location sheet from `sheetsMap` at render time — same pattern as dialogue's speaker.

---

## Phase 1: Schema & Domain (Backend)

### 1.1 Add "scene" to node types

**File:** `lib/storyarn/flows/flow_node.ex`
- Add `"scene"` to `@node_types` list
- Add `:scene` to `@type node_type` union

### 1.2 No special CRUD logic needed

**File:** `lib/storyarn/flows/node_crud.ex`
- No changes needed. Scene nodes have no special creation constraints (unlike hub's unique `hub_id` or subflow's circular reference check).
- Standard `insert_node/2` handles it via the catch-all clause.

### 1.3 No serialization changes needed

**File:** `lib/storyarn/flows.ex`
- No changes to `resolve_node_colors/3`. The canvas resolves the location sheet name/color client-side via `sheetsMap`, same as dialogue resolves the speaker.

---

## Phase 2: LiveView (Node Module + Sidebar)

### 2.1 Create scene node module

**New file:** `lib/storyarn_web/live/flow_live/nodes/scene/node.ex`

```elixir
def type, do: "scene"
def icon_name, do: "clapperboard"
def label, do: gettext("Scene")

def default_data do
  %{
    "location_sheet_id" => nil,
    "int_ext" => "int",
    "sub_location" => "",
    "time_of_day" => "",
    "description" => "",
    "technical_id" => ""
  }
end

def extract_form_data(data) do
  %{
    "location_sheet_id" => data["location_sheet_id"] || "",
    "int_ext" => data["int_ext"] || "int",
    "sub_location" => data["sub_location"] || "",
    "time_of_day" => data["time_of_day"] || "",
    "description" => data["description"] || "",
    "technical_id" => data["technical_id"] || ""
  }
end

def on_select(_node, socket), do: socket
def on_double_click(_node), do: :sidebar
def duplicate_data_cleanup(data), do: Map.put(data, "technical_id", "")
```

**Technical ID generation handler:**
- Generate from: `{flow_shortcut}_{int_ext}_{location_name}_{count}`
- Example: `ch_prologue_int_hotel_1`
- Follows the same `normalize_for_id` pattern as dialogue

### 2.2 Create scene sidebar

**New file:** `lib/storyarn_web/live/flow_live/nodes/scene/config_sidebar.ex`

```
+----------------------------------+
|  LOCATION                        |
|  [Select location...        v]   |  <- dropdown from all_sheets
|                                  |
|  INT / EXT                       |
|  [INT v]                         |  <- select: int, ext, int_ext
|                                  |
|  SUB-LOCATION                    |
|  [Lobby___________________]      |  <- text input
|                                  |
|  TIME OF DAY                     |
|  [Night v]                       |  <- select: day, night, morning...
|                                  |
|  DESCRIPTION                     |
|  [Action lines / notes    ]      |  <- textarea
|  [________________________]      |
|                                  |
|  v Advanced                      |  <- collapsible panel section
|  TECHNICAL ID                    |
|  [ch_prologue_int_hotel_1] [R]   |  <- text + generate button
+----------------------------------+
```

**Location dropdown:** Built from `@all_sheets` (already available in assigns). Uses `phx-change="update_node_data"` like dialogue's speaker selector — no custom event needed.

**All fields** use the standard `phx-change="update_node_data"` with `phx-debounce="500"`. No type-specific events required beyond `generate_technical_id` (already handled in `show.ex`).

### 2.3 Register in NodeTypeRegistry

**File:** `lib/storyarn_web/live/flow_live/node_type_registry.ex`
- Add `"scene" => Nodes.Scene.Node` to `@node_modules`
- Add `"scene" => Nodes.Scene.ConfigSidebar` to `@sidebar_modules`

### 2.4 Add technical ID handler dispatch

**File:** `lib/storyarn_web/live/flow_live/show.ex`
- Add alias: `alias StoryarnWeb.FlowLive.Nodes.Scene`
- In `handle_event("generate_technical_id", ...)`, add clause:
  ```elixir
  node && node.type == "scene" ->
    Scene.Node.handle_generate_technical_id(socket)
  ```

No other changes needed in `show.ex` — all other events use generic handlers.

---

## Phase 3: JavaScript (Canvas Rendering)

### 3.1 Create scene node JS module

**New file:** `assets/js/flow_canvas/nodes/scene.js`

```javascript
config: {
  label: "Scene",
  color: "#06b6d4",       // cyan — distinct from dialogue (blue)
  icon: createIconSvg(Clapperboard),
  inputs: ["input"],
  outputs: ["output"],
  dynamicOutputs: false,
}
```

**Rendering:**

```
Scene node on canvas:

  +----------------------------+
  |  [avatar] Whirling-in-Rags |  <- speakerHeader with location sheet
  |  INT. LOBBY - NIGHT        |  <- slug line from int_ext + sub_location + time
  |  The detective enters...   |  <- description preview (truncated)
  |  o---------o               |  <- input/output sockets
  +----------------------------+
```

**Key render logic:**
- Use `speakerHeader()` from render_helpers.js if location sheet found in `sheetsMap` (same as dialogue uses it for speakers)
- Build slug line: `{INT_EXT}. {SUB_LOCATION} - {TIME_OF_DAY}` (uppercase)
- Show description as preview text (truncated)
- Node color inherits from location sheet color (like dialogue inherits speaker color)

### 3.2 Slug line formatting

```javascript
getPreviewText(data) {
  const parts = [];
  const intExt = (data.int_ext || "").toUpperCase().replace("_", "./");
  if (intExt) parts.push(intExt + ".");
  if (data.sub_location) parts.push(data.sub_location.toUpperCase());
  if (data.time_of_day) {
    if (parts.length > 0) parts.push("-");
    parts.push(data.time_of_day.toUpperCase());
  }
  return parts.join(" ");
}
```

Examples:
- `INT. LOBBY - NIGHT`
- `EXT. ROOFTOP - MORNING`
- `INT./EXT. COURTYARD - DAY`
- `INT.` (minimal — only int_ext set)

### 3.3 Indicators

```javascript
getIndicators(data) {
  const indicators = [];
  if (!data.location_sheet_id) {
    indicators.push({ type: "warning", title: "No location set" });
  }
  return indicators;
}
```

No location = warning (not error — scene can work without a sheet reference).

### 3.4 Node color from location sheet

```javascript
nodeColor(data, config, sheetsMap) {
  const locId = data.location_sheet_id;
  const locSheet = locId ? sheetsMap?.[String(locId)] : null;
  return locSheet?.color || config.color;
}
```

Same pattern as `dialogue.js:nodeColor()`.

### 3.5 needsRebuild

```javascript
needsRebuild(oldData, newData) {
  if (oldData?.location_sheet_id !== newData.location_sheet_id) return true;
  if (oldData?.int_ext !== newData.int_ext) return true;
  if (oldData?.sub_location !== newData.sub_location) return true;
  if (oldData?.time_of_day !== newData.time_of_day) return true;
  if (oldData?.description !== newData.description) return true;
  return false;
}
```

### 3.6 Register in JS index

**File:** `assets/js/flow_canvas/nodes/index.js`
- Import and add `scene` to `NODE_DEFS`

**File:** `assets/js/flow_canvas/event_bindings.js`
- No changes needed — scene has no custom events from Shadow DOM

---

## Phase 4: Seeds Update

### 4.1 Add scene nodes to RPG demo

**File:** `priv/repo/seeds.exs`

Add scene nodes to existing flows to demonstrate usage:

```elixir
# In Prologue flow — scene break before waking up
{:ok, scene_hotel} = Flows.create_node(prologue, %{
  type: "scene",
  position_x: 150.0, position_y: 300.0,
  data: %{
    "location_sheet_id" => hotel_sheet.id,
    "int_ext" => "int",
    "sub_location" => "Room",
    "time_of_day" => "morning",
    "description" => "A wrecked hotel room. Bottles and clothes everywhere.",
    "technical_id" => "PRO_SCENE_HOTEL"
  }
})

# In Chapter 1 — crime scene exterior
{:ok, scene_crime} = Flows.create_node(ch1, %{
  type: "scene",
  position_x: 150.0, position_y: 300.0,
  data: %{
    "location_sheet_id" => hotel_sheet.id,
    "int_ext" => "ext",
    "sub_location" => "Backyard",
    "time_of_day" => "morning",
    "description" => "Behind the hostel. A body hangs from an old oak tree.",
    "technical_id" => "CH1_SCENE_CRIME"
  }
})
```

Insert between entry node and first dialogue, rewire connections.

---

## Files Summary

| File | Change |
|------|--------|
| `lib/storyarn/flows/flow_node.ex` | Add `"scene"` to `@node_types` |
| `lib/storyarn_web/live/flow_live/nodes/scene/node.ex` | **NEW** — metadata, extract_form_data, technical ID generation |
| `lib/storyarn_web/live/flow_live/nodes/scene/config_sidebar.ex` | **NEW** — location selector, int/ext, sub_location, time, description, tech ID |
| `lib/storyarn_web/live/flow_live/node_type_registry.ex` | Register scene in `@node_modules` and `@sidebar_modules` |
| `lib/storyarn_web/live/flow_live/show.ex` | Add scene clause in `generate_technical_id` handler, add alias |
| `assets/js/flow_canvas/nodes/scene.js` | **NEW** — config, render, slug line, color from sheet, indicators |
| `assets/js/flow_canvas/nodes/index.js` | Import and register scene |
| `priv/repo/seeds.exs` | Add scene nodes to demo flows |

**No changes needed:**
- `flows.ex` — no server-side resolution (sheetsMap handles it client-side)
- `node_crud.ex` — no special creation/update logic
- `properties_panels.ex` — `all_sheets` already passed through
- `event_bindings.js` — no custom DOM events
- `generic_node_handlers.ex` — no new generic handlers

---

## Visual Summary

```
Canvas representation:

  +-------------------------------+
  |  [img] Whirling-in-Rags       |  <- location sheet avatar + name (cyan bg)
  |  INT. ROOM - MORNING          |  <- slug line
  |  A wrecked hotel room. Bot... |  <- description preview
  |  o-------------o              |  <- input → output
  +-------------------------------+

  +-------------------------------+
  |  [S] Scene                    |  <- no location selected (default cyan)
  |  ⚠ No location set           |  <- warning indicator
  |  EXT. - DAY                   |  <- partial slug line
  |  o-------------o              |
  +-------------------------------+

Sidebar:

  +----------------------------------+
  |  Location                        |
  |  [Whirling-in-Rags          v]   |
  |                                  |
  |  Int / Ext          Time of Day  |
  |  [INT  v]           [Morning v]  |
  |                                  |
  |  Sub-location                    |
  |  [Room________________________]  |
  |                                  |
  |  Description                     |
  |  [A wrecked hotel room.      ]   |
  |  [Bottles and clothes every..]   |
  |                                  |
  |  v Advanced                      |
  |  Technical ID                    |
  |  [PRO_SCENE_HOTEL_________] [R]  |
  +----------------------------------+
```

---

## Implementation Order

1. **Phase 1** — Add `"scene"` to `FlowNode.@node_types` (1 file, 2 lines)
2. **Phase 2** — Create `scene/node.ex` + `scene/config_sidebar.ex`, register in registry, add tech ID dispatch in show.ex (4 files, 2 new)
3. **Phase 3** — Create `scene.js`, register in `index.js` (2 files, 1 new)
4. **Phase 4** — Add scene nodes to seeds (1 file)

## Verification

1. **Add scene node** — verify it appears in "Add Node" dropdown with clapperboard icon
2. **Select location** — verify dropdown shows all project sheets, node color changes to sheet color
3. **Canvas rendering** — verify slug line formats correctly: `INT. LOBBY - NIGHT`
4. **No location** — verify warning indicator appears, default cyan color
5. **Technical ID** — verify auto-generation: `{flow}_{int_ext}_{location}_{count}`
6. **Duplicate node** — verify technical_id is cleared, other fields preserved
7. **Delete location sheet** — verify node still renders (shows default header, no crash)
8. **Seeds** — verify `mix run priv/repo/seeds.exs` works with scene nodes in flows
