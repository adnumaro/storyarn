# Epic 1B — Version Changelog & Diff Summaries

> Structured change summaries between versions so users understand what changed at each point in history

## Context

After Epic 1 (entity versioning with auto-snapshots, named versions, and restore with conflict detection), the Version History panel works but is hard to read. Each version entry shows only a title and timestamp — there's no indication of **what actually changed**. After several restores and edits, the history becomes a wall of opaque entries.

This epic adds structured diff summaries: when a version is created, the system compares it to the previous version and generates a human-readable changelog. This makes version history genuinely useful for understanding what happened and deciding which version to restore to.

**Depends on:** Epic 1 (complete)

---

## Feature 1: Snapshot Diff Engine

### What
A module that compares two snapshots of the same entity type and produces a structured list of changes.

### Why (standalone value)
The diff engine is the foundation for everything else in this epic. Without it, change summaries are guesswork. With it, we can generate accurate, semantic changelogs automatically.

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
  stats: %{added: 2, modified: 1, removed: 1}
}
```

**Per-entity-type diff logic** (via optional `SnapshotBuilder` callback):

```elixir
@callback diff_snapshots(old :: map(), new :: map()) :: [change()]
@optional_callbacks [diff_snapshots: 1]
```

Each builder knows its own structure:

- **FlowBuilder**: Compare nodes (by stable index or technical_id), connections, top-level properties (name, shortcut, scene_id, settings)
- **SceneBuilder**: Compare pins, zones, connections, annotations, layers, background, top-level properties
- **SheetBuilder**: Compare blocks (by variable_name or position), top-level properties (name, shortcut, avatar, banner)

**Matching strategy for collections:**
- Nodes/pins/zones/blocks: Match by a stable identifier where possible (technical_id for flow nodes, variable_name for blocks). Fall back to positional index.
- Connections: Match by source+target pair.
- Unmatched items in old = removed. Unmatched in new = added. Matched pairs = compare fields for modifications.

### Scope boundaries
- Text-level diffs (rich text content word-by-word) are **out of scope** — just detect "text changed" vs "text unchanged"
- Variable/condition expression diffs are **out of scope** — just detect changed vs unchanged
- Position-only changes (node moved on canvas) should be **excluded by default** (noise) but trackable via a flag

---

## Feature 2: Auto-generate Change Summary on Version Creation

### What
When a new version is created (auto or named), compare its snapshot to the previous version's snapshot and store a structured change summary.

### Why (standalone value)
Every version entry in the UI gets an automatic description of what changed, without the user having to write anything. "Added 2 nodes, modified speaker on Dialogue #3, removed 1 connection" vs just "Auto-snapshot".

### Design

**On version creation** (`VersionCrud.create_version/5`):
1. After creating the snapshot, load the previous version's snapshot
2. Run `SnapshotDiff.diff(entity_type, old_snapshot, new_snapshot)`
3. Format the diff into a human-readable `change_summary` string
4. Store in `EntityVersion.change_summary`

**Summary formatting:**
- Compact single-line for the version list: `"2 nodes added, 1 modified, speaker changed on #3"`
- Structured data stored in a new `change_details` JSON field for richer UI rendering later

**Schema change** (`EntityVersion`):
```elixir
field :change_details, :map  # Structured diff data (JSON)
```

The existing `change_summary` (string) becomes the human-readable summary. `change_details` stores the raw structured diff for UI rendering.

**Edge cases:**
- First version (no previous): summary = "Initial version"
- Restore versions: summary already set by restore logic ("Restored from vN") — skip diff
- No changes detected: summary = "No changes" (shouldn't happen with auto-snapshots due to debounce, but handle gracefully)

---

## Feature 3: Changelog Display in Version History UI

### What
Show the change summary for each version in the Version History panel. Expandable detail view for versions with many changes.

### Why (standalone value)
The version list goes from opaque timestamps to a readable changelog. Users can scan history and understand what happened at each point.

### Design

**Collapsed view** (default in version list):
```
v7  Restored from v1
    Mar 12, 2026 at 13:21
    2 nodes modified, speaker changed

v6  Before restore to v1
    Mar 12, 2026 at 13:21
    3 nodes, 2 connections, name: "Flow 1"

v5  Auto-snapshot
    Mar 12, 2026 at 13:06
    Added dialogue node, modified condition #2
```

**Expanded view** (click to expand):
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

### Scope boundaries
- No side-by-side visual diff (that's the "Visual Diffs" future epic)
- No clickable navigation to changed elements (future enhancement)
- No filtering versions by change type (future enhancement)

---

## Feature 4: Version Comparison (Pick Two)

### What
Allow the user to select two versions and see a diff between them, not just consecutive versions.

### Why (standalone value)
"What changed between my named checkpoint and the current state?" is a common question that consecutive diffs don't answer well. Direct comparison gives a clear answer.

### Design

**UI flow:**
1. User clicks "Compare" on a version entry
2. A second version selector appears (default: current/latest)
3. Diff is computed on-demand between the two selected snapshots
4. Changelog displayed in a modal or dedicated panel

**Technical:**
- Reuses the same `SnapshotDiff` engine from Feature 1
- Both snapshots loaded from storage on-demand (not pre-computed)
- No new schema changes needed — comparison is ephemeral

---

## Execution Order

1. **Feature 1** (Diff Engine) — foundation, no UI changes
2. **Feature 2** (Auto-generate summaries) — wires diff into version creation
3. **Feature 3** (Changelog UI) — makes summaries visible
4. **Feature 4** (Compare two versions) — power-user feature, builds on everything above

Features 1-3 form the core value. Feature 4 is a nice-to-have that can be deferred.

## Key Files (expected)

| File                                                               | Purpose                                |
|--------------------------------------------------------------------|----------------------------------------|
| `lib/storyarn/versioning/snapshot_diff.ex`                         | **NEW** — Diff engine core             |
| `lib/storyarn/versioning/builders/flow_builder.ex`                 | Add `diff_snapshots/2`                 |
| `lib/storyarn/versioning/builders/scene_builder.ex`                | Add `diff_snapshots/2`                 |
| `lib/storyarn/versioning/builders/sheet_builder.ex`                | Add `diff_snapshots/2`                 |
| `lib/storyarn/versioning/version_crud.ex`                          | Wire diff into `create_version`        |
| `lib/storyarn/versioning/snapshot_builder.ex`                      | Add optional `diff_snapshots` callback |
| `lib/storyarn_web/components/versions_section.ex`                  | Changelog display UI                   |
| `priv/repo/migrations/*_add_change_details_to_entity_versions.exs` | New JSON column                        |
