# Epic 3 — Drafts

> Private workspaces for experimentation without risk

## Context

After Epics 1 and 2, Storyarn has entity-level version history and project-level backups. But versioning is retroactive — it captures what already happened. Drafts solve the **proactive** problem: "I want to experiment with a big change without affecting what's live."

Drafts are private, individual workspaces. A designer creates a draft of a flow, rewrites the entire dialogue structure, and only merges it back when they're satisfied. No one else sees the work-in-progress. No risk to the main content.

Inspired by [Upwelling](https://www.inkandswitch.com/upwelling/) (Ink & Switch) and Figma's branching — but simpler. No auto-merge, no CRDTs, no branch-from-branch complexity.

Each feature is independent and ordered by dependency.

---

## Feature 1: Create Draft from Entity

### What
A user can create a **draft** (private copy) of any flow, sheet, or scene. The draft is a complete, independent clone of the entity at that moment in time.

### Why (standalone value)
The ability to say "let me try something" without fear is the most requested feature in collaborative design tools. Drafts give designers a safe sandbox.

### How it works

1. User opens a flow/sheet/scene → clicks "Create Draft"
2. System creates a complete copy of the entity and all its children:
   - **Flow draft**: flow metadata + all nodes + all connections
   - **Sheet draft**: sheet metadata + all blocks
   - **Scene draft**: scene metadata + all layers + zones + pins + connections + annotations
3. The draft is stored in the same DB tables but marked with a `draft_id` and `draft_source_id`
4. The draft appears in a "My Drafts" section, not in the main entity tree
5. The draft is **only visible to the creator** — no one else sees it

### Schema changes

**New schema: `Draft`**
```
drafts
├── id (uuid)
├── project_id (uuid, FK)
├── entity_type (string: "sheet" | "flow" | "scene")
├── source_entity_id (uuid — the original entity this was forked from)
├── source_version_number (integer, nullable — version at fork time, if exists)
├── name (string — default: "{entity_name} — Draft")
├── status (string: "active" | "merged" | "discarded")
├── created_by_id (uuid, FK to users)
├── merged_at (utc_datetime, nullable)
├── inserted_at (utc_datetime)
├── updated_at (utc_datetime)
```

**Entity tables extended:**
- `sheets`, `flows`, `scenes` (and child tables): add `draft_id` (uuid, FK to drafts, nullable)
- When `draft_id` is not null, the entity is a draft copy
- All existing queries filter by `is_nil(draft_id)` to exclude draft copies from normal views

### Key implementation areas
- **Cloning engine**: deep copy of entity + all children, assigning new UUIDs and setting `draft_id`
- **Internal reference remapping**: within the draft, all internal references (node connections, layer assignments, pin connections) must point to the new cloned IDs
- **External reference preservation**: references to entities outside the draft (sheets, flows, other scenes) keep their original IDs
- **Asset references**: draft entities point to the same assets (no blob duplication needed)
- **Query isolation**: all list/get queries must exclude draft entities by default
- **Draft access**: only the creator can open/edit the draft

### Design considerations
- Drafts are **not** in the sidebar tree — they have their own section/panel
- The draft editor is the same as the normal editor (same LiveView, same tools), just operating on draft entities
- A visual indicator in the editor makes it clear you're editing a draft, not the live entity (colored banner, "DRAFT" badge)
- Creating a draft does NOT lock the original — others can continue editing the original while you work on the draft
- The original entity may advance while the draft exists. This divergence is shown at merge time

### Acceptance criteria
- [ ] "Create Draft" action available on flows, sheets, and scenes
- [ ] Draft creates a complete deep copy with new UUIDs
- [ ] Internal references remapped correctly within the draft
- [ ] External references preserved as-is
- [ ] Draft entities excluded from all normal queries
- [ ] Draft only visible and editable by creator
- [ ] "My Drafts" section shows all active drafts
- [ ] Visual indicator in editor when editing a draft
- [ ] Creating a draft does not lock the original entity

---

## Feature 2: Edit Draft Independently

### What
The draft is a fully functional entity — the designer can edit it with all the same tools available in the normal editor. Changes to the draft do not affect the original, and changes to the original do not affect the draft.

### Why (standalone value)
A draft that can't be edited is useless. Full editing capability means the designer can experiment freely: restructure a flow, rewrite dialogue, reorganize a scene — all without risk.

### How it works
- Opening a draft loads the draft entities into the same LiveView as normal editing
- The LiveView detects `draft_id` in the URL/params and loads draft entities instead of live ones
- All mutations (create node, move pin, edit block) operate on draft entities
- Auto-snapshots (Epic 1) work on drafts too — the draft has its own version history
- Collaboration features are **disabled** for drafts (no presence, no locks, no broadcasts)

### Divergence tracking
While the designer edits their draft, the original entity may also change (other collaborators editing it). The system tracks this:
- `draft.source_version_number` records the version at fork time
- When the original gets new versions, the draft panel shows: "The original has changed since you created this draft (3 new versions)"
- This is informational only — no auto-rebase, no forced sync

### Design considerations
- URL scheme: `/workspaces/{ws}/projects/{proj}/flows/{flow_id}/draft/{draft_id}` or similar
- The sidebar shows the draft name with a draft icon
- Undo/redo works normally within the draft session
- The draft does not count toward the entity's version history — it has its own

### Acceptance criteria
- [ ] Drafts open in the same editor as normal entities
- [ ] All editing tools work on draft entities
- [ ] Changes to draft don't affect original
- [ ] Changes to original don't affect draft
- [ ] Divergence indicator shows when original has changed
- [ ] Auto-snapshots work on draft entities
- [ ] Collaboration features disabled in draft mode
- [ ] Undo/redo works normally in draft editor
- [ ] URL clearly identifies draft context

---

## Feature 3: Draft Review and Merge

### What
When a draft is ready, the designer initiates a **merge review**: a comparison between the draft and the current state of the original entity. They can then accept (merge) or continue editing.

### Why (standalone value)
The whole point of drafts is to eventually bring the work back to the main entity. Merge review ensures the designer sees what changed and makes an informed decision — especially important when the original diverged.

### Merge flow

1. **Initiate review**: designer clicks "Review & Merge" on the draft
2. **Comparison view**:
   - Shows what the draft changed relative to the original (at fork time)
   - Shows what the original changed since the fork (if anything)
   - Summary: "Your draft: added 3 nodes, modified 5 nodes, deleted 1 connection. Original since fork: modified 2 nodes."
3. **Decision**:
   - **Merge**: draft replaces the current state of the original entity
     - Auto-snapshot of original's current state created first (safety net)
     - Draft entities become the live entities (or live entities are updated to match draft state)
     - Draft marked as `status: merged`, `merged_at: now()`
   - **Continue editing**: close review, keep working on draft
   - **Discard draft**: delete the draft entirely

### Merge strategy (v1: full replacement)
For v1, merge is simple: **the draft completely replaces the original**.
- The original's current state is auto-snapshotted
- The original entity + all children are updated to match the draft's state
- The draft entities are cleaned up (deleted from DB)

This is intentionally simple. Selective merge (pick which nodes to keep) is a future enhancement that builds on the visual diff system.

### What if the original diverged?
The comparison view warns: "The original has changed since you created this draft. Merging will overwrite those changes."
- The auto-snapshot preserves those changes — they can be restored if needed
- The designer decides: are the original's changes important? If so, they can update their draft first

### Notification to collaborators
When a draft is merged:
- All collaborators editing the original receive a broadcast: "The flow was updated by {user} (draft merge)"
- Their LiveViews reload to pick up the new state
- No lock needed (unlike project restore) — it's a single entity update, fast enough to be atomic

### Acceptance criteria
- [ ] "Review & Merge" action on active drafts
- [ ] Comparison summary shows draft changes and original changes since fork
- [ ] Merge creates auto-snapshot of original's current state
- [ ] Merge replaces original with draft content
- [ ] Draft marked as merged after successful merge
- [ ] Collaborators notified of merge and LiveViews reload
- [ ] "Continue editing" returns to draft editor
- [ ] "Discard draft" deletes draft entities with confirmation

---

## Feature 4: Draft Lifecycle Management

### What
UI and backend support for listing, renaming, discarding, and cleaning up drafts. Keeps the workspace tidy and prevents abandoned drafts from accumulating.

### Why (standalone value)
Without lifecycle management, abandoned drafts pile up in the database indefinitely. Users need visibility into their drafts and easy ways to manage them.

### Features

**My Drafts panel:**
- Accessible from project sidebar or user menu
- Lists all active drafts for the current user in this project
- Shows: entity type icon, draft name, original entity name, created date, last edited date
- Actions: Open, Rename, Discard

**Draft staleness:**
- Drafts not edited for 30 days show a "Stale" indicator
- Optional: notification email for stale drafts ("You have a draft of 'Quest Principal' that hasn't been edited in 30 days")

**Cleanup:**
- Discarding a draft deletes all draft entities from DB
- Merged drafts are cleaned up automatically (draft entities deleted, draft record kept for history)
- Oban job cleans up draft entities for merged/discarded drafts (in case of incomplete cleanup)

**Draft limits:**

| Plan       | Max active drafts per user per project  |
|------------|-----------------------------------------|
| Free       | 2                                       |
| Pro        | 10                                      |
| Team       | 25                                      |
| Enterprise | Unlimited                               |

### Acceptance criteria
- [ ] "My Drafts" panel lists all active drafts
- [ ] Drafts can be renamed
- [ ] Drafts can be discarded with confirmation
- [ ] Stale draft indicator after 30 days of inactivity
- [ ] Merged/discarded draft entities cleaned up
- [ ] Draft limits enforced per plan
- [ ] Draft history preserved after merge (record, not entities)
- [ ] Cleanup job handles edge cases (abandoned drafts, partial cleanup)
