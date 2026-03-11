# Epic 2 — Project Snapshots

> Complete project backups that capture absolutely everything

## Context

After Epic 1, individual entities (sheets, flows, scenes) have version history. But designers also need **project-level** safety: a single point-in-time backup of the entire project that captures every entity, every asset, every tree structure — everything needed to fully reconstruct the project from scratch.

A project snapshot is a **complete, self-contained backup**. If the project is deleted, it can be restored entirely from a snapshot. Nothing is left out.

Each feature is independent and ordered by dependency.

---

## Feature 1: Manual Project Snapshots

### What
A user with `manage_project` permission can create a full project snapshot at any time. The snapshot captures **absolutely everything** in the project at that moment.

### Why (standalone value)
Before a major milestone (demo, client delivery, QA handoff), designers need a guaranteed restore point. "Gold Master v1.0" — one click, everything saved.

### What's captured (complete list)

| Category | Data | Includes assets? |
|----------|------|-------------------|
| **Project** | name, slug, settings, configuration | — |
| **Sheets** | All sheets + all blocks with values, config, types, order | Avatar blobs, banner blobs |
| **Flows** | All flows + all nodes + all connections + all node data | Audio blobs in dialogue nodes |
| **Scenes** | All scenes + layers + zones + pins + connections + annotations | Background blobs, pin icon blobs |
| **Localization** | Languages, texts, glossary entries | — |
| **Tree structure** | Complete parent_id + position hierarchy for all entity types | — |
| **Assets** | Full asset registry with blob hashes | All referenced binary blobs |

### Storage format

Project snapshot stored as a compressed archive in R2:

```
projects/{project_id}/project_snapshots/{snapshot_id}.tar.gz
├── manifest.json              # Format version, project metadata, creation date, author
├── project.json               # Project settings and configuration
├── tree.json                  # Complete hierarchical structure for all entity types
├── sheets/
│   ├── {sheet_id_1}.json      # Sheet + blocks snapshot
│   ├── {sheet_id_2}.json
│   └── ...
├── flows/
│   ├── {flow_id_1}.json       # Flow + nodes + connections snapshot
│   ├── {flow_id_2}.json
│   └── ...
├── scenes/
│   ├── {scene_id_1}.json      # Scene + layers + zones + pins + connections + annotations
│   ├── {scene_id_2}.json
│   └── ...
├── localization/
│   ├── languages.json         # All language configurations
│   └── texts.json             # All localization texts
└── blobs/
    ├── a1b2c3...png           # All asset binaries referenced by any entity
    ├── d4e5f6...jpg
    ├── g7h8i9...mp3
    └── ...
```

**The `manifest.json` includes:**
```json
{
  "format_version": "1.0",
  "storyarn_version": "0.1.0",
  "project_id": "uuid",
  "project_name": "My RPG",
  "snapshot_id": "uuid",
  "title": "Gold Master v1.0",
  "description": "Final version for publisher demo",
  "created_by": "user@example.com",
  "created_at": "2026-03-11T16:00:00Z",
  "entity_counts": {
    "sheets": 45,
    "flows": 12,
    "scenes": 8,
    "languages": 3,
    "assets": 67
  },
  "total_size_bytes": 52428800
}
```

### Schema changes

**New schema: `ProjectSnapshot`**
```
project_snapshots
├── id (uuid)
├── project_id (uuid, FK)
├── title (string, required, max 200)
├── description (text, nullable, max 1000)
├── storage_key (string — R2 path to .tar.gz)
├── snapshot_size_bytes (bigint)
├── entity_counts (map — {sheets: N, flows: N, scenes: N, ...})
├── is_auto (boolean — true for daily auto-snapshots)
├── status (string: "creating" | "ready" | "failed" | "restoring")
├── created_by_id (uuid, FK to users)
├── inserted_at (utc_datetime)
```

### Key implementation areas
- **Backend**: `Storyarn.Versioning.ProjectSnapshots` context module
- **Snapshot creation**: Oban job that serializes all entities, collects all blobs, creates archive, uploads to R2
- **UI**: Project settings page → "Versions" tab → "Create Snapshot" button + snapshot list
- **Progress**: since creation can take time (large projects), show progress indicator. Status field tracks lifecycle
- **Quota**: check plan limits before creating. Warn when approaching limit

### Acceptance criteria
- [ ] "Create Project Snapshot" available in project settings
- [ ] Snapshot captures all entities, assets, tree structure, and localization
- [ ] Archive format is self-contained (manifest + JSON + blobs)
- [ ] Snapshot creation runs as background job (Oban)
- [ ] Progress/status visible to user during creation
- [ ] Snapshot list shows title, date, author, size, entity counts
- [ ] Plan quota enforced (block creation when limit reached)
- [ ] `manifest.json` includes format version for forward compatibility

---

## Feature 2: Automatic Daily Snapshots

### What
An Oban cron job runs daily, iterates all projects, and creates a project snapshot for any project that has changes since its last snapshot.

### Why (standalone value)
Manual snapshots require discipline. Daily auto-backups mean that even if a designer never manually creates a snapshot, there's always a recent backup. Maximum data loss: 24 hours.

### How it works

1. **Oban cron job** runs at configurable time (default: 03:00 UTC)
2. For each project with auto-snapshot enabled:
   a. Check if any entity was modified since the last project snapshot (`updated_at` comparison)
   b. If no changes → skip (no duplicate snapshots)
   c. If changes exist → create project snapshot with `is_auto: true`, title: "Daily backup — {date}"
3. If a user created a manual snapshot within the last 6 hours → skip (no near-duplicate)

### Configuration
- Project settings: "Automatic daily backups" toggle (default: on)
- The 6-hour dedup window prevents: user creates manual snapshot at 22:00, auto-job at 03:00 creates nearly identical backup

### Retention
- Auto project snapshots follow the plan's retention policy
- Oldest auto-snapshots pruned when over quota
- Named (manual) snapshots are never auto-pruned

### Acceptance criteria
- [ ] Oban cron job runs daily
- [ ] Only creates snapshot if changes exist since last snapshot
- [ ] Skips if manual snapshot created within 6 hours
- [ ] Project setting to enable/disable auto-snapshots
- [ ] Auto-snapshots marked with `is_auto: true`
- [ ] Retention policy enforced by cleanup job
- [ ] Job handles errors gracefully (one project failure doesn't block others)

---

## Feature 3: Project Restore with Exclusive Lock

### What
Restore an entire project to a previous snapshot. During restoration, the project enters **exclusive mode**: all collaborators are switched to read-only, changes are blocked, and everyone is notified.

### Why (standalone value)
Project restore is the most powerful recovery tool — but also the most dangerous operation. Without protection, collaborators could be editing while the restore overwrites everything underneath them. Exclusive lock makes it safe.

### Restore flow

1. **Initiate** (requires `manage_project` permission):
   - User selects a project snapshot and clicks "Restore"
   - Confirmation modal: "This will restore the entire project to {date}. All current content will be replaced. A backup of the current state will be created first."

2. **Lock phase**:
   - Set `project.restoration_in_progress = true`
   - Broadcast to all connected collaborators: `{:project_locked, :restoration, %{user: "...", snapshot_title: "..."}}`
   - All LiveViews switch to read-only mode (disable all mutations)
   - Collaborators see banner: "Project is being restored by {user}. Please wait..."

3. **Backup phase**:
   - Auto-create a project snapshot of the current state: "Pre-restore backup — {date}"
   - This guarantees the restore can be undone

4. **Restore phase** (Oban job):
   - Download and decompress the target snapshot archive from R2
   - Within a DB transaction:
     a. Delete all current entities (sheets, flows, scenes, localization)
     b. Recreate all entities from snapshot JSON
     c. Restore tree hierarchies (parent_id, position)
     d. Restore asset references (blob hashes → asset records)
   - Verify integrity: entity counts match manifest

5. **Unlock phase**:
   - Set `project.restoration_in_progress = false`
   - Broadcast: `{:project_unlocked, :restoration_complete}`
   - All collaborator LiveViews trigger full reload to pick up new state
   - Initiator sees success message with summary

### Edge cases
- **Collaborator with unsaved changes**: changes are lost. The lock broadcast gives them a warning. The pre-restore backup captured the last persisted state
- **Restore fails mid-transaction**: DB transaction rolls back, project stays as-is, lock released, error reported
- **User disconnects during restore**: Oban job continues. Lock released on completion regardless
- **Concurrent restore attempts**: only one restore per project at a time (check `restoration_in_progress` flag)

### Schema changes
- `Project`: add `restoration_in_progress` (boolean, default: false)
- `Project`: add `restoration_started_by_id` (uuid, FK to users, nullable)
- `Project`: add `restoration_started_at` (utc_datetime, nullable)

### Acceptance criteria
- [ ] Only `manage_project` users can initiate restore
- [ ] Pre-restore backup always created automatically
- [ ] Project enters exclusive mode during restore
- [ ] All connected collaborators see read-only banner
- [ ] Restore runs as background job (Oban)
- [ ] All entities recreated from snapshot
- [ ] Tree structure restored exactly
- [ ] Asset references restored via blob hashes
- [ ] Lock released on completion or failure
- [ ] All collaborator LiveViews reload after restore
- [ ] Concurrent restore attempts blocked

---

## Feature 4: Deleted Project Recovery

### What
When a project is soft-deleted, its project snapshots survive in R2. From the workspace settings, users can restore a deleted project entirely from its most recent (or any) snapshot.

### Why (standalone value)
Accidental project deletion is catastrophic without this. With snapshot-based recovery, deleting a project is reversible. The project can be fully reconstructed — every flow, sheet, scene, asset, and tree structure.

### How it works

1. **On project soft-delete**: snapshots in R2 are NOT deleted. Only the DB record gets `deleted_at`
2. **Recovery UI**: Workspace settings → "Deleted Projects" section → shows projects with available snapshots
3. **Recovery flow**:
   a. User selects deleted project → sees list of available snapshots
   b. Selects a snapshot → clicks "Restore"
   c. System creates a **new project** in the workspace
   d. All entities recreated from snapshot (new UUIDs generated)
   e. Asset blobs already exist in R2 — new asset records point to same blobs
   f. Internal references (node → sheet, zone → flow) remapped to new UUIDs
4. **Result**: a new project that is identical in content to the snapshot, but with fresh IDs

### Why new IDs (not revive old project)?
- The old project's IDs might conflict with data created after deletion
- Clean separation: the restored project is a fresh entity
- No risk of ghost references from other projects pointing to the old IDs

### UUID remapping
The most complex part: every internal reference must be updated.
- Snapshot contains original UUIDs for all entities
- On restore, new UUIDs are generated for each entity
- A mapping table `{old_uuid => new_uuid}` is built
- All internal references are remapped: `speaker_sheet_id`, `target_flow_id`, `parent_id`, `layer_id`, `from_pin_id`, etc.
- External references (to entities outside the project) are left as-is — they may or may not still exist

### Retention
| Plan | Snapshots retained after project deletion |
|------|------------------------------------------|
| Free | 30 days |
| Pro | 90 days |
| Team | 1 year |
| Enterprise | Indefinite |

After retention period, Oban job deletes snapshots and runs blob garbage collection.

### Acceptance criteria
- [ ] Project soft-delete does NOT remove R2 snapshots
- [ ] Workspace settings shows deleted projects with snapshot availability
- [ ] User can select snapshot and restore to new project
- [ ] All entities recreated with new UUIDs
- [ ] Internal references remapped correctly
- [ ] Asset blobs reused (not duplicated)
- [ ] Restored project is fully functional
- [ ] Retention policy enforced by cleanup job
- [ ] Recovery only available to workspace admins

---

## Feature 5: Project Snapshot Export

### What
Download a project snapshot as a self-contained `.tar.gz` archive. The file contains everything needed to reconstruct the project in any Storyarn instance.

### Why (standalone value)
Portability. A designer can export their project, share it with a collaborator on a different workspace, import it into a different Storyarn instance, or simply keep an offline backup on their own machine.

### How it works
1. User clicks "Download" on a project snapshot
2. System generates a signed R2 URL for the `.tar.gz` file
3. Browser downloads the archive directly from R2
4. No server-side processing needed — the archive is already in the correct format

### Future: Import
The inverse operation (import a `.tar.gz` into a workspace as a new project) is a natural follow-up. The `manifest.json` format version ensures forward compatibility. Not in scope for this feature but the architecture supports it.

### Acceptance criteria
- [ ] "Download" button on each project snapshot
- [ ] Download serves the complete `.tar.gz` archive from R2
- [ ] Downloaded file is self-contained (manifest + JSON + blobs)
- [ ] No server-side processing required (direct R2 download via signed URL)
- [ ] File name includes project name and date for easy identification
