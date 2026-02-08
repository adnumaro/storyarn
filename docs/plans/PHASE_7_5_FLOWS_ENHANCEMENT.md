# Phase 7.5: Flows Enhancement

> **Goal:** Evolve Flows into a hierarchical tree structure with explicit entry/exit points and inter-flow navigation
>
> **Priority:** Alongside Phase 7.5 Pages Enhancement - both define the data model for export
>
> **Last Updated:** February 8, 2026

## Overview

This phase enhances the Flows system to mirror the Pages tree structure, adding:
- Hierarchical flow organization (tree like Pages)
- Explicit Entry and Exit nodes per flow
- Inter-flow navigation (Subflow node, Exit caller_return mode)
- Intra-flow convergence (Hub, Jump)
- Event Trigger nodes for parallel world events
- Flow versioning and history
- Integration with sheet variables (`#shortcut.variable`)

**Design Philosophy:** The tree structure is for **organization only**, not execution order. Flow connections (including Subflow nodes) define the actual narrative path.

---

## Unified Tree Model (Pages & Flows)

### Key Architectural Decision

**We use a unified model for both Pages and Flows:** Any node can have children AND content.

This was a deliberate decision to:
1. **Ensure consistency** between Pages and Flows
2. **Simplify the mental model** - no artificial folder/content distinction
3. **Enable future features** like templates and folder-level versioning
4. **Let the UI adapt** based on what the node contains

```
Page / Flow:
├── parent_id        → Tree structure (FK to self, nullable)
├── position         → Order among siblings (integer)
├── name, shortcut   → Identity
├── description      → Rich text for annotations (NEW)
├── content          → Blocks (Pages) / Nodes (Flows)
└── children         → has_many self
```

**UI Behavior:**
| Situation | UI Response |
|-----------|-------------|
| Has children, has content | Show tree + editor |
| Has children, no content | Show tree + "Add content" placeholder |
| No children, has content | Show editor |
| No children, no content | Show "Empty flow" state |

### Why No `is_folder` Flag?

We initially considered an explicit `is_folder` boolean but decided against it:

| Approach          | Pros                                     | Cons                                                               |
|-------------------|------------------------------------------|--------------------------------------------------------------------|
| `is_folder` flag  | Clear separation                         | Artificial dichotomy, validation overhead, conversion logic needed |
| **Unified model** | Consistent with Pages, simpler, flexible | UI must be smart about what to show                                |

**The unified model won** because:
- A flow that "acts as a folder" is just a flow with children and no nodes
- Users can add nodes later without "converting" from folder
- Templates (future) can apply to any node with children
- Folder-level versioning (future) works on any node with children

---

## Current Implementation Status

### Completed ✅

| Task                                 | Status  | Notes                                |
|--------------------------------------|---------|--------------------------------------|
| Tree structure (parent_id, position) | ✅ Done  | Migration `20260203185253`           |
| Soft delete (deleted_at)             | ✅ Done  | Cascade to children                  |
| Description field                    | ✅ Done  | Migration `20260204000652`           |
| TreeOperations module                | ✅ Done  | reorder_flows, move_flow_to_position |
| list_flows_tree/1                    | ✅ Done  | Recursive tree building              |
| Unified model (remove is_folder)     | ✅ Done  | Migration `20260204000652`           |
| Pages description field              | ✅ Done  | Consistency with Flows               |
| Tree UI (sidebar)                    | ✅ Done  | ProjectSidebar, SortableTree hook    |
| Entry node                           | ✅ Done  | Auto-created, cannot delete          |
| Exit node                            | ✅ Done  | Multiple allowed, can delete         |
| Hub node                             | ✅ Done  | hub_id unique per flow, color picker |
| Jump node                            | ✅ Done  | Targets hub_id in same flow          |
| Subflow node (was "FlowJump")        | ✅ Done  | Dynamic exit pins from referenced flow |
| Scene node                           | ✅ Done  | Screenplay slug line (INT/EXT, location, time) |
| Instruction node                     | ✅ Done  | Variable assignment builder          |
| Tree UI (sidebar)                    | ✅ Done  | SortableTree, drag-and-drop, context menu |
| Entry "Referenced By"                | ✅ Done  | Shows subflows and exit flow_references |

### Pending

| Task                | Priority  | Dependencies  |
|---------------------|-----------|---------------|
| Event node          | Low       | None          |
| Flow versions       | Medium    | None          |
| Variable references | Low       | Sheets 7.5    |

---

## Architecture

### Current Flow Model

```
flows
├── id, project_id, name
├── shortcut                 # User-defined alias
├── description              # Rich text for annotations (NEW)
├── parent_id                # FK to flows (nullable, tree structure)
├── position                 # Order among siblings
├── is_main                  # Main flow flag
├── settings                 # JSONB settings
├── deleted_at               # Soft delete
└── timestamps

flow_nodes
├── id, flow_id, type, position_x, position_y
├── data (JSONB)
└── timestamps

flow_connections
├── id, flow_id, source_node_id, target_node_id
├── source_pin, target_pin
├── label, condition
└── timestamps
```

### Future: Flow Versions

```
flow_versions (NOT YET IMPLEMENTED)
├── id, flow_id
├── version_number
├── snapshot (JSONB)     # {name, shortcut, description, nodes, connections}
├── changed_by_id (FK user)
├── change_summary
└── created_at
```

---

## New Node Types

### Overview of All Node Types

| Node        | Type Key      | Category     | Purpose                                  | Status   |
|-------------|---------------|--------------|------------------------------------------|----------|
| Entry       | `entry`       | Flow Control | Single entry point per flow (required)   | ✅ Done   |
| Exit        | `exit`        | Flow Control | Exit point(s), 3 modes: terminal, flow_reference, caller_return | ✅ Done |
| Subflow     | `subflow`     | Inter-flow   | Navigate to another flow (dynamic exit pins) | ✅ Done |
| Hub         | `hub`         | Intra-flow   | Convergence point for multiple paths     | ✅ Done   |
| Jump        | `jump`        | Intra-flow   | Jump to a Hub in same flow               | ✅ Done   |
| Scene       | `scene`       | Narrative    | Screenplay slug line (INT/EXT, location, time) | ✅ Done |
| Event       | `event`       | World State  | Trigger parallel events without blocking | Pending  |

### Existing Node Types (Reference)

| Node        | Type Key      | Purpose                                         |
|-------------|---------------|-------------------------------------------------|
| Dialogue    | `dialogue`    | Single line of dialogue with speaker + responses |
| Condition   | `condition`   | Branch based on variable state (dynamic outputs) |
| Instruction | `instruction` | Variable assignment via builder UI               |

> **Note:** There is no separate "Choice" node. Player choices are handled via dialogue responses.
> **Note:** "FlowReturn" was absorbed into exit node's `caller_return` mode.

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
- [x] Exactly ONE Entry node per flow (enforced)
- [x] Cannot be deleted if it's the only Entry node
- [x] No input handles, only output
- [x] Auto-created when flow is created
- [x] Visual: Green circle icon, distinct styling

**Implementation:**
- [x] Add `entry` to node types enum
- [x] Validation: ensure exactly 1 entry per flow
- [x] Auto-create Entry node at position {100, 300} on flow creation
- [x] Prevent deletion of last Entry node
- [x] UI: Distinct green styling, "Entry" label

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
- [x] Multiple Exit nodes allowed per flow
- [x] No output handles, only input
- [x] Optional label to identify different endings
- [x] Visual: Red square icon

**Implementation:**
- [x] Add `exit` to node types enum
- [x] Schema validation for data.label (string, optional)
- [x] UI: Distinct red styling, shows label if set
- [ ] Auto-create one Exit node on flow creation (optional, deferred)

---

### 7.5.F.3 Subflow Node (was "FlowJump") ✅ DONE

Navigate to another flow in the project. Implemented as `subflow` with dynamic exit pins.

```
┌─────────────────────────────┐
│  📦 Subflow                  │
├─────────────────────────────┤
│  Target: [Select flow ▼]    │
│  Act 1 / Scene 2            │
├─────────────────────────────┤
│────○              [exit1]○──│  (dynamic exit pins from
│                   [exit2]○──│   referenced flow's exits)
└─────────────────────────────┘
```

**Schema:**
```elixir
type: "subflow"
data: %{
  "referenced_flow_id" => integer  # Required: destination flow
}
```

**Rules:**
- [x] Target must be a flow in the same project
- [x] Target cannot be the same flow (self-reference prevented)
- [x] Input pin + dynamic output pins (one per exit node in referenced flow)
- [x] Double-click navigates to referenced flow
- [x] Entry node of referenced flow shows "Referenced By" backlinks

**Implementation:**
- [x] Add `subflow` to node type registry
- [x] Flow selector in sidebar (all project flows excluding self)
- [x] Load exit nodes from referenced flow for dynamic output pins
- [x] Double-click navigates to target flow
- [x] Entry node on_select loads referencing subflows and exit flow_references

---

### 7.5.F.4 FlowReturn — Absorbed into Exit Node ✅ DONE

Instead of a separate FlowReturn node, the Exit node has 3 modes:

| Exit Mode        | Behavior                                     |
|------------------|----------------------------------------------|
| `terminal`       | End of flow (default)                        |
| `flow_reference` | Navigate to another flow (like a Subflow at the end) |
| `caller_return`  | Return to the calling flow (subroutine pattern) |

This is simpler than a separate node type and keeps exit semantics in one place.

**Use Case Example:**
```
Main Quest Flow:
  ... → [Subflow: Merchant Barter] ─[exit1]─→ [Continue] → ...

Merchant Barter Flow (reusable):
  [Entry] → [Dialogue] → [Responses] → [Exit: caller_return]
```

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
- [x] hub_id must be unique within the flow
- [x] Multiple inputs allowed (convergence point)
- [x] Single output (what happens after convergence)
- [x] Can be targeted by Jump nodes

**Implementation:**
- [x] Add `hub` to node types enum (already existed)
- [x] Validation: hub_id unique per flow
- [x] Color picker (preset colors)
- [x] UI: Shows hub_id, color selection

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
- [x] Target must be a Hub in the same flow
- [x] No output handle (execution teleports to Hub)
- [x] Dropdown shows available Hubs in flow

**Implementation:**
- [x] Add `jump` to node types enum (already existed)
- [x] Hub selector (only Hubs in current flow)
- [x] Data structure: `target_hub_id`
- [ ] Visual connection line to target Hub (dashed/dotted) - deferred
- [x] UI: Arrow icon pointing to Hub

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

Flows are organized in a tree structure identical to Sheets. Any flow can have children AND content (nodes).

```
🔀 Flows
├── 🔀 Act 1                         # Has children AND can have nodes
│   ├── 🔀 Intro                     shortcut: #act1.intro
│   ├── 🔀 Meet Jaime                shortcut: #act1.meet-jaime
│   └── 🔀 Tavern Branch             # Parent flow with children
│       ├── 🔀 Enter Tavern
│       └── 🔀 Bar Fight
├── 🔀 Act 2
│   └── ...
└── 🔀 Shared
    ├── 🔀 Merchant Barter           shortcut: #shared.merchant
    └── 🔀 Game Over
```

**Key Point:** There are no "folder" flows. Any flow can:
- Have child flows (for organization)
- Have nodes (for content)
- Have both children AND nodes
- Have neither (empty placeholder)

**Implementation:** ✅ DONE
- [x] `parent_id` FK to flows (nullable)
- [x] `position` for ordering among siblings
- [x] `description` for annotations
- [x] Soft delete cascades to children
- [x] TreeOperations module (reorder, move)
- [x] Tree UI in sidebar (ProjectSidebar + SortableTree hook)
- [x] Drag-and-drop reordering
- [x] Context menu: New Flow, Rename, Delete

---

## Flow Versioning

### 7.5.F.9 Version Snapshots

Same pattern as Page versioning from Phase 7.5.

```elixir
# Migration (NOT YET IMPLEMENTED)
create table(:flow_versions) do
  add :flow_id, references(:flows, on_delete: :delete_all), null: false
  add :version_number, :integer, null: false
  add :snapshot, :map, null: false  # {name, shortcut, description, nodes, connections}
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
  "description": "First encounter with Jaime at the tavern",
  "nodes": [
    {"id": "...", "type": "entry", "position_x": 100, "position_y": 300, "data": {}},
    {"id": "...", "type": "dialogue", "position_x": 300, "position_y": 300, "data": {...}}
  ],
  "connections": [
    {"source_node_id": "...", "target_node_id": "...", "source_pin": "output", "target_pin": "input"}
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

### 7.5.F.10 Flow Trash ✅ DONE

```elixir
# Already implemented in migration 20260203185253
alter table(:flows) do
  add :deleted_at, :utc_datetime
end

create index(:flows, [:deleted_at])
```

**Implementation:** ✅ DONE
- [x] Queries exclude deleted flows by default
- [x] "Move to trash" instead of hard delete
- [x] Cascade soft delete to all children
- [x] `list_deleted_flows/1` for trash view
- [x] `restore_flow/1` to recover
- [x] `hard_delete_flow/1` for permanent deletion
- [ ] Trash UI view (pending)
- [ ] Auto-purge after 30 days (pending)

---

## Integration with Sheet Variables

### 7.5.F.11 Variable References in Conditions/Instructions

Flows can read and modify sheet variables using the `#shortcut.variable` syntax from Phase 7.5.

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
- [ ] Autocomplete in script editors (fetch sheet shortcuts + variables)
- [ ] Validation: check referenced sheets/variables exist
- [ ] Runtime resolution: resolve shortcut → sheet → block → value
- [ ] Track references in entity_references table

---

## UI/UX Specifications

### Flow Editor Layout

```
┌──────────────────────────────────────────────────────────────────────────┐
│ PROJECT SIDEBAR          │ FLOW EDITOR                                   │
├──────────────────────────┼───────────────────────────────────────────────┤
│                          │ Meet Jaime                    [Versions] [⚙️] │
│ 📄 Pages                 │ #act1.meet-jaime                              │
│ ├── Characters           │ First encounter with Jaime...                 │
│ └── Locations            ├───────────────────────────────────────────────┤
│                          │                                               │
│ 🔀 Flows ◀               │  🟢 ───→ [Dialogue] ───→ [Dialogue] ──┐      │
│ ▼ 🔀 Act 1               │  Entry   "Hello!"      (responses)  │      │
│   ├── Intro              │                                      │       │
│   ├── Meet Jaime ◀────── │            ┌──────────────────────────┘       │
│   └── 🔀 Tavern          │            │                                  │
│       ├── Enter          │            ▼                                  │
│       └── Bar Fight      │  [Condition] ─── true ──→ [Subflow] → 🔴     │
│ ├── 🔀 Act 2             │  #jaime.likes_player      #act1.tavern Exit  │
│ └── 🔀 Shared            │       │                                       │
│     └── Merchant         │       └── false ──→ [Dialogue] ──→ 🔴        │
│                          │                     "Maybe later"   Exit     │
│                          │                                               │
│                          ├───────────────────────────────────────────────┤
│                          │ NODE PALETTE        │ PROPERTIES              │
│                          │ [Entry] [Exit]      │ Type: Dialogue          │
│                          │ [Subflow] [Scene]   │ Speaker: #mc.jaime      │
│                          │ [Hub] [Jump]        │ Text: "Hello!"          │
│                          │ [Event]             │                         │
│                          │ [Dialogue] [Instr]  │ [Delete Node]           │
│                          │ [Condition]         │                         │
└──────────────────────────┴─────────────────────┴─────────────────────────┘
```

### Node Palette Organization

```
┌─────────────────────────────────────┐
│ FLOW CONTROL                        │
│ [Entry] [Exit]                      │
│                                     │
│ NAVIGATION                          │
│ [Subflow] [Hub] [Jump]              │
│                                     │
│ NARRATIVE                           │
│ [Dialogue] [Scene]                  │
│                                     │
│ LOGIC                               │
│ [Condition] [Instruction]           │
│                                     │
│ WORLD (pending)                     │
│ [Event]                             │
└─────────────────────────────────────┘
```

> **Note:** No separate "Choice" node — dialogue responses handle player choices.
> **Note:** No separate "FlowReturn" — exit node's `caller_return` mode handles it.

### Subflow Flow Selector

```
┌─────────────────────────────────────┐
│ Select Target Flow                  │
├─────────────────────────────────────┤
│ 🔍 [Search flows...]                │
├─────────────────────────────────────┤
│ 🔀 Act 1                            │
│   ├── 🔀 Intro         #act1.intro  │
│   ├── 🔀 Meet Jaime                 │
│   └── 🔀 Tavern                     │
│       ├── 🔀 Enter Tavern           │
│       └── 🔀 Bar Fight              │
│ 🔀 Act 2                            │
│   └── ...                           │
│ 🔀 Shared                           │
│   └── 🔀 Merchant      #shared.merch│
└─────────────────────────────────────┘
```

---

## Database Migrations

### Migration 1: Flow Tree Structure ✅ DONE

```elixir
# 20260203185253_add_tree_structure_to_flows.exs
alter table(:flows) do
  add :parent_id, references(:flows, on_delete: :nilify_all)
  add :position, :integer, default: 0
  add :deleted_at, :utc_datetime
end

create index(:flows, [:parent_id])
create index(:flows, [:project_id, :parent_id, :position])
create index(:flows, [:deleted_at])
```

### Migration 2: Unify Tree Model ✅ DONE

```elixir
# 20260204000652_unify_tree_model.exs
# Removes is_folder (unified model), adds description to pages
alter table(:pages) do
  add :description, :text
end
```

### Migration 3: Flow Versions (PENDING)

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

### Migration 4: New Node Types

No migration needed - node types are stored in `flow_nodes.type` as strings.
Just update the application code to handle new types.

---

## Implementation Order

| Order  | Task                                      | Status  | Dependencies        | Testable Outcome                   |
|--------|-------------------------------------------|---------|---------------------|------------------------------------|
| 1      | Flow tree structure (parent_id, position) | ✅ Done  | None                | Flows organized in tree            |
| 2      | Soft delete (deleted_at)                  | ✅ Done  | Tree structure      | Trash/restore works                |
| 3      | Unified model (remove is_folder)          | ✅ Done  | Tree structure      | Any flow can have children+content |
| 4      | Description field                         | ✅ Done  | None                | Flows and Pages have descriptions  |
| 5      | Tree UI (reuse from Pages)                | ✅ Done  | Tree structure      | Sidebar shows flow tree            |
| 6      | Entry node                                | ✅ Done  | None                | Entry node works                   |
| 7      | Exit node (3 modes)                       | ✅ Done  | None                | Exit node works (terminal, flow_reference, caller_return) |
| 8      | Hub node                                  | ✅ Done  | None                | Hub convergence works              |
| 9      | Jump node                                 | ✅ Done  | Hub node            | Jump to Hub works                  |
| 10     | Subflow node (was FlowJump)               | ✅ Done  | None                | Navigate between flows, dynamic exit pins |
| 11     | Scene node                                | ✅ Done  | None                | Screenplay slug line works         |
| 12     | Instruction node                          | ✅ Done  | None                | Variable assignment builder works  |
| 13     | Entry "Referenced By" backlinks           | ✅ Done  | Subflow node        | Entry shows referencing subflows   |
| 14     | Event node                                | Pending | None                | Events can be fired                |
| 15     | Variable references in scripts            | Pending | 7.5 Block variables | #shortcut.var works                |
| 16     | Flow versions                             | Pending | None                | Version history works              |

---

## Testing Strategy

### Unit Tests ✅ Partially Done

- [x] Flow tree operations (create, move, reparent)
- [x] Soft delete with cascade to children
- [x] Position auto-assignment
- [x] Tree listing (list_flows_tree, list_flows_by_parent)
- [x] Entry node validation (exactly one per flow, cannot delete)
- [x] Hub ID uniqueness within flow
- [ ] Subflow target validation
- [ ] Variable reference parsing
- [ ] Version snapshot creation

### Integration Tests

- [ ] Create flow with auto Entry node
- [ ] Create flow with children and nodes
- [x] Soft delete parent cascades to children
- [ ] Subflow between flows (dynamic exit pins)
- [ ] Hub/Jump within same flow
- [ ] Event node creation and export
- [ ] Flow versioning and restore

### E2E Tests

- [ ] Build complete flow tree
- [ ] Navigate between flows via Subflow node
- [ ] Use sheet variables in Condition nodes
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
      "description": "First encounter with Jaime at the tavern",
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

1. **Parent deletion:** When deleting a parent flow, should children be deleted or moved to grandparent?
   - **Decision:** Cascade soft delete to all children (implemented)

2. **Circular Subflows:** Should we detect and warn about A → B → A cycles?
   - Recommendation: Warn but allow (could be intentional loops)

3. **Entry node position:** Auto-position or let user place it?
   - Recommendation: Auto-create at {100, 300}, user can move it

4. **Multiple Entry nodes:** Should we ever allow multiple entries (for different starting points)?
   - Recommendation: No, use a Subflow from a "router" flow instead

5. **Event node integration:** How do game engines consume events?
   - Recommendation: Export as separate event list, let engine decide

---

## Success Criteria

- [x] Flows organized in tree structure (like Pages)
- [x] Any flow can have children AND content (unified model)
- [x] Soft delete with trash recovery
- [x] Every flow has exactly one Entry node
- [x] Subflow navigates between flows correctly (with dynamic exit pins)
- [x] Hub/Jump works for intra-flow convergence
- [x] Entry node shows "Referenced By" backlinks
- [x] Scene node for screenplay slug lines
- [x] Exit node supports 3 modes (terminal, flow_reference, caller_return)
- [ ] Event nodes can be created and exported
- [ ] Sheet variables accessible in Condition/Instruction nodes
- [ ] Flow versioning with restore capability

---

## Comparison: articy:draft vs Storyarn

| Feature                | articy:draft                 | Storyarn                                  |
|------------------------|------------------------------|-------------------------------------------|
| Flow organization      | Nested containers (submerge) | Unified tree (any node can have children) |
| Entry/Exit             | Multiple pins, implicit      | 1 Entry + N Exit, explicit                |
| Inter-flow navigation  | Pins connect inner/outer     | Subflow node (dynamic exit pins)          |
| Intra-flow convergence | Hub + Jump                   | Hub + Jump (same)                         |
| Parallel events        | Not supported                | Event node                                |
| Variables              | Global Variables             | Sheet block variables                     |
| Learning curve         | Medium-high                  | Low (familiar tree pattern)               |

**Key Advantage:** Storyarn's unified model is simpler to learn (one navigation paradigm, no folder/content distinction) while being equally powerful for narrative design.

---

## Future Considerations

### Templates (Post-MVP)
- Any flow with children can define a "template"
- Child flows can inherit structure from parent template
- Similar to Page templates feature

### Folder-Level Versioning (Post-MVP)
- Snapshot entire subtree, not just single flow
- Enables branching/merging narratives
- Complex feature requiring careful design

---

*This plan complements PHASE_7_5_PAGES_ENHANCEMENT.md. Both should be implemented together for a cohesive experience.*
