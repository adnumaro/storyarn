# Phase 7.5: Flows Enhancement

> **Goal:** Evolve Flows into a hierarchical tree structure with explicit entry/exit points and inter-flow navigation
>
> **Priority:** Alongside Phase 7.5 Pages Enhancement - both define the data model for export
>
> **Last Updated:** February 2, 2026

## Overview

This phase enhances the Flows system to mirror the Pages tree structure, adding:
- Hierarchical flow organization (tree like Pages)
- Explicit Entry and Exit nodes per flow
- Inter-flow navigation (FlowJump, FlowReturn)
- Intra-flow convergence (Hub, Jump)
- Event Trigger nodes for parallel world events
- Flow versioning and history
- Integration with Page block variables (`#shortcut.variable`)

**Design Philosophy:** The tree structure is for **organization only**, not execution order. Flow connections (including FlowJump nodes) define the actual narrative path.

---

## Architecture Changes

### Current Flow Model

```
flows
├── id, project_id, name
├── viewport_x, viewport_y, zoom
└── timestamps

flow_nodes
├── id, flow_id, type, position_x, position_y
├── data (JSONB)
└── timestamps

flow_connections
├── id, flow_id, source_node_id, target_node_id
├── source_handle, target_handle
└── timestamps
```

### New Flow Model

```
flows
├── id, project_id, name
├── parent_id            # NEW: FK to flows (nullable, for tree structure)
├── position             # NEW: Order among siblings
├── shortcut             # NEW: User-defined alias (from 7.5 Pages)
├── viewport_x, viewport_y, zoom
├── deleted_at           # NEW: Soft delete
└── timestamps

flow_nodes
├── id, flow_id, type, position_x, position_y
├── data (JSONB)
└── timestamps

flow_connections (unchanged)

flow_versions            # NEW TABLE
├── id, flow_id
├── version_number
├── snapshot (JSONB)     # {name, nodes: [...], connections: [...]}
├── changed_by_id (FK user)
├── change_summary
└── created_at
```

---

## New Node Types

### Overview of All Node Types

| Node       | Type Key      | Category     | Purpose                                  |
|------------|---------------|--------------|------------------------------------------|
| Entry      | `entry`       | Flow Control | Single entry point per flow (required)   |
| Exit       | `exit`        | Flow Control | Exit point(s) of the flow                |
| FlowJump   | `flow_jump`   | Inter-flow   | Navigate to another flow                 |
| FlowReturn | `flow_return` | Inter-flow   | Return to calling flow                   |
| Hub        | `hub`         | Intra-flow   | Convergence point for multiple paths     |
| Jump       | `jump`        | Intra-flow   | Jump to a Hub in same flow               |
| Event      | `event`       | World State  | Trigger parallel events without blocking |

### Existing Node Types (Reference)

| Node        | Type Key      | Purpose                              |
|-------------|---------------|--------------------------------------|
| Dialogue    | `dialogue`    | Single line of dialogue with speaker |
| Choice      | `choice`      | Player decision point with options   |
| Condition   | `condition`   | Branch based on variable state       |
| Instruction | `instruction` | Modify variable values               |
| Note        | `note`        | Designer annotations (not exported)  |

---

## Node Specifications

### 7.5.F.1 Entry Node

The single entry point of a flow. Every flow MUST have exactly one Entry node.

```
┌─────────────────────────────┐
│  🟢 Entry                   │
├─────────────────────────────┤
│  [No configuration]         │
├─────────────────────────────┤
│                        ○────│ (output only)
└─────────────────────────────┘
```

**Schema:**
```elixir
type: "entry"
data: %{}  # No additional data needed
```

**Rules:**
- [ ] Exactly ONE Entry node per flow (enforced)
- [ ] Cannot be deleted if it's the only Entry node
- [ ] No input handles, only output
- [ ] Auto-created when flow is created
- [ ] Visual: Green circle icon, distinct styling

**Implementation:**
- [ ] Add `entry` to node types enum
- [ ] Validation: ensure exactly 1 entry per flow
- [ ] Auto-create Entry node at position {100, 300} on flow creation
- [ ] Prevent deletion of last Entry node
- [ ] UI: Distinct green styling, "START" label

---

### 7.5.F.2 Exit Node

Exit point(s) of a flow. A flow can have multiple Exit nodes (different endings).

```
┌─────────────────────────────┐
│  🔴 Exit                    │
├─────────────────────────────┤
│  Label: [Victory]           │
├─────────────────────────────┤
│────○                        │ (input only)
└─────────────────────────────┘
```

**Schema:**
```elixir
type: "exit"
data: %{
  "label" => "default"  # Optional label for multiple exits
}
```

**Rules:**
- [ ] Multiple Exit nodes allowed per flow
- [ ] No output handles, only input
- [ ] Optional label to identify different endings
- [ ] Visual: Red circle/square icon

**Implementation:**
- [ ] Add `exit` to node types enum
- [ ] Schema validation for data.label (string, optional)
- [ ] UI: Distinct red styling, shows label if set
- [ ] Auto-create one Exit node on flow creation (optional, can be toggled)

---

### 7.5.F.3 FlowJump Node

Navigate to another flow in the project. This is the primary way to connect flows.

```
┌─────────────────────────────┐
│  ⤴️ FlowJump                │
├─────────────────────────────┤
│  Target: [Select flow ▼]    │
│  📁 Act 1 / Scene 2         │
│  #act1.scene2               │
├─────────────────────────────┤
│────○                   ○────│
└─────────────────────────────┘
```

**Schema:**
```elixir
type: "flow_jump"
data: %{
  "target_flow_id" => "uuid",      # Required: destination flow
  "target_flow_shortcut" => "...", # Cached for display
  "target_flow_name" => "...",     # Cached for display
  "target_flow_path" => "..."      # Cached: "Act 1 / Scene 2"
}
```

**Rules:**
- [ ] Target must be a flow in the same project
- [ ] Target cannot be the same flow (use Hub/Jump for that)
- [ ] Both input and output handles (can chain or continue after return)
- [ ] Visual indicator if target flow doesn't exist (deleted)
- [ ] Clicking the node can navigate to target flow

**Implementation:**
- [ ] Add `flow_jump` to node types enum
- [ ] Flow selector component (searchable, shows tree path)
- [ ] Search by: name, shortcut, path
- [ ] Cache target info for display (denormalized)
- [ ] Handle deleted targets gracefully
- [ ] Track in entity_references table (for backlinks)
- [ ] UI: Arrow icon, shows target path, click to navigate

---

### 7.5.F.4 FlowReturn Node

Return to the flow that jumped to this one. Enables "subroutine" patterns.

```
┌─────────────────────────────┐
│  ↩️ FlowReturn              │
├─────────────────────────────┤
│  Return to caller           │
├─────────────────────────────┤
│────○                        │ (input only)
└─────────────────────────────┘
```

**Schema:**
```elixir
type: "flow_return"
data: %{}  # No configuration needed
```

**Rules:**
- [ ] No output handles (execution returns to caller)
- [ ] If no caller (flow entered directly), acts as Exit
- [ ] Useful for reusable conversation flows

**Use Case Example:**
```
Main Quest Flow:
  ... → [FlowJump: Merchant Barter] → [Continue after purchase] → ...

Merchant Barter Flow (reusable):
  [Entry] → [Dialogue] → [Choice: Buy/Sell/Leave] → [FlowReturn]
```

**Implementation:**
- [ ] Add `flow_return` to node types enum
- [ ] Runtime: maintain call stack during simulation
- [ ] UI: Return arrow icon, distinct from Exit

---

### 7.5.F.5 Hub Node

Convergence point within a flow. Multiple paths can lead to the same Hub.

```
┌─────────────────────────────┐
│  🔷 Hub                     │
├─────────────────────────────┤
│  ID: [merchant_done]        │
│  Color: [Blue ▼]            │
├─────────────────────────────┤
│────○                   ○────│
└─────────────────────────────┘
```

**Schema:**
```elixir
type: "hub"
data: %{
  "hub_id" => "merchant_done",  # Required: unique within flow
  "color" => "blue"             # Optional: visual distinction
}
```

**Rules:**
- [ ] hub_id must be unique within the flow
- [ ] Multiple inputs allowed (convergence point)
- [ ] Single output (what happens after convergence)
- [ ] Can be targeted by Jump nodes

**Implementation:**
- [ ] Add `hub` to node types enum
- [ ] Validation: hub_id unique per flow
- [ ] Color picker (preset colors)
- [ ] UI: Diamond shape, shows hub_id label

---

### 7.5.F.6 Jump Node

Jump to a Hub within the same flow. Avoids duplicating connection paths.

```
┌─────────────────────────────┐
│  ⤵️ Jump                    │
├─────────────────────────────┤
│  Target Hub: [Select ▼]     │
│  → merchant_done            │
├─────────────────────────────┤
│────○                        │ (input only, teleports)
└─────────────────────────────┘
```

**Schema:**
```elixir
type: "jump"
data: %{
  "target_hub_id" => "merchant_done"  # Hub ID within same flow
}
```

**Rules:**
- [ ] Target must be a Hub in the same flow
- [ ] No output handle (execution teleports to Hub)
- [ ] Dropdown shows available Hubs in flow

**Implementation:**
- [ ] Add `jump` to node types enum
- [ ] Hub selector (only Hubs in current flow)
- [ ] Validation: target Hub must exist
- [ ] Visual connection line to target Hub (dashed/dotted)
- [ ] UI: Arrow icon pointing to Hub

---

### 7.5.F.7 Event Node

Trigger events that happen elsewhere in the game world without blocking the current flow. This addresses a gap in articy:draft.

```
┌─────────────────────────────┐
│  🎯 Event                   │
├─────────────────────────────┤
│  Event ID: [castle_burns]   │
│  Description: [The castle   │
│  catches fire in the        │
│  background]                 │
│                             │
│  ☑️ Fire immediately        │
│  ☐ Delay: [__] nodes        │
├─────────────────────────────┤
│────○                   ○────│
└─────────────────────────────┘
```

**Schema:**
```elixir
type: "event"
data: %{
  "event_id" => "castle_burns",     # Required: unique event identifier
  "description" => "...",            # What happens (for documentation)
  "delay_type" => "immediate",       # "immediate" | "delayed"
  "delay_nodes" => 0,                # If delayed, how many nodes later
  "tags" => ["world", "visual"]      # Optional categorization
}
```

**Rules:**
- [ ] event_id should be unique within project (recommendation, not enforced)
- [ ] Both input and output handles (flow continues immediately)
- [ ] Event is "fired" but doesn't block execution
- [ ] Game engine handles what the event actually does

**Use Cases:**
- "Meanwhile, the castle burns down" (while player is elsewhere)
- "Guard patrol starts" (background activity)
- "Music changes to tense" (ambient events)
- "Achievement unlocked" (meta events)

**Implementation:**
- [ ] Add `event` to node types enum
- [ ] Event ID input with autocomplete (existing events)
- [ ] Description textarea
- [ ] Delay configuration
- [ ] Tags for filtering/categorization
- [ ] Export: events are separate from dialogue flow
- [ ] UI: Target/flag icon, shows event_id

---

## Flow Tree Structure

### 7.5.F.8 Hierarchical Organization

Flows are organized in a tree structure identical to Pages.

```
🔀 Flows
├── 📁 Act 1
│   ├── 🔀 Intro                    shortcut: #act1.intro
│   ├── 🔀 Meet Jaime               shortcut: #act1.meet-jaime
│   └── 📁 Tavern Branch
│       ├── 🔀 Enter Tavern
│       └── 🔀 Bar Fight
├── 📁 Act 2
│   └── ...
└── 🔀 Shared
    ├── 🔀 Merchant Barter          shortcut: #shared.merchant
    └── 🔀 Game Over
```

**Implementation:**
- [ ] Add `parent_id` to flows table (FK to flows, nullable)
- [ ] Add `position` to flows table (integer, for ordering)
- [ ] Flows with `parent_id = NULL` are root level
- [ ] Reuse TreeComponents from Pages
- [ ] Drag-and-drop reordering
- [ ] Drag to reparent (move into folder)
- [ ] Context menu: New Flow, New Folder, Rename, Delete

### 7.5.F.9 Flow Folders

Folders are flows with no content (only for organization).

**Option A:** Flows with a `is_folder` boolean flag
**Option B:** Folders are just flows that happen to have no nodes (implicit)

**Recommendation:** Option A - explicit is clearer

```elixir
# Migration
alter table(:flows) do
  add :is_folder, :boolean, default: false
end
```

**Rules:**
- [ ] Folders cannot have nodes (editor disabled)
- [ ] Folders can have shortcuts (for namespacing: #act1)
- [ ] Folders can be converted to flows (add Entry node)
- [ ] Flows can be converted to folders (if empty)

---

## Flow Versioning

### 7.5.F.10 Version Snapshots

Same pattern as Page versioning from Phase 7.5.

```elixir
# Migration
create table(:flow_versions) do
  add :flow_id, references(:flows, on_delete: :delete_all), null: false
  add :version_number, :integer, null: false
  add :snapshot, :map, null: false  # {name, shortcut, nodes, connections}
  add :changed_by_id, references(:users, on_delete: :nilify_all)
  add :change_summary, :string

  timestamps(updated_at: false)
end

create index(:flow_versions, [:flow_id, :version_number])
```

**Snapshot Structure:**
```json
{
  "name": "Meet Jaime",
  "shortcut": "act1.meet-jaime",
  "nodes": [
    {"id": "...", "type": "entry", "position_x": 100, "position_y": 300, "data": {}},
    {"id": "...", "type": "dialogue", "position_x": 300, "position_y": 300, "data": {...}}
  ],
  "connections": [
    {"source_node_id": "...", "target_node_id": "...", "source_handle": "output", "target_handle": "input"}
  ]
}
```

**Implementation:**
- [ ] Create flow_versions table
- [ ] `Flows.create_version/2` function
- [ ] Auto-version on significant changes (node add/delete, connection changes)
- [ ] Debounce: max 1 version per 5 minutes
- [ ] Version history in flow sidebar or modal
- [ ] Restore version functionality

---

## Soft Delete

### 7.5.F.11 Flow Trash

```elixir
# Migration
alter table(:flows) do
  add :deleted_at, :utc_datetime
end

create index(:flows, [:deleted_at])
```

**Implementation:**
- [ ] Update queries to exclude deleted flows by default
- [ ] "Move to trash" instead of hard delete
- [ ] Trash view: list deleted flows with restore/permanent delete
- [ ] Auto-purge after 30 days
- [ ] Handle children when parent is deleted (move to root or delete cascade?)

---

## Integration with Page Variables

### 7.5.F.12 Variable References in Conditions/Instructions

Flows can read and modify Page block variables using the `#shortcut.variable` syntax from Phase 7.5.

**In Condition Nodes:**
```
#characters.jaime.is_alive == true
#characters.jaime.health > 50
#inventory.gold >= 100
#locations.tavern.visited == false
```

**In Instruction Nodes:**
```
#characters.jaime.health -= 10;
#inventory.gold += 50;
#locations.tavern.visited = true;
```

**Implementation:**
- [ ] Parser for `#shortcut.variable` syntax in condition/instruction scripts
- [ ] Autocomplete in script editors (fetch page shortcuts + variables)
- [ ] Validation: check referenced pages/variables exist
- [ ] Runtime resolution: resolve shortcut → page → block → value
- [ ] Track references in entity_references table

---

## UI/UX Specifications

### Flow Editor Layout (Updated)

```
┌──────────────────────────────────────────────────────────────────────────┐
│ PROJECT SIDEBAR          │ FLOW EDITOR                                   │
├──────────────────────────┼───────────────────────────────────────────────┤
│                          │ Meet Jaime                    [Versions] [⚙️] │
│ 📄 Pages                 │ #act1.meet-jaime                              │
│ ├── Characters           ├───────────────────────────────────────────────┤
│ └── Locations            │                                               │
│                          │  🟢 ───→ [Dialogue] ───→ [Choice] ───┐       │
│ 🔀 Flows ◀               │  Entry   "Hello!"      "Accept?"    │       │
│ ▼ 📁 Act 1               │                                      │       │
│   ├── Intro              │            ┌──────────────────────────┘       │
│   ├── Meet Jaime ◀────── │            │                                  │
│   └── 📁 Tavern          │            ▼                                  │
│       ├── Enter          │  [Condition] ─── true ──→ [FlowJump] → 🔴    │
│       └── Bar Fight      │  #jaime.likes_player      #act1.tavern Exit  │
│ ├── 📁 Act 2             │       │                                       │
│ └── 🔀 Shared            │       └── false ──→ [Dialogue] ──→ 🔴        │
│     └── Merchant         │                     "Maybe later"   Exit     │
│                          │                                               │
│                          ├───────────────────────────────────────────────┤
│                          │ NODE PALETTE        │ PROPERTIES              │
│                          │ [Entry] [Exit]      │ Type: Dialogue          │
│                          │ [FlowJump] [Return] │ Speaker: #mc.jaime      │
│                          │ [Hub] [Jump]        │ Text: "Hello!"          │
│                          │ [Event]             │                         │
│                          │ [Dialogue] [Choice] │ [Delete Node]           │
│                          │ [Condition] [Instr] │                         │
└──────────────────────────┴─────────────────────┴─────────────────────────┘
```

### Node Palette Organization

```
┌─────────────────────────────────────┐
│ FLOW CONTROL                        │
│ [🟢 Entry] [🔴 Exit]                │
│                                     │
│ NAVIGATION                          │
│ [⤴️ FlowJump] [↩️ Return]           │
│ [🔷 Hub] [⤵️ Jump]                  │
│                                     │
│ NARRATIVE                           │
│ [💬 Dialogue] [❓ Choice]           │
│                                     │
│ LOGIC                               │
│ [🔀 Condition] [📝 Instruction]     │
│                                     │
│ WORLD                               │
│ [🎯 Event]                          │
│                                     │
│ OTHER                               │
│ [📌 Note]                           │
└─────────────────────────────────────┘
```

### FlowJump Selector

```
┌─────────────────────────────────────┐
│ Select Target Flow                  │
├─────────────────────────────────────┤
│ 🔍 [Search flows...]                │
├─────────────────────────────────────┤
│ 📁 Act 1                            │
│   ├── 🔀 Intro         #act1.intro  │
│   ├── 🔀 Meet Jaime               │
│   └── 📁 Tavern                     │
│       ├── 🔀 Enter Tavern           │
│       └── 🔀 Bar Fight              │
│ 📁 Act 2                            │
│   └── ...                           │
│ 🔀 Shared                           │
│   └── 🔀 Merchant      #shared.merch│
└─────────────────────────────────────┘
```

---

## Database Migrations

### Migration 1: Flow Tree Structure

```elixir
alter table(:flows) do
  add :parent_id, references(:flows, on_delete: :nilify_all)
  add :position, :integer, default: 0
  add :is_folder, :boolean, default: false
end

create index(:flows, [:parent_id])
create index(:flows, [:project_id, :parent_id, :position])
```

### Migration 2: Flow Shortcuts (if not already in 7.5)

```elixir
alter table(:flows) do
  add :shortcut, :string
end

create unique_index(:flows, [:project_id, :shortcut],
  where: "shortcut IS NOT NULL AND deleted_at IS NULL",
  name: :flows_project_shortcut_unique)
```

### Migration 3: Flow Soft Delete

```elixir
alter table(:flows) do
  add :deleted_at, :utc_datetime
end

create index(:flows, [:deleted_at])
```

### Migration 4: Flow Versions

```elixir
create table(:flow_versions) do
  add :flow_id, references(:flows, on_delete: :delete_all), null: false
  add :version_number, :integer, null: false
  add :snapshot, :map, null: false
  add :changed_by_id, references(:users, on_delete: :nilify_all)
  add :change_summary, :string

  timestamps(updated_at: false)
end

create index(:flow_versions, [:flow_id, :version_number])
create index(:flow_versions, [:flow_id, :inserted_at])
```

### Migration 5: New Node Types

No migration needed - node types are stored in `flow_nodes.type` as strings.
Just update the application code to handle new types.

---

## Implementation Order

| Order   | Task                                      | Dependencies        | Testable Outcome        |
|---------|-------------------------------------------|---------------------|-------------------------|
| 1       | Flow tree structure (parent_id, position) | None                | Flows organized in tree |
| 2       | Flow folders (is_folder)                  | Tree structure      | Can create folders      |
| 3       | Tree UI (reuse from Pages)                | Tree structure      | Sidebar shows flow tree |
| 4       | Entry node                                | None                | Entry node works        |
| 5       | Exit node                                 | None                | Exit node works         |
| 6       | Hub node                                  | None                | Hub convergence works   |
| 7       | Jump node                                 | Hub node            | Jump to Hub works       |
| 8       | FlowJump node                             | Tree structure      | Can jump between flows  |
| 9       | FlowReturn node                           | FlowJump            | Return to caller works  |
| 10      | Event node                                | None                | Events can be fired     |
| 11      | Flow shortcuts                            | 7.5 Pages shortcuts | Flows have shortcuts    |
| 12      | Variable references in scripts            | 7.5 Block variables | #shortcut.var works     |
| 13      | Flow soft delete                          | None                | Trash/restore works     |
| 14      | Flow versions                             | None                | Version history works   |
| 15      | Backlinks for flows                       | entity_references   | "What jumps here?"      |

---

## Testing Strategy

### Unit Tests

- [ ] Flow tree operations (create, move, reparent)
- [ ] Entry node validation (exactly one per flow)
- [ ] Hub ID uniqueness within flow
- [ ] FlowJump target validation
- [ ] Variable reference parsing
- [ ] Version snapshot creation

### Integration Tests

- [ ] Create flow with auto Entry node
- [ ] Create folder and add flows inside
- [ ] FlowJump between flows
- [ ] Hub/Jump within same flow
- [ ] Event node creation and export
- [ ] Flow versioning and restore
- [ ] Soft delete and restore

### E2E Tests

- [ ] Build complete flow tree with folders
- [ ] Navigate between flows via FlowJump
- [ ] Use Page variables in Condition nodes
- [ ] Restore flow from version history

---

## Export Considerations

When exporting flows to JSON for game engines:

```json
{
  "flows": [
    {
      "id": "uuid",
      "shortcut": "act1.meet-jaime",
      "path": "Act 1/Meet Jaime",
      "entry_node_id": "uuid",
      "exit_nodes": ["uuid", "uuid"],
      "nodes": [...],
      "connections": [...]
    }
  ],
  "events": [
    {
      "id": "castle_burns",
      "triggered_in_flow": "act1.meet-jaime",
      "triggered_at_node": "uuid",
      "description": "The castle catches fire",
      "delay_type": "immediate"
    }
  ],
  "flow_graph": {
    "act1.intro": ["act1.meet-jaime"],
    "act1.meet-jaime": ["act1.tavern.enter", "act1.tavern.bar-fight"]
  }
}
```

---

## Open Questions

1. **Folder deletion:** When deleting a folder, should children be deleted or moved to parent?
   - Recommendation: Move to parent (safer)

2. **Circular FlowJumps:** Should we detect and warn about A → B → A cycles?
   - Recommendation: Warn but allow (could be intentional loops)

3. **Entry node position:** Auto-position or let user place it?
   - Recommendation: Auto-create at {100, 300}, user can move it

4. **Multiple Entry nodes:** Should we ever allow multiple entries (for different starting points)?
   - Recommendation: No, use FlowJump from a "router" flow instead

5. **Event node integration:** How do game engines consume events?
   - Recommendation: Export as separate event list, let engine decide

---

## Success Criteria

- [ ] Flows organized in tree structure (like Pages)
- [ ] Every flow has exactly one Entry node
- [ ] FlowJump navigates between flows correctly
- [ ] Hub/Jump works for intra-flow convergence
- [ ] Event nodes can be created and exported
- [ ] Flow shortcuts work with # syntax
- [ ] Page variables accessible in Condition/Instruction nodes
- [ ] Flow versioning with restore capability
- [ ] Soft delete with trash recovery

---

## Comparison: articy:draft vs Storyarn

| Feature                | articy:draft                 | Storyarn                    |
|------------------------|------------------------------|-----------------------------|
| Flow organization      | Nested containers (submerge) | Tree + FlowJump (lateral)   |
| Entry/Exit             | Multiple pins, implicit      | 1 Entry + N Exit, explicit  |
| Inter-flow navigation  | Pins connect inner/outer     | FlowJump node               |
| Intra-flow convergence | Hub + Jump                   | Hub + Jump (same)           |
| Parallel events        | Not supported                | Event node                  |
| Variables              | Global Variables             | Page block variables        |
| Learning curve         | Medium-high                  | Low (familiar tree pattern) |

**Key Advantage:** Storyarn's model is simpler to learn (one navigation paradigm) while being equally powerful for narrative design.

---

*This plan complements PHASE_7_5_PAGES_ENHANCEMENT.md. Both should be implemented together for a cohesive experience.*
