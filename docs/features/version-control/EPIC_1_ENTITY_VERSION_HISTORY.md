# Epic 1 — Entity Version History

> Per-entity snapshots, restore, and named versions for Sheets, Flows, and Scenes

## Context

Storyarn currently has versioning only for Sheets: full JSON snapshots with restore, rate-limited auto-creation, and a UI with paginated listing. Flows and Scenes have zero versioning. This epic generalizes the system into shared infrastructure and extends it to all three entity types.

Each feature is independent and ordered by dependency.

---

## Feature 1: Generalize Versioning System

### What
Refactor the existing sheet-only versioning into a **shared versioning engine** that works for any entity type (Sheet, Flow, Scene). Then extend it to Flows and Scenes.

### Why (standalone value)
Without this, we'd duplicate the versioning code three times. A shared system means one codebase to maintain, consistent behavior across all editors, and faster implementation of future versioning features.

### Current state
- `Storyarn.Sheets.Versioning` — full implementation for sheets only
- `SheetVersion` schema — sheet-specific with `sheet_id` foreign key
- Snapshot format hardcoded for sheet structure (name, shortcut, blocks)
- UI in `versions_section.ex` — sheet-specific LiveComponent

### Target architecture

**Shared versioning engine** (`Storyarn.Shared.Versioning`):
- Generic snapshot creation, listing, restore, deletion
- Entity-type-agnostic metadata storage
- Pluggable snapshot builders per entity type

**New schema: `EntityVersion`** (replaces `SheetVersion`):
```
entity_versions
├── id (id)
├── entity_type (string: "sheet" | "flow" | "scene")
├── entity_id (id)
├── project_id (id, FK)
├── version_number (integer, auto-increment per entity)
├── title (string, nullable — nil for auto-snapshots)
├── description (text, nullable)
├── change_summary (string, auto-generated)
├── storage_key (string — R2 path to snapshot JSON)
├── snapshot_size_bytes (integer — for quota tracking)
├── is_auto (boolean — true for auto-snapshots, false for named)
├── created_by_id (id, FK to users)
├── inserted_at (utc_datetime)
```

No `snapshot` map column — the JSON lives in R2, referenced by `storage_key`.

**Snapshot builder behaviour:**
```elixir
@callback build_snapshot(entity :: struct()) :: map()
@callback restore_snapshot(entity :: struct(), snapshot :: map()) :: {:ok, struct()} | {:error, term()}
@callback generate_change_summary(old_snapshot :: map() | nil, new_snapshot :: map()) :: String.t()
```

Implementations: `SheetSnapshotBuilder`, `FlowSnapshotBuilder`, `SceneSnapshotBuilder`.

### Key implementation areas
- **Migrate SheetVersion → EntityVersion**: migration to rename/restructure table, move existing snapshot data to R2
- **Extract shared engine**: generic CRUD for versions, pagination, rate-limiting
- **Sheet builder**: extract from current `Versioning` module
- **Flow builder**: new — captures nodes, connections, all node data
- **Scene builder**: new — captures layers, zones, pins, connections, annotations
- **UI component**: generalize `versions_section.ex` to accept any entity type
- **Facade integration**: add version functions to `Flows` and `Scenes` contexts

### Flow snapshot structure
```json
{
  "name": "Quest Principal",
  "shortcut": "quest.main",
  "description": "...",
  "position": 0,
  "parent_id": "id-or-null",
  "scene_backdrop_id": "id-or-null",
  "nodes": [
    {
      "id": "id",
      "type": "dialogue",
      "position_x": 150.0,
      "position_y": 200.0,
      "width": null,
      "data": {
        "speaker_sheet_id": "id",
        "text": "<p>Hello</p>",
        "stage_directions": "",
        "menu_text": "",
        "audio_asset_id": "id-or-null",
        "audio_blob_hash": "sha256-or-null",
        "technical_id": "dlg_001",
        "localization_id": "",
        "responses": [...]
      }
    }
  ],
  "connections": [
    {
      "id": "id",
      "source_node_id": "id",
      "source_output": "main",
      "target_node_id": "id",
      "target_input": "input"
    }
  ],
  "external_refs": {
    "sheet_ids": ["id1", "id2"],
    "flow_ids": ["id3"],
    "asset_ids": ["id4"],
    "asset_blob_hashes": {"id4": "sha256hash"}
  }
}
```

### Scene snapshot structure
```json
{
  "name": "Tavern",
  "shortcut": "tavern",
  "description": "...",
  "position": 0,
  "parent_id": "id-or-null",
  "width": 1000,
  "height": 1000,
  "scale_value": 500.0,
  "scale_unit": "km",
  "default_zoom": 1.0,
  "default_center_x": 50.0,
  "default_center_y": 50.0,
  "background_asset_id": "id-or-null",
  "background_blob_hash": "sha256-or-null",
  "layers": [
    {
      "id": "id",
      "name": "Default Layer",
      "position": 0,
      "visible": true,
      "locked": false,
      "opacity": 1.0
    }
  ],
  "zones": [
    {
      "id": "id",
      "layer_id": "id",
      "name": "Market Square",
      "vertices": [{"x": 10, "y": 10}, {"x": 90, "y": 10}, {"x": 90, "y": 90}],
      "fill_color": "#ff0000",
      "border_color": "#000000",
      "border_style": "solid",
      "border_width": 2,
      "opacity": 0.3,
      "tooltip": "A bustling market",
      "action_type": "none",
      "action_data": {},
      "target_type": null,
      "target_id": null,
      "condition": null,
      "condition_effect": "hide",
      "position": 0
    }
  ],
  "pins": [
    {
      "id": "id",
      "layer_id": "id",
      "label": "Jaime",
      "pin_type": "character",
      "position_x": 50.0,
      "position_y": 50.0,
      "color": "#8b5cf6",
      "size": "md",
      "opacity": 1.0,
      "icon": "user",
      "sheet_id": "id-or-null",
      "icon_asset_id": "id-or-null",
      "icon_blob_hash": "sha256-or-null",
      "action_type": "none",
      "action_data": {},
      "target_type": null,
      "target_id": null,
      "condition": null,
      "condition_effect": "hide",
      "position": 0
    }
  ],
  "connections": [
    {
      "id": "id",
      "from_pin_id": "id",
      "to_pin_id": "id",
      "waypoints": [{"x": 30, "y": 40}],
      "line_style": "solid",
      "line_width": 2,
      "color": "#000000",
      "bidirectional": false,
      "label": null,
      "show_label": false
    }
  ],
  "annotations": [
    {
      "id": "id",
      "layer_id": "id",
      "text": "North Gate",
      "position_x": 20.0,
      "position_y": 10.0,
      "font_size": "md",
      "color": "#000000",
      "background_color": null,
      "opacity": 1.0,
      "rotation": 0,
      "position": 0
    }
  ],
  "external_refs": {
    "sheet_ids": ["id1"],
    "flow_ids": ["id2"],
    "scene_ids": ["id3"],
    "asset_ids": ["id4", "id5"],
    "asset_blob_hashes": {"id4": "sha256a", "id5": "sha256b"}
  }
}
```

### Acceptance criteria
- [ ] `EntityVersion` schema replaces `SheetVersion`
- [ ] Existing sheet versions migrated to new schema + R2 storage
- [ ] Shared versioning engine with pluggable snapshot builders
- [ ] Flow snapshot builder captures all nodes, connections, and data
- [ ] Scene snapshot builder captures all layers, zones, pins, connections, annotations
- [ ] Version listing, creation, and deletion work for all three entity types
- [ ] Generalized UI component works in sheet, flow, and scene editors
- [ ] `external_refs` metadata captured in every snapshot

---

## Feature 2: Auto-Snapshots by Significant Action

### What
Automatically create snapshots when the user performs significant changes, with a rate-limit to prevent snapshot flood. No manual action required — the safety net is always on.

### Why (standalone value)
Users forget to save versions. Auto-snapshots mean they never lose more than 10-15 minutes of work, even if they never manually create a version.

### Significant actions (triggers)

**Sheets:**
- Block created, deleted, or reordered
- Block type changed
- Sheet name or shortcut changed
- Block value changed (rate-limited — text edits are frequent)

**Flows:**
- Node created, deleted, or duplicated
- Connection created or deleted
- Node type changed
- Node data significantly changed (speaker, conditions, responses added/removed)
- Flow name or shortcut changed

**Scenes:**
- Zone created, deleted, or vertices changed
- Pin created, deleted, or moved significantly
- Connection created or deleted
- Layer created, deleted, or reordered
- Annotation created or deleted
- Scene settings changed (background, dimensions, scale)

### Rate limiting
- Minimum **10 minutes** between auto-snapshots per entity
- A significant action within the cooldown window is **deferred**: when the timer expires, if there were deferred actions, a snapshot is created
- This ensures we capture the state after a burst of changes, not during

### Implementation approach
- Hook into existing `handle_event` handlers — after successful mutation, call `Versioning.maybe_create_auto_snapshot(entity, user)`
- The `maybe_create_auto_snapshot` function checks the rate limit and either creates immediately or schedules a deferred snapshot
- Deferred snapshots via `Process.send_after` on the LiveView process — if the user is still connected when the timer fires, snapshot is created
- If the user disconnects before the deferred timer, the snapshot is lost (acceptable — the next session will snapshot on first change)

### Acceptance criteria
- [ ] Auto-snapshots trigger on significant actions for sheets, flows, and scenes
- [ ] Rate limit of 10-15 minutes enforced per entity
- [ ] Deferred snapshots capture state after burst of changes
- [ ] Auto-snapshots marked with `is_auto: true` in metadata
- [ ] Auto-snapshots have auto-generated change summaries (no title)
- [ ] Auto-snapshots respect retention policy (cleaned by Oban job)
- [ ] No user action required — completely transparent

---

## Feature 3: Named Versions with Intent

### What
User-created milestones with a title, description, and auto-generated change summary. Named versions are preserved indefinitely (not subject to auto-cleanup) and surfaced prominently in the version history.

### Why (standalone value)
Auto-snapshots are a safety net, but named versions tell the **story** of the design process. "Before rewriting Act 2", "Final dialogue pass", "Client feedback round 1" — these are the versions users actually want to find later.

### UX flow
1. User clicks "Save Version" in the editor toolbar or version panel
2. Modal appears with:
   - **Title** (required, max 100 chars): "Before rewriting Act 2"
   - **Description** (optional, max 500 chars): "The current dialogue flow works but the pacing is off in the middle section"
3. On save:
   - Snapshot is created immediately (bypasses rate limit)
   - Change summary auto-generated by comparing to previous version
   - Marked as `is_auto: false`

### Version history UI
- Named versions shown prominently (full row with title, description, author, date)
- Auto-snapshots collapsed between named versions (expandable: "12 auto-saves between v5 and v6")
- Current state indicator: "You are here" marker at the top
- Each version shows: version badge, title/summary, author avatar, relative date
- Actions per version: Restore, Delete, Rename (for named versions)

### Acceptance criteria
- [ ] "Save Version" button in editor toolbar
- [ ] Modal with title and description fields
- [ ] Change summary auto-generated (nodes added/modified/deleted, connections changed, etc.)
- [ ] Named versions bypass rate limit (always created immediately)
- [ ] Named versions marked `is_auto: false`, never auto-deleted
- [ ] Version history UI shows named versions prominently
- [ ] Auto-snapshots collapsed between named versions
- [ ] Quota enforcement: warn when approaching limit, block when exceeded

---

## Feature 4: Restore with Conflict Detection

### What
When restoring a version, scan all external references in the snapshot against the current project state. Show a conflict report before applying the restore, letting the user make an informed decision.

### Why (standalone value)
Blind restore is dangerous. A flow referencing a deleted sheet, a scene pointing to a removed flow — silent broken references corrupt the project. Conflict detection makes restore **safe and transparent**.

### Conflict types

| Conflict               | Example                                                                  | Resolution                                            |
|------------------------|--------------------------------------------------------------------------|-------------------------------------------------------|
| **Missing entity**     | Dialogue node references `speaker_sheet_id` that was deleted             | Clear the reference (set to nil)                      |
| **Missing asset**      | Pin uses `icon_asset_id` that was deleted                                | Clear the reference, use default icon                 |
| **Shortcut collision** | Restored entity has shortcut "quest.main" but another entity now uses it | Auto-rename to "quest.main-restored"                  |
| **Missing variable**   | Condition references `mc.jaime.health` but that sheet/block was deleted  | Flag the condition as broken (user must fix manually) |
| **Missing target**     | Zone has `target_flow_id` pointing to deleted flow                       | Clear the target reference                            |

### UX flow
1. User clicks "Restore" on a version
2. System loads the snapshot from R2
3. System scans `external_refs` against current project state
4. **If no conflicts**: confirmation dialog → "Restore to v5? A new auto-snapshot of the current state will be created first."
5. **If conflicts found**: conflict report modal showing:
   - List of broken references grouped by type
   - What will happen to each (cleared, renamed, etc.)
   - "Restore anyway" / "Cancel" buttons
6. On confirm: auto-snapshot current state → apply restore → notify collaborators

### Implementation
- `Versioning.validate_restore(snapshot, project_id)` → `{:ok, []}` or `{:ok, conflicts}`
- `Versioning.apply_restore(entity, snapshot, conflict_resolutions)` — applies snapshot with conflict fixes
- Pre-restore auto-snapshot always created (user can undo the restore by restoring the auto-snapshot)
- Restore is **non-destructive** in terms of history: it creates a new state, doesn't delete any versions

### Acceptance criteria
- [ ] Restore scans external references before applying
- [ ] Conflict report modal shows all broken references with resolution plan
- [ ] User can proceed with restore or cancel after seeing conflicts
- [ ] Auto-snapshot of current state created before every restore
- [ ] Shortcut collisions auto-resolved with rename + notification
- [ ] Missing entity/asset references cleared gracefully
- [ ] Restore creates a new version entry ("Restored from v5")

---

## Feature 5: Content-Addressable Asset Storage

### What
Store asset binaries (images, audio) by SHA256 hash in R2. Snapshots reference assets by hash, not by ID. Multiple snapshots sharing the same asset = one copy in storage.

### Why (standalone value)
Without this, every snapshot that includes an avatar, background image, or audio file duplicates the binary. 100 snapshots × 5MB background = 500MB. With content-addressable storage: 5MB (if the image never changed) to maybe 15MB (if it changed 3 times).

### How it works

**On asset upload (existing flow, extended):**
1. User uploads `avatar.png`
2. System calculates SHA256 hash → `a1b2c3d4...`
3. Stores in R2: `projects/{project_id}/blobs/a1b2c3d4.png`
4. Asset record in DB stores both `storage_key` (current path) and `blob_hash`

**On snapshot creation:**
1. Snapshot builder collects all asset references from the entity
2. For each asset: looks up the `blob_hash` from the Asset record
3. Stores blob hashes in the snapshot JSON under `asset_blob_hashes`
4. If the blob doesn't exist yet in the blobs path (for legacy assets), copies it

**On restore:**
1. Read blob hashes from snapshot
2. For each asset reference: check if blob exists in R2 → it should, since blobs are never deleted while referenced
3. Create or update Asset records pointing to the correct blob

**Garbage collection (Oban job):**
1. List all blob hashes referenced by any active version or any current entity
2. List all blobs in R2
3. Delete blobs not referenced by anything
4. Run weekly or monthly

### Schema changes
- `Asset`: add `blob_hash` field (string, nullable — populated on upload, nil for legacy)
- Legacy assets get their hash computed and blob copied on first snapshot that includes them

### Acceptance criteria
- [ ] New asset uploads compute and store SHA256 hash
- [ ] Blob stored at content-addressable path in R2
- [ ] Snapshots reference assets by blob hash
- [ ] Restore resolves blob hashes to correct asset files
- [ ] Multiple snapshots referencing same asset share one blob
- [ ] Garbage collection job cleans unreferenced blobs
- [ ] Legacy assets backfilled on first snapshot inclusion
- [ ] Storage savings verified: N snapshots with unchanged assets ≈ 1× asset size
