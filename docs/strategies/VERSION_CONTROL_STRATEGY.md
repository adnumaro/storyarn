# Version Control Strategy: Final Approach

> **Date:** February 2026
> **Status:** Approved
> **Related:** [Version Control Research](../research/VERSION_CONTROL_RESEARCH.md)

---

## Decision Summary

**Chosen approach:** Hybrid client-side + server-side with premium upgrade path

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  FREE / PRO / TEAM                    ENTERPRISE (Future)       │
│  ─────────────────                    ───────────────────       │
│                                                                  │
│  Layer 1: IndexedDB History (client)  + Full server-side deltas │
│  Layer 2: Activity Log (server)       + Page-level history UI   │
│  Layer 3: Project Snapshots (server)  + Compare any 2 versions  │
│  Layer 4: Export/Import               + Unlimited retention     │
│                                                                  │
│  Server cost: ~$0.01/project/month    + Delta storage costs     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**Rationale:**
- 90% of "restore" requests are by the same user who made the mistake
- Most restoration happens within minutes/hours, not days
- IndexedDB handles this at zero server cost
- Server-side full history can be added later as Enterprise feature

---

## Layer 1: IndexedDB Version History (Client-Side)

### Purpose
Full page-level version history stored locally in the browser. Handles the most common use case: "I made a mistake and want to undo it."

### Key Characteristics

| Property            | Value              |
|---------------------|--------------------|
| Storage location    | Browser IndexedDB  |
| Server cost         | **$0**             |
| Versions per page   | 100 max            |
| Retention           | 7 days             |
| Snapshot interval   | Every 20 versions  |
| Total storage limit | ~50 MB per project |
| Survives refresh    | Yes                |
| Survives clear data | No                 |
| Cross-device sync   | No                 |

### Data Structure

```javascript
// IndexedDB Store: "page_versions"
// Key: page_id

{
  pageId: "uuid-123",
  projectId: "uuid-456",
  currentVersion: 47,
  versions: [
    {
      version: 47,
      timestamp: "2026-02-04T15:30:00Z",
      userId: "uuid-789",        // For multi-user awareness
      type: "delta",
      data: [                    // RFC 6902 JSON Patch
        { "op": "replace", "path": "/age", "value": 36 }
      ]
    },
    {
      version: 40,
      timestamp: "2026-02-04T14:00:00Z",
      userId: "uuid-789",
      type: "snapshot",          // Full page every 20 versions
      data: { /* complete page content */ }
    }
    // ... up to 100 versions
  ]
}
```

### Implementation

```javascript
// assets/js/services/version_history.js

import { openDB } from 'idb';

const DB_NAME = 'storyarn_versions';
const DB_VERSION = 1;
const STORE_NAME = 'page_versions';
const MAX_VERSIONS = 100;
const SNAPSHOT_INTERVAL = 20;
const RETENTION_DAYS = 7;

class VersionHistory {
  constructor() {
    this.db = null;
  }

  async init() {
    this.db = await openDB(DB_NAME, DB_VERSION, {
      upgrade(db) {
        const store = db.createObjectStore(STORE_NAME, { keyPath: 'pageId' });
        store.createIndex('projectId', 'projectId');
        store.createIndex('timestamp', 'versions.timestamp');
      }
    });
  }

  async saveVersion(pageId, projectId, userId, previousContent, newContent) {
    const record = await this.db.get(STORE_NAME, pageId) || {
      pageId,
      projectId,
      currentVersion: 0,
      versions: []
    };

    const newVersion = record.currentVersion + 1;
    const needsSnapshot = newVersion % SNAPSHOT_INTERVAL === 0;

    const versionEntry = {
      version: newVersion,
      timestamp: new Date().toISOString(),
      userId,
      type: needsSnapshot ? 'snapshot' : 'delta',
      data: needsSnapshot
        ? newContent
        : this.computePatch(previousContent, newContent)
    };

    record.versions.push(versionEntry);
    record.currentVersion = newVersion;

    // Prune old versions
    record.versions = this.pruneVersions(record.versions);

    await this.db.put(STORE_NAME, record);
    return newVersion;
  }

  async getVersion(pageId, targetVersion) {
    const record = await this.db.get(STORE_NAME, pageId);
    if (!record) return null;

    // Find nearest snapshot before target
    const snapshot = this.findNearestSnapshot(record.versions, targetVersion);
    if (!snapshot) return null;

    // Reconstruct by applying patches
    let content = snapshot.data;
    const patches = record.versions
      .filter(v => v.version > snapshot.version && v.version <= targetVersion)
      .sort((a, b) => a.version - b.version);

    for (const patch of patches) {
      if (patch.type === 'delta') {
        content = this.applyPatch(content, patch.data);
      } else {
        content = patch.data;
      }
    }

    return content;
  }

  async getVersionList(pageId) {
    const record = await this.db.get(STORE_NAME, pageId);
    if (!record) return [];

    return record.versions.map(v => ({
      version: v.version,
      timestamp: v.timestamp,
      userId: v.userId,
      type: v.type
    }));
  }

  computePatch(oldContent, newContent) {
    // Use RFC 6902 JSON Patch
    return jsonpatch.compare(oldContent, newContent);
  }

  applyPatch(content, patch) {
    return jsonpatch.applyPatch(structuredClone(content), patch).newDocument;
  }

  findNearestSnapshot(versions, targetVersion) {
    return versions
      .filter(v => v.type === 'snapshot' && v.version <= targetVersion)
      .sort((a, b) => b.version - a.version)[0];
  }

  pruneVersions(versions) {
    const cutoff = new Date();
    cutoff.setDate(cutoff.getDate() - RETENTION_DAYS);

    // Keep versions within retention period
    let kept = versions.filter(v => new Date(v.timestamp) > cutoff);

    // Ensure we don't exceed max versions
    if (kept.length > MAX_VERSIONS) {
      // Keep most recent, but ensure at least one snapshot remains
      const snapshots = kept.filter(v => v.type === 'snapshot');
      const deltas = kept.filter(v => v.type === 'delta');

      kept = [
        ...snapshots.slice(-5),  // Keep last 5 snapshots
        ...deltas.slice(-(MAX_VERSIONS - 5))  // Fill rest with deltas
      ].sort((a, b) => a.version - b.version);
    }

    return kept;
  }

  async clearProject(projectId) {
    const tx = this.db.transaction(STORE_NAME, 'readwrite');
    const index = tx.store.index('projectId');

    for await (const cursor of index.iterate(projectId)) {
      cursor.delete();
    }
  }
}

export const versionHistory = new VersionHistory();
```

### LiveView Integration

```javascript
// In flow_canvas.js or page editor hook

Hooks.PageEditor = {
  mounted() {
    this.previousContent = null;

    // Initialize version history
    versionHistory.init();

    // Track content changes
    this.handleEvent("page_loaded", ({ page }) => {
      this.previousContent = page.content;
    });

    this.handleEvent("page_saved", ({ page, userId }) => {
      if (this.previousContent) {
        versionHistory.saveVersion(
          page.id,
          page.project_id,
          userId,
          this.previousContent,
          page.content
        );
      }
      this.previousContent = page.content;
    });
  }
}
```

### UI: Version History Panel

```
┌─ Page History (Local) ──────────────────────────┐
│                                                  │
│ Your recent changes (stored in browser)          │
│                                                  │
│ v47  Just now                           [View]  │
│      Changed: age, description                   │
│                                                  │
│ v46  2 minutes ago                      [View]  │
│      Changed: name                               │
│                                                  │
│ v45  5 minutes ago                      [View]  │
│      Changed: biography                          │
│                                                  │
│ v40  15 minutes ago              [Restore]     │
│      Snapshot                                    │
│                                                  │
│ ─────────────────────────────────────────────── │
│ ⓘ History is stored locally in your browser.   │
│   It will be lost if you clear browser data.    │
│   Use Project Snapshots for permanent backups.  │
└─────────────────────────────────────────────────┘
```

---

## Layer 2: Activity Log (Server-Side)

### Purpose
Track WHO did WHAT WHEN for team awareness. Does NOT store actual values.

### Database Schema

```sql
CREATE TABLE project_activities (
  id BIGSERIAL PRIMARY KEY,
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  page_id UUID REFERENCES pages(id) ON DELETE SET NULL,
  flow_id UUID REFERENCES flows(id) ON DELETE SET NULL,
  user_id UUID NOT NULL REFERENCES users(id),

  action VARCHAR(50) NOT NULL,      -- 'created', 'updated', 'deleted', 'moved'
  target_type VARCHAR(50) NOT NULL, -- 'page', 'flow', 'node', 'connection', 'asset'
  target_name VARCHAR(255),         -- Name at time of action (preserved for deleted items)
  changed_fields TEXT[],            -- ['age', 'description'] - field names only
  metadata JSONB,                   -- Optional context (old_parent, new_parent, etc.)

  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_activities_project_recent
  ON project_activities(project_id, created_at DESC);
CREATE INDEX idx_activities_page
  ON project_activities(page_id, created_at DESC)
  WHERE page_id IS NOT NULL;
CREATE INDEX idx_activities_user
  ON project_activities(user_id, created_at DESC);
```

### What We Track

| Action   | Target Type   | Fields Logged               |
|----------|---------------|-----------------------------|
| created  | page          | name, parent_name           |
| updated  | page          | list of changed field names |
| deleted  | page          | name (preserved)            |
| moved    | page          | old_parent, new_parent      |
| created  | flow          | name                        |
| updated  | flow          | name (if changed)           |
| created  | node          | node_type, flow_name        |
| deleted  | node          | node_type, flow_name        |
| created  | connection    | source_name, target_name    |

### What We DON'T Track
- Previous values
- New values
- Full content diffs

### Storage Estimate
- ~150 bytes per event
- 50 events/day x 365 days = ~2.7 MB/year per active project
- Negligible cost

### Retention by Plan

| Plan       | Retention  |
|------------|------------|
| Free       | 30 days    |
| Pro        | 90 days    |
| Team       | 1 year     |
| Enterprise | Unlimited  |

### Elixir Implementation

```elixir
defmodule Storyarn.Activities do
  alias Storyarn.Repo
  alias Storyarn.Activities.ProjectActivity

  def log_page_update(page, user, changed_fields) do
    %ProjectActivity{}
    |> ProjectActivity.changeset(%{
      project_id: page.project_id,
      page_id: page.id,
      user_id: user.id,
      action: "updated",
      target_type: "page",
      target_name: page.name,
      changed_fields: changed_fields
    })
    |> Repo.insert()
  end

  def list_project_activities(project_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    ProjectActivity
    |> where([a], a.project_id == ^project_id)
    |> order_by([a], desc: a.created_at)
    |> limit(^limit)
    |> preload(:user)
    |> Repo.all()
  end
end
```

### UI: Activity Feed

```
┌─ Project Activity ──────────────────────────────┐
│                                                  │
│ Today                                            │
│                                                  │
│ 3:45 PM  Maria                                  │
│ └── Edited "Jaime" (age, description)           │
│                                                  │
│ 2:30 PM  You                                    │
│ └── Created "Cersei"                            │
│                                                  │
│ 11:00 AM  Carlos                                │
│ └── Deleted "Old Character"                     │
│                                                  │
│ Yesterday                                        │
│                                                  │
│ 5:00 PM  Maria                                  │
│ └── Moved "Tavern" to "Locations/Cities"        │
│                                                  │
│ 2:15 PM  You                                    │
│ └── Added dialogue node in "Main Quest"         │
│                                                  │
│ [Load more...]                                   │
│                                                  │
└─────────────────────────────────────────────────┘
```

---

## Layer 3: Project Snapshots

### Purpose
Full project backups for disaster recovery and milestones.

### Types

| Type   | Trigger                            | Retention      |
|--------|------------------------------------|----------------|
| Manual | User clicks "Create Snapshot"      | Based on plan  |
| Auto   | Daily at midnight if changes exist | Rolling window |

### Limits by Plan

| Plan       | Manual    | Auto    | Retention  |
|------------|-----------|---------|------------|
| Free       | 3         | 3 days  | 30 days    |
| Pro        | 10        | 7 days  | 1 year     |
| Team       | 25        | 14 days | Unlimited  |
| Enterprise | Unlimited | 30 days | Unlimited  |

### Database Schema

```sql
CREATE TABLE project_snapshots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,

  name VARCHAR(255) NOT NULL,
  description TEXT,
  snapshot_type VARCHAR(20) DEFAULT 'manual', -- 'manual' | 'auto'

  -- Storage
  storage_type VARCHAR(20) DEFAULT 'database', -- 'database' | 's3'
  data BYTEA,                    -- Compressed snapshot (if database)
  s3_key TEXT,                   -- S3 path (if s3)

  -- Metadata
  page_count INTEGER,
  flow_count INTEGER,
  asset_count INTEGER,
  size_bytes BIGINT,

  created_by UUID REFERENCES users(id),
  created_at TIMESTAMP DEFAULT NOW(),

  CONSTRAINT unique_snapshot_name UNIQUE(project_id, name)
);

CREATE INDEX idx_snapshots_project ON project_snapshots(project_id, created_at DESC);
CREATE INDEX idx_snapshots_auto ON project_snapshots(project_id, created_at DESC)
  WHERE snapshot_type = 'auto';
```

### Storage Strategy

```
Project size    →  Storage location
─────────────────────────────────────
< 5 MB          →  PostgreSQL (BYTEA with zstd)
5-50 MB         →  S3 Standard
> 50 MB         →  S3 (with lifecycle to Glacier after 90 days)
```

### Snapshot Data Format

```json
{
  "format_version": "1.0",
  "created_at": "2026-02-04T15:30:00Z",
  "project": {
    "id": "uuid",
    "name": "My Game",
    "settings": {}
  },
  "pages": [
    {
      "id": "uuid",
      "name": "Jaime",
      "parent_id": "uuid",
      "position": 0,
      "template_id": null,
      "blocks": []
    }
  ],
  "flows": [
    {
      "id": "uuid",
      "name": "Main Quest",
      "nodes": [],
      "connections": []
    }
  ],
  "assets": [
    {
      "id": "uuid",
      "name": "portrait.png",
      "type": "image",
      "url": "https://..."
    }
  ]
}
```

### UI: Snapshot Management

```
┌─ Project Snapshots ─────────────────────────────┐
│                                                  │
│ MANUAL SNAPSHOTS                     [+ Create] │
│                                                  │
│ "Release v1.0"                                  │
│   Feb 1, 2026 • 47 pages • 1.2 MB • by You     │
│   [Restore] [Fork] [Download] [Delete]          │
│                                                  │
│ "Pre-Alpha"                                     │
│   Jan 15, 2026 • 35 pages • 890 KB • by Maria  │
│   [Restore] [Fork] [Download] [Delete]          │
│                                                  │
│ 2 of 10 manual snapshots                        │
│                                                  │
│ ─────────────────────────────────────────────── │
│                                                  │
│ AUTO SNAPSHOTS                                   │
│                                                  │
│ Feb 4, 2026 (today)      • 52 pages • 1.3 MB   │
│ Feb 3, 2026 (yesterday)  • 51 pages • 1.2 MB   │
│ Feb 2, 2026              • 50 pages • 1.2 MB   │
│                                                  │
│ Auto-snapshots: daily if changes exist          │
│ Keeping last 7 days (Pro plan)                  │
│                                                  │
└─────────────────────────────────────────────────┘
```

---

## Layer 4: Export/Import

### Purpose
User-controlled local backups and project portability.

### Formats

| Format   | Contents               | Use Case                |
|----------|------------------------|-------------------------|
| JSON     | Pages, flows, settings | Quick backup, re-import |
| ZIP      | JSON + all asset files | Full archive            |

### UI

```
┌─ Export Project ────────────────────────────────┐
│                                                  │
│ Download a backup of your project               │
│                                                  │
│ Format:                                          │
│ ○ JSON only (2.1 MB)                            │
│   Pages, flows, settings. No asset files.       │
│                                                  │
│ ● ZIP with assets (45 MB)                       │
│   Everything including images and audio.        │
│                                                  │
│ [Download]                                       │
│                                                  │
│ Last export: Feb 1, 2026                         │
│                                                  │
└─────────────────────────────────────────────────┘
```

---

## Storage & Cost Summary

### Per Project (Active, 10K pages, 50 edits/day)

| Component               | Storage    | Cost/month  |
|-------------------------|------------|-------------|
| IndexedDB (client)      | ~2 MB      | **$0**      |
| Activity Log (30 days)  | ~225 KB    | ~$0         |
| Auto-Snapshots (7 days) | ~10 MB     | ~$0.001     |
| Manual Snapshots (10)   | ~15 MB     | ~$0.002     |
| **Total server**        | **~25 MB** | **~$0.003** |

### For 1,000 Projects

| Component                                 | Storage    | Cost/month      |
|-------------------------------------------|------------|-----------------|
| PostgreSQL (activities + small snapshots) | ~5 GB      | Included in RDS |
| S3 (large snapshots)                      | ~20 GB     | ~$0.50          |
| **Total**                                 | **~25 GB** | **~$0.50**      |

### Comparison

| Approach                   | Storage/year       | 1000 Projects/year   |
|----------------------------|--------------------|----------------------|
| Full page copies (naive)   | 90 MB              | 90 GB                |
| Server-side deltas         | 5 MB               | 5 GB                 |
| **This approach (hybrid)** | **~0.3 MB server** | **~0.3 GB**          |

**Server storage reduction: 99.6% vs naive, 94% vs server-side deltas**

---

## Enterprise Upgrade Path (Future)

When demand exists, add full server-side page history:

```
┌─ Enterprise Features ───────────────────────────┐
│                                                  │
│ Page-Level Version History                       │
│                                                  │
│ ✓ Full server-side history for all pages        │
│ ✓ Compare any two versions side-by-side         │
│ ✓ See exact field-level changes                 │
│ ✓ Restore individual pages to any version       │
│ ✓ Audit trail with values (who changed what to) │
│ ✓ Unlimited retention                           │
│                                                  │
│ Implementation: RFC 6902 JSON Patch + zstd      │
│ See: docs/research/VERSION_CONTROL_RESEARCH.md  │
│                                                  │
└─────────────────────────────────────────────────┘
```

---

## Implementation Priority

### Phase 1: IndexedDB History
1. Add `idb` npm package
2. Implement `VersionHistory` class
3. Integrate with page editor saves
4. Add basic "View history" UI

### Phase 2: Activity Log
1. Create `project_activities` table
2. Add activity logging to contexts
3. Activity feed component
4. Retention job (Oban)

### Phase 3: Snapshots
1. Create `project_snapshots` table
2. Manual snapshot creation
3. Snapshot restore (fork method)
4. Snapshot management UI

### Phase 4: Auto-Snapshots
1. Daily snapshot job (Oban)
2. Pruning logic
3. S3 integration for large projects

### Phase 5: Export/Import
1. JSON export
2. ZIP with assets
3. Import from backup

---

## Summary

| Layer        | What                | Where         | Cost   | Covers            |
|--------------|---------------------|---------------|--------|-------------------|
| IndexedDB    | Full page history   | Browser       | $0     | 90% of undo needs |
| Activity Log | Who/what/when       | PostgreSQL    | ~$0    | Team awareness    |
| Snapshots    | Full project backup | PostgreSQL/S3 | ~$0.01 | Disaster recovery |
| Export       | Downloadable backup | User's disk   | $0     | Portability       |

**This approach provides excellent version control UX at near-zero cost, with a clear upgrade path to full server-side history for Enterprise.**
