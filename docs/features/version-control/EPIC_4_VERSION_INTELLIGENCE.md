# Epic 4 — Version Intelligence

> Smart restore, automatic changelogs, and side-by-side version comparison

## Context

After Epics 1–3 (entity versioning, project snapshots, drafts), the versioning system is functional but opaque. Each version entry shows only a title and timestamp — there's no indication of **what actually changed**. After several restores and edits, the history becomes a wall of indistinguishable entries.

Additionally, restoring a version always creates a "Before restore" safety snapshot, even when the current state is already versioned. This wastes version quota on limited plans and clutters the history.

Finally, there's no way to visually compare two versions of an entity. Users have to restore, look around, undo, try another — a painful workflow.

This epic makes the version system **intelligent**: it understands what changed, avoids redundant snapshots, generates human-readable changelogs, and lets users compare any version side-by-side with the current state.

**Depends on:** Epic 1 (complete), Epic 3 (Drafts)

---

## Feature 1: Snapshot Diff Engine

### What
A module that compares two snapshots of the same entity type and produces a structured list of changes.

### Why (standalone value)
The diff engine is the foundation for everything else in this epic. Without it, change summaries are guesswork and smart restore can't detect "no changes". With it, we can generate accurate, semantic changelogs automatically and avoid redundant snapshots.

### Design

**Module:** `Storyarn.Versioning.SnapshotDiff`

**Input:** Two snapshots (maps) + entity type string

**Output:** A structured changeset:
```elixir
%{
  changes: [
    %{category: :node, action: :added, detail: "Dialogue node \"Greeting\""},
    %{category: :node, action: :modified, detail: "Dialogue node #3 — speaker changed"},
    %{category: :node, action: :removed, detail: "Condition node #5"},
    %{category: :connection, action: :added, detail: "Connection from Entry to Dialogue #1"},
    %{category: :property, action: :modified, detail: "Flow name: \"Old\" → \"New\""},
    %{category: :property, action: :modified, detail: "Shortcut: \"old-sc\" → \"new-sc\""},
  ],
  stats: %{added: 2, modified: 1, removed: 1},
  has_changes: true
}
```

**Per-entity-type diff logic** (via optional `SnapshotBuilder` callback):

```elixir
@callback diff_snapshots(old :: map(), new :: map()) :: [change()]
@optional_callbacks [diff_snapshots: 2]
```

Each builder knows its own structure:

- **FlowBuilder**: Compare nodes (by stable index or technical_id), connections, top-level properties (name, shortcut, scene_id, settings)
- **SceneBuilder**: Compare pins, zones, connections, annotations, layers, background, top-level properties
- **SheetBuilder**: Compare blocks (by variable_name or position), top-level properties (name, shortcut, avatar, banner)

**Matching strategy for collections:**
- Nodes/pins/zones/blocks: Match by a stable identifier where possible (technical_id for flow nodes, variable_name for blocks). Fall back to positional index.
- Connections: Match by source+target pair.
- Unmatched items in old = removed. Unmatched in new = added. Matched pairs = compare fields for modifications.

**Quick check function** for smart restore (Feature 2):
```elixir
SnapshotDiff.has_changes?(entity_type, old_snapshot, new_snapshot) :: boolean()
```
Short-circuits on first detected change — doesn't compute the full diff.

### Scope boundaries
- Text-level diffs (rich text content word-by-word) are **out of scope** — just detect "text changed" vs "text unchanged"
- Variable/condition expression diffs are **out of scope** — just detect changed vs unchanged
- Position-only changes (node moved on canvas) should be **excluded by default** (noise) but trackable via a flag

---

## Feature 2: Smart Pre-Restore

### What
Before restoring a version, check if the current state has unversioned changes. If yes, ask the user what to do. If no, skip the safety snapshot entirely.

### Why (standalone value)
Currently, every restore creates a "Before restore to vN" snapshot regardless of whether the current state already exists in the version history. This wastes version quota (especially painful on Free/Pro plans) and clutters the history with duplicate entries. Smart pre-restore eliminates redundant versions and gives the user explicit control over their unsaved work.

### Design

**Pre-restore flow:**

1. User clicks "Restore" on a version → `preview_restore` event fires
2. Load the latest version's snapshot and the current entity state (build snapshot without persisting)
3. Run `SnapshotDiff.has_changes?(entity_type, latest_snapshot, current_snapshot)`
4. **If no changes:** proceed directly to conflict detection modal. No "Before restore" snapshot will be created.
5. **If changes detected:** show a modal explaining:
   - "You have unsaved changes that aren't in any version."
   - Option A: **"Save & Restore"** — create a named version with the current state, then restore
   - Option B: **"Discard & Restore"** — skip saving, proceed to restore (changes lost)
   - Option C: **"Cancel"** — abort

**Integration with existing restore flow:**

The conflict detection modal (from Epic 1, Feature 4) appears **after** the user resolves the unsaved changes question. The flow becomes:

```
Restore click
  → Has unsaved changes?
    → Yes: Save/Discard/Cancel modal
      → Save & Restore: create version → conflict check → restore
      → Discard & Restore: conflict check → restore
    → No: conflict check → restore
```

**"Current snapshot" generation:**
Reuse the existing `SnapshotBuilder.build_snapshot/2` to capture the live entity state without persisting it. Compare against the latest version's snapshot loaded from storage.

### Edge cases
- Entity has zero versions (first-time restore from a named version): always has changes, offer Save & Restore
- Entity was just auto-snapshotted (debounce timer fired): likely no changes, skip safety snapshot

---

## Feature 3: Automatic Changelog

### What
When a new version is created (auto or named), compare its snapshot to the previous version's snapshot and store a structured change summary. Display it in the Version History panel.

### Why (standalone value)
Every version entry in the UI gets an automatic description of what changed, without the user having to write anything. "Added 2 nodes, modified speaker on Dialogue #3, removed 1 connection" vs just "Auto-snapshot". The version history goes from a wall of opaque timestamps to a readable changelog.

### Design

**On version creation** (`VersionCrud.create_version/5`):
1. After creating the snapshot, load the previous version's snapshot
2. Run `SnapshotDiff.diff(entity_type, old_snapshot, new_snapshot)`
3. Format the diff into a human-readable `change_summary` string
4. Store structured data in `change_details` JSON field

**Schema change** (`EntityVersion`):
```elixir
field :change_details, :map  # Structured diff data (JSON)
```

The existing `change_summary` (string) becomes the human-readable summary. `change_details` stores the raw structured diff for richer UI rendering.

**Summary formatting:**
- Compact single-line for the version list: `"2 nodes added, 1 modified, speaker changed on #3"`
- Structured data in `change_details` for expandable UI

**Edge cases:**
- First version (no previous): summary = "Initial version"
- Restore versions: summary already set by restore logic ("Restored from vN") — skip diff
- No changes detected: summary = "No changes" (shouldn't happen with auto-snapshots due to debounce, but handle gracefully)

**UI in Version History panel:**

Collapsed view (default):
```
v7  Restored from v1
    Mar 12, 2026 at 13:21
    2 nodes modified, speaker changed

v5  Auto-snapshot
    Mar 12, 2026 at 13:06
    Added dialogue node, modified condition #2
```

Expanded view (click to expand):
```
v5  Auto-snapshot
    Mar 12, 2026 at 13:06

    Changes:
    + Added dialogue node "Greeting"
    ~ Modified condition node #2 — expression changed
    ~ Modified flow name: "Draft" → "Flow 1"
    - Removed connection: Entry → Hub #1
```

**UI components:**
- Change summary line below date/author in `version_row`
- Expandable section with categorized change list
- Icons: `+` added (green), `~` modified (amber), `-` removed (red)

---

## Feature 4: Split View Comparison

### What
Side-by-side comparison of the current entity state with any historical version. The current version is fully editable, the historical version is readonly but fully inspectable (toolbars, sidebar settings, node properties).

### Why (standalone value)
"What did this flow look like before I restructured it?" is a question that no competing tool answers well. articy has binary diffs (useless), Figma has no structured diff, Notion has no comparison at all. Having two versions side-by-side — even without diff highlighting — lets users visually compare and understand what changed. This is an app-killer feature.

### Design

**Architecture: iframe-based isolation**

The historical version loads in an iframe using the same editor page but fed with snapshot data instead of live DB data. This gives complete JS isolation — no conflicts between two Rete.js or Leaflet instances.

```
┌─────────────────────────────────────────────────┐
│  Global header / toolbar                        │
├────────────────────┬────────────────────────────┤
│  Current version   │  Historical version        │
│  (normal editor)   │  (iframe, readonly)        │
│                    │                            │
│  Full editing      │  Full inspection           │
│  capabilities      │  Toolbars, sidebars work   │
│                    │  No mutations              │
└────────────────────┴────────────────────────────┘
```

**Readonly iframe route:**

New route: `GET /workspaces/:slug/projects/:slug/versions/:entity_type/:id/:version_number`

This route loads a LiveView that:
- Reads the snapshot from storage instead of the live DB
- Deserializes it into the format the editor expects (reuse `SnapshotBuilder` logic)
- Sets `can_edit: false` (existing mechanism already disables all mutations)
- Uses a minimal layout (no workspace sidebar, no top nav) but keeps the editor UI intact:
  - Toolbars remain visible
  - Right sidebar can be opened to inspect element properties
  - Node/pin/zone selection works (for inspection)
  - All edit actions are disabled

**Parent split view:**

When the user clicks "Compare" on a version entry in the Version History panel:
1. The editor layout transitions to split mode (CSS grid 50/50)
2. Left side: current editor (unchanged, fully functional)
3. Right side: iframe loading the readonly route for the selected version
4. A header bar shows version info: "Comparing with v5 — Auto-snapshot (Mar 12, 2026)"
5. Close button returns to normal single-pane view

**What the iframe gets right for free:**
- Full canvas rendering (Rete.js for flows, Leaflet for scenes, block list for sheets)
- All existing hooks and interactions in readonly mode
- Toolbar state (zoom, pan, etc.)
- Right sidebar with element properties
- No interference with the main editor's JS state

**What needs to be built:**
- Snapshot-to-editor-data deserializer (render snapshot without persisting to DB)
- Minimal layout variant for the iframe
- Split view CSS layout with resize handle
- Version selector in the comparison header
- Route + LiveView for the readonly snapshot viewer

### Scope boundaries
- No diff highlighting (colored nodes/connections) — that's Epic 5 (Visual Diffs)
- No synchronized zoom/pan between the two views (future enhancement)
- No "navigate to change" feature (future enhancement)
- Resize handle between panes is nice-to-have, not required for MVP

---

## Execution Order

1. **Feature 1** (Diff Engine) — foundation, no UI changes
2. **Feature 2** (Smart Pre-Restore) — uses diff engine to detect changes
3. **Feature 3** (Automatic Changelog) — uses diff engine to generate summaries + UI
4. **Feature 4** (Split View) — independent from 2-3, but benefits from having the diff engine available

Features 1-3 form a tight unit. Feature 4 can be built in parallel after Feature 1 is done.

## Key Files (expected)

| File                                                               | Purpose                                                |
|--------------------------------------------------------------------|--------------------------------------------------------|
| `lib/storyarn/versioning/snapshot_diff.ex`                         | **NEW** — Diff engine core                             |
| `lib/storyarn/versioning/builders/flow_builder.ex`                 | Add `diff_snapshots/2`                                 |
| `lib/storyarn/versioning/builders/scene_builder.ex`                | Add `diff_snapshots/2`                                 |
| `lib/storyarn/versioning/builders/sheet_builder.ex`                | Add `diff_snapshots/2`                                 |
| `lib/storyarn/versioning/version_crud.ex`                          | Wire diff into `create_version`, smart pre-restore     |
| `lib/storyarn/versioning/snapshot_builder.ex`                      | Add optional `diff_snapshots` callback                 |
| `lib/storyarn_web/components/versions_section.ex`                  | Smart restore modal, changelog display, compare button |
| `lib/storyarn_web/live/version_live/show.ex`                       | **NEW** — Readonly snapshot viewer for iframe          |
| `lib/storyarn_web/layouts/version_compare.html.heex`               | **NEW** — Minimal layout for iframe                    |
| `priv/repo/migrations/*_add_change_details_to_entity_versions.exs` | New JSON column                                        |
