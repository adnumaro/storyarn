# Epic 1 — Entity Versioning

> Foundation: auto-snapshots and named versions for individual entities

## Context

Currently only Sheets have versioning (full JSON snapshots with restore). This epic generalizes that system to Flows and Scenes, moves snapshot storage from PostgreSQL to R2, introduces content-addressable asset storage, and adds auto-snapshots triggered by significant actions.

Each feature is independent and ordered by dependency.

---

## Feature 1: Content-Addressable Asset Storage

### What
Store all assets (images, audio) by SHA256 hash of their content. When a snapshot references an asset, it stores the hash — not a copy of the file. Multiple snapshots referencing the same unchanged asset share one physical copy.

### Why (standalone value)
Without this, every snapshot that includes assets would duplicate the binary files, making storage costs explode. This is the foundation that makes versioning with full asset fidelity economically viable.

### Key concepts
- **Blob key**: `projects/{project_id}/blobs/{sha256_hash}.{ext}`
- **On upload**: compute SHA256 of file content, check if blob already exists, skip upload if duplicate
- **Asset record**: existing `Asset` schema gets a new `blob_hash` field linking to the content-addressable blob
- **Snapshot references**: snapshots store `blob_hash` instead of `asset_id` (asset records may be deleted, but blobs persist as long as snapshots reference them)
- **Garbage collection**: Oban job periodically scans for blobs not referenced by any snapshot or active asset → deletes from R2

### Schema changes
- `Asset`: add `blob_hash` field (string, SHA256 hex)
- New table: `blob_references` (or track via snapshot metadata — TBD during implementation)

### Key implementation areas
- **Upload pipeline**: compute SHA256 during upload, store blob by hash, record hash on Asset
- **R2 integration**: extend existing Storage adapter to support blob key format
- **Garbage collection job**: Oban worker that scans for orphaned blobs
- **Migration**: backfill `blob_hash` for existing assets (compute hash from current R2 objects)

### Design considerations
- SHA256 is fast enough for file sizes we handle (images/audio, typically < 50MB)
- Collision probability is negligible (2^-256)
- Extension preserved in blob key for content-type inference on retrieval
- Local dev storage adapter must also support content-addressable pattern
- Existing asset URLs continue to work — blob storage is an additional layer, not a replacement

### Acceptance criteria
- [ ] New asset uploads compute and store SHA256 hash
- [ ] Duplicate content detected and deduplicated (no re-upload)
- [ ] Blob key format: `projects/{project_id}/blobs/{hash}.{ext}`
- [ ] Existing assets backfilled with blob_hash
- [ ] Garbage collection job removes unreferenced blobs
- [ ] Local storage adapter supports same pattern

---

## Feature 2: Generic Snapshot Engine

### What
A unified snapshot system that can capture the complete state of any entity type (sheet, flow, scene) as a compressed JSON blob stored in R2, with lightweight metadata in PostgreSQL.

This generalizes the existing Sheet versioning into a shared engine.

### Why (standalone value)
Without a generic engine, we'd duplicate the snapshot logic for each entity type. The engine provides: snapshot creation, storage, retrieval, listing, and deletion — reusable across all entity types.

### Key concepts
- **Snapshot metadata** (PostgreSQL): id, entity_type, entity_id, project_id, version_number, title, description, change_summary, storage_key, created_by_id, created_at, is_named (boolean)
- **Snapshot content** (R2): compressed JSON at `projects/{project_id}/snapshots/{entity_type}/{entity_id}/{version_number}.json.gz`
- **Entity-specific serializers**: each entity type provides a `build_snapshot/1` function that returns the complete state as a map
- **Asset tracking**: serializers collect all blob_hashes referenced by the entity → stored in snapshot metadata for GC reference tracking

### What each serializer captures

**Sheet snapshot:**
- Metadatos: name, shortcut, description, position, parent_id
- All blocks: type, position, config, value, is_constant, variable_name, scope, inherited_from_block_id, detached, required
- Avatar asset: blob_hash
- Banner asset: blob_hash
- Rich text embedded images: blob_hashes extracted from HTML content

**Flow snapshot:**
- Metadata: name, shortcut, description, position, parent_id
- All nodes: type, data (full), position_x, position_y, width, height
- All connections: source_node_id, target_node_id, source_output, target_input
- Audio assets in dialogue nodes: blob_hashes
- Speaker sheet references: sheet_ids (for conflict detection on restore)

**Scene snapshot:**
- Metadata: name, shortcut, description, position, parent_id, width, height, scale_value, scale_unit, default_zoom, default_center_x, default_center_y
- Background image: blob_hash
- All layers: name, position, visible, opacity, locked
- All zones: vertices, fill_color, border_color, border_style, border_width, opacity, tooltip, action_type, action_data, target_type, target_id, condition, condition_effect, layer_id mapping
- All pins: position_x, position_y, pin_type, size, color, opacity, icon, label, sheet_id, icon_asset blob_hash, action_type, action_data, target_type, target_id, condition, condition_effect, layer_id mapping
- All connections: from_pin mapping, to_pin mapping, waypoints, line_style, line_width, color, bidirectional, label, show_label
- All annotations: text, position_x, position_y, font_size, color, rotation, layer_id mapping

### Schema changes
- New table: `version_snapshots`
  ```sql
  create table(:version_snapshots) do
    add :entity_type, :string, null: false        -- "sheet" | "flow" | "scene"
    add :entity_id, :binary_id, null: false
    add :project_id, references(:projects), null: false
    add :version_number, :integer, null: false
    add :title, :string                            -- nil for auto-snapshots
    add :description, :text
    add :change_summary, :string
    add :storage_key, :string, null: false          -- R2 key
    add :blob_hashes, {:array, :string}, default: [] -- asset references for GC
    add :is_named, :boolean, default: false
    add :created_by_id, references(:users)
    timestamps(updated_at: false)
  end
  ```
- Migrate existing `sheet_versions` data to new table (or keep both during transition)

### Key implementation areas
- **Snapshot engine module**: `Storyarn.Versioning` — generic create/list/get/delete/restore
- **Entity serializers**: `Storyarn.Versioning.SheetSerializer`, `FlowSerializer`, `SceneSerializer`
- **R2 storage**: compress JSON with `:zlib.gzip`, upload to R2, retrieve and decompress
- **Version numbering**: auto-increment per entity (existing pattern from Sheet versioning)
- **Change summary generation**: compare current snapshot with previous → auto-describe changes

### Design considerations
- Serializers must capture **internal IDs** for relationship mapping (which node connects to which) but these are relative IDs within the snapshot, not absolute DB IDs
- Layer/zone/pin/annotation IDs in scene snapshots need a mapping table for restore (new IDs generated, but internal references preserved)
- The engine should be entity-type agnostic — it receives a map and stores it. Type-specific logic lives in serializers
- Compression ratio for JSON is typically 5-10x, so a 100KB snapshot becomes ~15KB in R2
- Keep the existing Sheet versioning working during migration — feature flag for cutover

### Acceptance criteria
- [ ] Generic snapshot engine creates/stores/retrieves snapshots for any entity type
- [ ] Sheet serializer captures complete sheet state including asset blob hashes
- [ ] Flow serializer captures complete flow state including nodes, connections, assets
- [ ] Scene serializer captures complete scene state including all sub-entities and assets
- [ ] Snapshots stored as compressed JSON in R2
- [ ] Metadata stored in PostgreSQL (lightweight, queryable)
- [ ] Version numbers auto-increment per entity
- [ ] Change summary auto-generated by comparing consecutive snapshots
- [ ] Existing sheet versioning migrated to new engine

---

## Feature 3: Auto-Snapshots on Significant Actions

### What
Automatically create entity snapshots when significant changes occur, with a rate-limit of 10-15 minutes between auto-snapshots for the same entity. "Significant" means structural changes, not trivial edits.

### Why (standalone value)
The silent safety net. A designer never thinks about versioning until something goes wrong — and when it does, the last auto-snapshot is at most 10-15 minutes old. Zero friction, maximum safety.

### Key concepts
- **Significant actions by entity type**:
  - **Sheet**: block created/deleted, block type changed, sheet name/shortcut changed
  - **Flow**: node created/deleted, connection created/deleted, node type changed
  - **Scene**: zone created/deleted, pin created/deleted, connection created/deleted, layer created/deleted, background changed
- **NOT significant** (don't trigger snapshot):
  - Text edits within a block value or node data (too granular)
  - Position-only changes (moving a node/pin on canvas)
  - Visual-only changes (colors, opacity, line styles)
- **Rate-limit**: minimum 10 minutes between auto-snapshots for the same entity
- **Deferred creation**: snapshot runs async (Oban job or Task) to not block the user action

### Key implementation areas
- **Action hooks**: after each significant action in CRUD modules, call `Versioning.maybe_auto_snapshot(entity, user)`
- **Rate-limit check**: query latest auto-snapshot timestamp for entity, skip if < 10 minutes
- **Async execution**: snapshot creation is non-blocking — enqueue as Oban job or spawn Task
- **Retention**: auto-snapshots are eligible for expiration (per plan tier). Named versions are not

### Design considerations
- Rate-limit is per-entity, not per-user. If two users both make significant changes to the same flow within 10 minutes, only one auto-snapshot is created
- The rate-limit timer resets on each significant action — so continuous editing extends the window, and the snapshot fires 10 minutes after the LAST significant action (debounce pattern)
- Actually, debounce vs throttle is a design choice:
  - **Throttle** (recommended): snapshot every 10-15 min during active editing. Guarantees regular checkpoints
  - **Debounce**: snapshot only after editing stops for 10 min. Could miss long editing sessions
  - Use **throttle** with a final **trailing snapshot** when the user leaves the editor
- The "leaving editor" snapshot is important: capture state when user navigates away, even if rate-limit hasn't elapsed

### Acceptance criteria
- [ ] Significant actions trigger auto-snapshot creation
- [ ] Rate-limit prevents snapshots more often than every 10 minutes per entity
- [ ] Snapshot creation is async (doesn't block user action)
- [ ] Auto-snapshots are marked as `is_named: false` (eligible for expiration)
- [ ] A trailing snapshot fires when the user leaves the editor
- [ ] Non-significant actions (position, color) do NOT trigger snapshots
- [ ] Auto-snapshots respect plan tier retention limits

---

## Feature 4: Named Versions with Intent

### What
Users can explicitly create a named version of any entity, with a title, description, and auto-generated change summary. Named versions are preserved from auto-expiration and serve as meaningful milestones.

### Why (standalone value)
Auto-snapshots are the safety net. Named versions are the **story of the design process**. "Before rewriting Act 2", "After playtest feedback", "Final version for publisher demo". They answer "why" this state existed, not just "when".

### Key concepts
- **Creation**: user clicks "Create Version" → modal with title (required) + description (optional)
- **Change summary**: auto-generated by comparing with the previous snapshot (same logic as auto-snapshots)
- **Promotion**: any auto-snapshot can be retroactively promoted to a named version (add title + description without re-snapshotting)
- **Limits**: per plan tier (Free: 10, Pro: 50, Team/Enterprise: unlimited)
- **Never expire**: named versions are exempt from the auto-snapshot retention policy

### Schema changes
- Uses same `version_snapshots` table — `is_named: true`, `title` not null for named versions

### Key implementation areas
- **UI**: "Create Version" button in entity editor toolbar → modal form
- **Promotion UI**: in version timeline, auto-snapshots show "Name this version" action
- **Limit enforcement**: check count of named versions for entity before allowing creation
- **Change summary**: reuse the diff logic from Feature 2

### Design considerations
- Promoting an auto-snapshot to named is just updating `is_named`, `title`, `description` — no new snapshot needed
- Named version count limits are per-project, not per-entity (a project with 100 sheets shouldn't get 10 × 100 = 1000 named versions on Free)
- Consider: show named versions prominently in a "Milestones" section, auto-snapshots in an expandable "History" section
- Title max length: 100 chars. Description max: 500 chars

### Acceptance criteria
- [ ] User can create a named version from current entity state
- [ ] Title is required, description is optional
- [ ] Change summary auto-generated
- [ ] Auto-snapshots can be promoted to named versions
- [ ] Named versions exempt from auto-expiration
- [ ] Plan tier limits enforced (with clear error message when exceeded)
- [ ] Named versions visually distinct in version timeline

---

## Feature 5: Restore with Conflict Detection

### What
Restore any version (auto or named) to the current state of an entity, with full validation of cross-entity references. Broken references are reported before restore, and the user decides how to proceed.

### Why (standalone value)
Restore without conflict detection is dangerous — you silently break references and the designer discovers it later in a broken flow or missing character. Conflict detection makes restore **safe and predictable**.

### Key concepts

**Validation checks on restore:**
| Reference type | Check | Resolution |
|---|---|---|
| `speaker_sheet_id` in flow node | Does sheet exist and not deleted? | Warn, nilify on restore |
| `target_flow_id` in node/zone | Does flow exist and not deleted? | Warn, nilify on restore |
| `target_scene_id` in node/zone | Does scene exist and not deleted? | Warn, nilify on restore |
| `sheet_id` on pin | Does sheet exist? | Warn, nilify on restore |
| Variable references in conditions | Does the sheet.variable still exist? | Warn, clear condition on restore |
| Shortcut uniqueness | Is snapshot's shortcut taken by another entity? | Auto-rename with suffix, notify user |
| Asset blob_hash | Does blob still exist in R2? | Warn, restore without asset |

**Conflict report UI:**
- Modal showing all detected conflicts, grouped by severity
- Critical (blocks functionality): broken flow targets, missing speakers
- Warning (cosmetic): missing assets, renamed shortcuts
- Each conflict shows: what's broken, what will happen if you proceed
- User actions: "Restore anyway" (clean broken refs) or "Cancel"

**Non-destructive restore:**
- Before restoring, an auto-snapshot of the CURRENT state is created ("Pre-restore backup")
- This means restore is always reversible — you can "undo" a restore by restoring the pre-restore snapshot

### Key implementation areas
- **Conflict scanner**: receives snapshot + current DB state → produces conflict report
- **Restore executor**: applies snapshot, resolving conflicts per user decision
- **Pre-restore snapshot**: auto-created before every restore operation
- **UI**: conflict report modal with categorized issues and clear actions

### Design considerations
- Restore of a sheet with blocks: all current blocks deleted, snapshot blocks recreated (same as current Sheet versioning)
- Restore of a flow: all current nodes and connections deleted, snapshot nodes/connections recreated. Internal IDs regenerated but relationships preserved via mapping
- Restore of a scene: all current layers/zones/pins/connections/annotations deleted, snapshot sub-entities recreated
- Assets: blob_hashes in snapshot → re-link to existing blobs. If blob was garbage collected (shouldn't happen if GC is correct), the asset reference is nullified
- **Collaboration**: if entity is locked by another user, restore is blocked. If collaborators have the entity open, they receive a push event to reload

### Acceptance criteria
- [ ] Restoring any version triggers conflict detection
- [ ] Conflict report shows all broken references with context
- [ ] User can proceed (clean broken refs) or cancel
- [ ] Pre-restore snapshot auto-created before every restore
- [ ] Shortcut collisions resolved with auto-rename + notification
- [ ] Assets restored from blob hashes (or warned if missing)
- [ ] Locked entities cannot be restored (clear error message)
- [ ] Collaborators viewing the entity receive reload push after restore

---

## Feature 6: Version Timeline UI

### What
A version history panel for each entity (flow, sheet, scene) showing auto-snapshots and named versions in a navigable timeline. Browse, search, and restore from a unified interface.

### Why (standalone value)
The data exists but without good UI it's invisible. The timeline makes version history **discoverable and usable** — designers can see the evolution of their work and confidently navigate through time.

### Key concepts
- **Two-section layout**:
  - **Named Versions** (top): milestones with title, description, change summary, author, date
  - **Auto History** (expandable): collapsed by default, shows auto-snapshots between named versions
- **Each entry shows**: version badge (v12), title or change summary, author avatar, relative date
- **Actions per entry**: Restore, Name (for auto-snapshots), Delete (for named versions)
- **Pagination**: lazy-load older entries on scroll
- **Search**: filter by title, change summary, author, date range

### Key implementation areas
- **LiveComponent**: `VersionTimeline` — reusable across sheet/flow/scene editors
- **Data loading**: paginated query on `version_snapshots` filtered by entity
- **Snapshot detail**: clicking an entry shows full change summary + description
- **Restore flow**: triggers Feature 5 (conflict detection → restore)

### Design considerations
- Reuse and extend the existing `VersionsSection` component from Sheet editor
- Auto-snapshots between two named versions should collapse into "N auto-saves" with expand
- The current version should be highlighted (if set)
- Consider: a visual mini-timeline (vertical line with dots) à la Figma, not just a list
- Mobile-friendly: the panel should work in a slide-out drawer
- Future: this is where visual diffs will live (compare two versions side-by-side). Design the UI with a "Compare" action placeholder that's disabled for now

### Acceptance criteria
- [ ] Version timeline panel available in sheet, flow, and scene editors
- [ ] Named versions shown prominently, auto-snapshots collapsed between them
- [ ] Each entry shows version badge, title/summary, author, date
- [ ] Restore action triggers conflict detection flow
- [ ] "Name this version" action on auto-snapshots
- [ ] Pagination / lazy-load for long histories
- [ ] Search by title, summary, author, date range
- [ ] "Compare" action placeholder (disabled, for future visual diffs)
