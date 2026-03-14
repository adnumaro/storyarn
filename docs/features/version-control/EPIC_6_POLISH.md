# Epic 6 — Draft & Versioning Polish

> Refinements and edge-case hardening for the draft system

## Context

Epics 1–5 deliver entity versioning, project snapshots, drafts, version intelligence, and visual diffs. This epic captures polish items discovered during draft implementation — edge cases, UX improvements, and parity gaps between entity types.

Each feature is independent and can be implemented in any order.

---

## Feature 1: Selective Merge for Flows and Scenes

### What
Extend the selective merge strategy (already implemented for sheets) to flows and scenes. Currently, merging a flow or scene draft does a **full replacement** — all nodes/layers/pins/zones in the original are deleted and replaced with the draft's content. This means entities added to the original after draft creation are lost.

### Why (standalone value)
If a collaborator adds nodes to a flow or pins to a scene while a draft exists, merging the draft silently destroys their work. The same protection sheets have (baseline tracking) should apply to all entity types.

### How it works
Follow the same pattern as sheets:
1. At draft creation, capture baseline entity IDs in `baseline_entity_ids`:
   - **Flows**: `%{"node_ids" => [...], "connection_ids" => [...]}`
   - **Scenes**: `%{"layer_ids" => [...], "pin_ids" => [...], "zone_ids" => [...], "annotation_ids" => [...]}`
2. `CloneEngine.get_baseline_entity_ids/3` already returns `%{}` for flows/scenes — extend it
3. In `FlowBuilder.restore_snapshot/3` and `SceneBuilder.restore_snapshot/3`, accept `baseline_*_ids` opts and only delete entities in the baseline set
4. Handle connection graph integrity: connections referencing a mix of preserved and new nodes need careful remapping

### Complexity notes
- **Flows**: Connections reference nodes by index in the snapshot. With preserved nodes (not in snapshot), index-based restoration breaks. May need to switch to ID-based connection tracking for selective merge.
- **Scenes**: Connections reference pins by (layer_index, pin_index). Same issue — preserved pins not in snapshot break the index mapping.
- Consider a phased approach: start with nodes/layers only (no connection preservation for post-draft entities).

### Acceptance criteria
- [ ] Flow merge preserves nodes added to original after draft creation
- [ ] Scene merge preserves layers/pins/zones added after draft creation
- [ ] Connections involving preserved entities remain intact
- [ ] Variable name / shortcut uniqueness enforced across preserved + merged entities
- [ ] Tests cover selective merge for all entity types

---

## Feature 2: Read-Only Shortcut Display in Flow and Scene Drafts

### What
Show the original entity's shortcut as read-only text in the draft editor for flows and scenes. Currently only implemented for sheet drafts.

### Why (standalone value)
When editing a flow or scene draft, the shortcut field is empty (drafts have `shortcut: nil` to avoid unique constraint conflicts). The designer loses context about what shortcut this entity uses in the project. Showing it read-only — as already done for sheets — keeps the designer oriented.

### How it works
Follow the same pattern as `sheet_live/show.ex`:
1. In `load_draft_flow/2` and `load_draft_scene/2`, load the source entity's shortcut via the draft's `source_entity_id`
2. Assign `source_shortcut` to the socket
3. Pass `is_draft` and `source_shortcut` to the title/header component
4. Render the shortcut as read-only text (not contenteditable) with reduced opacity and tooltip

### Key files to modify
- `lib/storyarn_web/live/flow_live/show.ex` — `load_draft_flow/2`, pass to header component
- `lib/storyarn_web/live/flow_live/components/flow_header.ex` — Render read-only shortcut
- `lib/storyarn_web/live/scene_live/show.ex` — `load_draft_scene/2`, pass to header component
- Scene header component (if shortcut is displayed there)

### Acceptance criteria
- [ ] Flow draft editor shows original shortcut as read-only
- [ ] Scene draft editor shows original shortcut as read-only
- [ ] Shortcut not editable in draft mode
- [ ] Tooltip explains "Shortcut from the original (read-only in draft)"

---

## Feature 3: Stale Draft Email Notifications

### What
Send an email notification to the draft creator when a draft has not been edited for 30 days. The UI already shows a "Stale" badge — this adds proactive outreach.

### Why (standalone value)
Designers may forget about drafts, especially in projects with many collaborators. A gentle email reminder ("You have a draft of 'Quest Principal' that hasn't been edited in 30 days") prompts them to either finish the work or discard the draft.

### How it works
1. Extend `DraftCleanupWorker` (or create a new `DraftStaleNotifier` worker) to query drafts where `last_edited_at < 30 days ago` and `status == "active"`
2. Send a single email per stale draft (track notification in a new field or separate table to avoid re-sending)
3. Email includes: draft name, original entity name, project name, link to open draft, link to discard
4. Respect user notification preferences (if/when implemented)

### Design considerations
- Send at most one stale notification per draft (not daily reminders)
- Add `stale_notified_at` field to Draft schema to track notification state
- Consider batching: one email per user with all their stale drafts, not one per draft

### Acceptance criteria
- [ ] Email sent when draft reaches 30 days without edits
- [ ] Email contains draft name, original entity, and action links
- [ ] Notification sent only once per draft (not repeated)
- [ ] No notification for already-merged or discarded drafts
