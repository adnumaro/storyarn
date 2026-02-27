# Phase 7.5: Sheets Enhancement

> **Goal:** Evolve Sheets into a more powerful wiki-like system with variables, references, and version control
>
> **Priority:** Before Phase 7 (Export) - this defines the data model that will be exported
>
> **Last Updated:** February 8, 2026

## Overview

This phase enhances the Sheets system to be more like Notion/articy:draft, adding:
- Blocks as variables (accessible from flow scripting)
- Reference system with shortcuts (`#shortcut.path`)
- Bidirectional links (backlinks)
- Sheet versioning and history
- New block types (boolean, date, reference)
- Sheet avatar (image upload replacing icon field)
- Sheet color and description
- Property inheritance (blocks cascade from parent to child sheets)
- Column layout (blocks side-by-side in 2-3 column groups)

---

## Architecture Changes

### Sheets Domain Model (After)

```
sheets
├── id, project_id, name, parent_id, position
├── shortcut                    # User-defined alias (unique per project)
├── description                 # Rich text for annotations
├── color                       # Hex color (#fff, #3b82f6, #3b82f680)
├── avatar_asset_id             # Sheet avatar/thumbnail (FK to assets)
├── banner_asset_id             # Optional header image (FK to assets)
├── current_version_id          # FK to sheet_versions
├── hidden_inherited_block_ids  # {:array, :integer} - hidden ancestor blocks
├── deleted_at                  # Soft delete
└── timestamps

blocks
├── id, sheet_id, type, position, config, value
├── is_constant                 # boolean (default false) - if true, NOT a variable
├── variable_name               # Auto-generated from label (slugified)
├── scope                       # "self" | "children" - inheritance scope
├── inherited_from_block_id     # FK to parent block (for inheritance)
├── detached                    # boolean - detached from parent definition
├── required                    # boolean - required field
├── column_group_id             # UUID - groups blocks side-by-side
├── column_index                # integer 0-2 - position within column group
├── deleted_at                  # Soft delete
└── timestamps

sheet_versions
├── id, sheet_id
├── version_number
├── snapshot (JSONB)  # {name, avatar_asset_id, shortcut, blocks: [...]}
├── changed_by_id (FK user)
├── change_summary    # Auto-generated: "Added 2 blocks, modified text"
└── created_at

entity_references     # Backlinks tracking
├── id
├── source_type       # "block" | "flow_node"
├── source_id         # bigint
├── target_type       # "sheet" | "flow"
├── target_id         # bigint
├── context           # Where in the source (block_id, node field, etc.)
└── timestamps
```

### Flows Domain Model (Updates)

```
flows
├── ...existing fields...
├── shortcut          # NEW: User-defined alias (unique per project)
└── timestamps
```

---

## Implementation Tasks

### 7.5.1 Infrastructure Base

#### 7.5.1.1 Shortcut System ✅ DONE
- [x] Add `shortcut` field to `sheets` table (string, nullable)
- [x] Add `shortcut` field to `flows` table (string, nullable)
- [x] Add unique index on `(project_id, shortcut)` for both tables
- [x] Validation: shortcut format (lowercase, alphanumeric, dots allowed, no spaces)
- [x] Validation: unique within each table per project
- [x] Schema validation in Sheet and Flow modules
- [x] UI: Shortcut field in sheet header (inline editable with #prefix)
- [x] UI: Shortcut field in flow header (inline editable with #prefix)

**Shortcut Format:**
```
Valid:   mc.jaime, loc.tavern, items.sword, quest-1
Invalid: MC.Jaime (uppercase), my shortcut (spaces), @mention (special chars)
```

#### 7.5.1.2 Sheet Avatar (replaces icon) ✅ DONE
- [x] Add `avatar_asset_id` field to `sheets` table (FK to assets, nullable)
- [x] Remove/deprecate `icon` field (migration to drop or keep for backwards compat)
- [x] Preload avatar asset in sheet queries
- [x] UI: Avatar display in sheet header (circular/rounded image)
- [x] UI: Avatar display in sidebar tree (small thumbnail)
- [x] UI: Click to upload/change avatar
- [x] UI: Remove avatar option (fallback to default icon or initials)
- [x] Integration with existing Assets system (asset picker or direct upload)

#### 7.5.1.3 Sheet Banner ✅ DONE
- [x] Add `banner_asset_id` field to `sheets` table (FK to assets, nullable)
- [x] Preload banner asset in sheet queries
- [x] UI: Banner display at top of sheet (like Notion)
- [x] UI: "Add cover" button when no banner
- [x] UI: Change/remove banner options
- [x] Integration with existing Assets system (direct upload via BannerUpload hook)

#### 7.5.1.4 Sheet Tabs System ✅ DONE
- [x] Refactor SheetLive.Show to support tabs
- [x] Tab 1: **Content** - Current block editor view (default)
- [x] Tab 2: **References** - Backlinks + version history (placeholder)
- [x] Tab navigation component (daisyUI tabs)
- [x] Tab state in socket assigns (URL preservation can be added later)

---

### 7.5.2 Block Variables

#### 7.5.2.1 Variable Fields
- [x] Add `is_constant` field to `blocks` table (boolean, default: false)
  - **Note:** Inverted logic — `is_constant: false` means the block IS a variable
- [x] Add `variable_name` field to `blocks` table (string, nullable)
- [x] Auto-generate `variable_name` from label on block create/update
- [x] Slugify function: "Health Points" → "health_points"
- [x] Ensure unique `variable_name` within sheet (DB constraint)
- [x] Handle name collisions: "health", "health_2", "health_3"

#### 7.5.2.2 Variable Configuration UI
- [x] Add "Use as constant" toggle in block config panel (is_constant)
- [x] Show generated variable name (read-only display)
- [ ] Show full path: `#shortcut.variable_name` or `#sheets.path.variable_name`
- [x] Visual indicator on constant blocks (green lock icon with tooltip)

#### 7.5.2.3 Variable Access Path Resolution
- [ ] Function to resolve variable path: `#mc.jaime.health` → block value
- [ ] Support shortcut-based paths: `#shortcut.variable`
- [ ] Support full paths: `#sheets.characters.jaime.health`
- [ ] Return type information with value

**Which blocks can be variables:**
| Block Type   | Can be Variable | Value Type |
|--------------|-----------------|------------|
| text         | Yes             | string     |
| rich_text    | Yes             | string (HTML) |
| number       | Yes             | number     |
| select       | Yes             | string (selected key) |
| multi_select | Yes             | array of strings |
| date         | Yes             | string (ISO date) |
| boolean      | Yes             | boolean / null (tri-state) |
| reference    | No (for now)    | - |

---

### 7.5.3 New Block Types

#### 7.5.3.1 Boolean Block ✅ DONE
- [x] Add "boolean" to block types enum
- [x] Schema: config `{label, mode}` where mode is "two_state" or "tri_state"
- [x] Schema: value `{content}` where content is `true`, `false`, or `null`
- [x] Default config: `{label: "", mode: "two_state"}`
- [x] UI (two_state): Toggle or checkbox (true/false)
- [x] UI (tri_state): Three-way toggle (true/neutral/false) with indeterminate state
- [x] Config panel: Mode selector (2 states vs 3 states)
- [x] Config panel: Custom labels for states (true_label, false_label, neutral_label)

**Tri-state UI options:**
```
Option A: Segmented control [Yes] [—] [No]
Option B: Toggle with neutral: ○ ◐ ●
Option C: Radio buttons: ○ True  ○ Neutral  ○ False
```

#### 7.5.3.2 Date Block ✅ DONE
- [x] Add "date" to block types enum
- [x] Schema: config `{label}`
- [x] Schema: value `{content}` where content is ISO date string or null
- [x] UI: Date picker
- [x] Can be variable (value type: string ISO date)

#### 7.5.3.3 Reference Block ✅ DONE
- [x] Add "reference" to block types enum
- [x] Schema: config `{label, allowed_types}` where allowed_types is ["sheet", "flow"] or subset
- [x] Schema: value `{target_type, target_id}`
- [x] UI: Select with search (combobox pattern)
- [x] Search by: name, shortcut
- [x] Display: Show target name + type icon + shortcut if exists
- [x] Validation: Target must exist and be in same project
- [x] Handle deleted targets gracefully (show "Deleted reference" state)
- [x] Config panel: Allowed types selection (checkboxes for sheets/flows)

---

### 7.5.4 Mentions System (`#`)

#### 7.5.4.1 Tiptap Mention Extension ✅ DONE
- [x] Install/configure @tiptap/extension-mention
- [x] Custom trigger character: `#` (not `@`)
- [x] Suggestion list component (dropdown with search)
- [x] Fetch suggestions from server (sheets + flows with shortcuts)
- [x] Search by: shortcut, name
- [x] Show: icon + name + shortcut (if exists)
- [x] Insert mention as custom node with target info

#### 7.5.4.2 Mention Rendering ✅ DONE
- [x] Render mentions as styled inline elements (chip/badge style)
- [ ] Click to navigate to referenced entity (deferred)
- [ ] Hover to show preview (optional, can defer)
- [ ] Handle broken references (target deleted) (deferred)

#### 7.5.4.3 Server Integration ✅ DONE
- [x] LiveView event handler for Tiptap to fetch suggestions (mention_suggestions)
- [x] Returns: `[{type, id, name, shortcut, label}]`
- [ ] Extract mentions from saved content for backlinks tracking (deferred to Task 13)

---

### 7.5.5 Version Control

#### 7.5.5.1 Database Schema ✅ DONE
- [x] Create `sheet_versions` table (migration)
- [x] Indexes on `(sheet_id, version_number)` and `(sheet_id, inserted_at)`
- [x] Unique constraint on `(sheet_id, version_number)`

#### 7.5.5.2 Snapshot Creation ✅ DONE
- [x] Function: `Sheets.create_version/2` - creates snapshot of current sheet state
- [x] Auto-generate change summary by diffing with previous version
- [x] Snapshot includes: name, avatar, shortcut, banner, all blocks with values
- [x] Functions: `Sheets.list_versions/2`, `Sheets.get_version/2`, `Sheets.get_latest_version/1`, `Sheets.count_versions/1`

#### 7.5.5.3 Automatic Versioning Triggers ✅ DONE
- [ ] Create version after 60 seconds of inactivity (debounced) - deferred
- [x] Create version on significant changes:
  - Block added or deleted
  - Sheet name changed
  - Shortcut changed
- [x] Rate limit: max 1 version per 5 minutes per sheet
- [ ] GenServer or Process to handle debouncing per sheet - deferred (using simple rate limit instead)

#### 7.5.5.4 Version History UI (References Tab) ✅ DONE
- [x] List of versions with: version number, date, author, summary
- [ ] Click to view version (read-only sheet view) - deferred
- [ ] Compare two versions (diff view) - deferred
- [x] Restore version button (restores sheet metadata, creates new version)

#### 7.5.5.5 Retention Policy
- [ ] Config: max versions per sheet (default: 50)
- [ ] Config: max age (default: 30 days)
- [ ] Background job to clean old versions
- [ ] Keep at least N versions regardless of age

---

### 7.5.6 Soft Delete (Trash)

#### 7.5.6.1 Sheets Soft Delete
- [x] Add `deleted_at` field to `sheets` table
- [x] Update queries to exclude deleted sheets by default
- [x] "Move to trash" instead of hard delete (context functions)
- [x] Trash view: list deleted sheets with restore/permanent delete options
- [ ] Auto-purge after 30 days (background job)

#### 7.5.6.2 Blocks Soft Delete
- [x] Add `deleted_at` field to `blocks` table
- [x] Update block queries to exclude deleted blocks
- [ ] Track deleted blocks in sheet version history
- [ ] Option to restore individual blocks from version history

---

### 7.5.7 Backlinks (References Tab)

#### 7.5.7.1 Reference Tracking ✅ DONE
- [x] Create `entity_references` table (migration)
- [x] Extract references when saving:
  - From rich_text blocks (mentions)
  - From reference blocks
  - [ ] From flow node speaker field (deferred)
  - [ ] From flow connection conditions (future)
- [x] Update references atomically with content saves
- [x] Handle reference cleanup when source is deleted

#### 7.5.7.2 Backlinks UI (References Tab) ✅ DONE
- [x] Query: "What references this sheet?"
- [x] Show: source name, context (which block/field)
- [x] Empty state when no references
- [ ] Click to navigate to source (requires route context, deferred)

---

### 7.5.8 Property Inheritance ✅ DONE

Blocks with `scope: "children"` automatically cascade to descendant sheets.

#### 7.5.8.1 Schema
- [x] Add `scope` field to blocks ("self" | "children", default: "self")
- [x] Add `inherited_from_block_id` FK to blocks (points to parent block)
- [x] Add `detached` boolean to blocks (detached from parent definition)
- [x] Add `required` boolean to blocks (required field flag)
- [x] Add `hidden_inherited_block_ids` array to sheets (hidden ancestor blocks)

#### 7.5.8.2 PropertyInheritance Module
- [x] `resolve_inherited_blocks/1` — returns inherited blocks grouped by source sheet
- [x] `create_inherited_instances/2` — creates block instances on child sheets
- [x] `propagate_to_descendants/2` — bulk creates instances for selected descendants
- [x] `sync_definition_change/1` — syncs config/type changes to non-detached instances
- [x] `detach_block/1` — makes inherited block independent (keeps provenance)
- [x] `reattach_block/1` — re-syncs previously detached block
- [x] `hide_for_children/2` — hides ancestor block from cascading
- [x] `unhide_for_children/2` — unhides ancestor block
- [x] `delete_inherited_instances/1` — soft-deletes instances when parent deleted
- [x] `restore_inherited_instances/1` — restores deleted instances
- [x] Variable names auto-deduplicated per sheet on inheritance

#### 7.5.8.3 UI
- [x] Inherited blocks grouped by source sheet with "Inherited from" header
- [x] Scope indicator (arrow-down icon) for blocks with `scope: "children"`
- [x] Context menu: Go to source, Detach, Hide for children
- [x] Drag handle hidden for inherited blocks
- [x] Propagation modal when changing scope to "children" on existing descendants

---

### 7.5.9 Column Layout ✅ DONE

Blocks can be arranged side-by-side in 2-3 column groups.

#### 7.5.9.1 Schema
- [x] Add `column_group_id` (UUID) to blocks — shared by blocks in same group
- [x] Add `column_index` (integer 0-2) to blocks — position within group

#### 7.5.9.2 Operations
- [x] `reorder_blocks_with_columns/2` — reorder with column layout info
- [x] `create_column_group/2` — group blocks side-by-side (min 2, max 3)
- [x] `dissolve_column_group/2` — reset blocks to full-width
- [x] Auto-dissolve when deletion leaves fewer than 2 blocks in group

#### 7.5.9.3 UI
- [x] ColumnSortable hook (two-tier SortableJS: vertical + horizontal)
- [x] Drag to right edge of block to create column group
- [x] Drop indicator CSS for column creation
- [x] Responsive: columns stack on mobile

---

### 7.5.10 Sheet Color ✅ DONE

- [x] Add `color` field to sheets (hex string, nullable)
- [x] Validation: `#fff`, `#3b82f6`, or `#3b82f680` (3, 6, or 8 hex chars)
- [x] Figma-style color picker dropdown in sheet editor
- [x] Color displayed in sidebar tree

---

## UI/UX Specifications

### Sheet Layout (After)

```
┌─────────────────────────────────────────────────────────────┐
│ [Banner Image - optional, full width]                       │
├─────────────────────────────────────────────────────────────┤
│ [Avatar]  Sheet Name                      [⚙️ Settings]     │
│   🖼️      Shortcut: #mc.jaime                               │
├─────────────────────────────────────────────────────────────┤
│ [Content] [References]                    ← Tabs            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ Content Tab:                                                │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ [drag] Name ────────────────── [Jaime] ────── [⚙️][🗑️] │ │ ← text block
│ │ [drag] Health ─────────────── [100] ────────── [⚙️][🗑️] │ │ ← number block (variable ✓)
│ │ [drag] Is Alive ───────────── [✓] ─────────── [⚙️][🗑️] │ │ ← boolean block (variable ✓)
│ │ [drag] Location ───────────── [Tavern ▼] ──── [⚙️][🗑️] │ │ ← reference block
│ │                                                         │ │
│ │ Type / to add a block...                                │ │
│ └─────────────────────────────────────────────────────────┘ │
│                                                             │
│ References Tab:                                             │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ BACKLINKS                                               │ │
│ │ ├─ 📄 Quest: Find Jaime (mentions in description)       │ │
│ │ ├─ 🔀 Chapter 1 Flow (speaker in 3 nodes)               │ │
│ │ └─ 📄 Tavern (location reference)                       │ │
│ │                                                         │ │
│ │ VERSION HISTORY                                         │ │
│ │ ├─ v12 - Feb 2, 10:30 - You - "Modified health"         │ │
│ │ ├─ v11 - Feb 2, 09:15 - You - "Added avatar"            │ │
│ │ └─ v10 - Feb 1, 18:45 - You - "Initial creation"        │ │
│ └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### Block with Variable Indicator

```
┌──────────────────────────────────────────────────────────────┐
│ [≡] Health ──────────────────── [100] ──────────── [⚙️][🗑️] │
│     ⚡ #mc.jaime.health                      ← variable path │
└──────────────────────────────────────────────────────────────┘
```

### Mention Autocomplete (in Tiptap)

```
User types: "Talk to #ja"

┌─────────────────────────┐
│ 📄 Jaime    #mc.jaime   │ ← shortcut match
│ 📄 James    #npc.james  │
│ 📄 Jar Shop             │ ← name match
└─────────────────────────┘
```

---

## Database Migrations

### Migration 1: Shortcuts
```elixir
alter table(:sheets) do
  add :shortcut, :string
end

alter table(:flows) do
  add :shortcut, :string
end

create unique_index(:sheets, [:project_id, :shortcut],
  where: "shortcut IS NOT NULL", name: :sheets_project_shortcut_unique)
create unique_index(:flows, [:project_id, :shortcut],
  where: "shortcut IS NOT NULL", name: :flows_project_shortcut_unique)
```

### Migration 2: Sheet Avatar & Banner
```elixir
alter table(:sheets) do
  add :avatar_asset_id, references(:assets, on_delete: :nilify_all)
  add :banner_asset_id, references(:assets, on_delete: :nilify_all)
  # Optionally remove icon field or keep for migration period
  # remove :icon
end
```

### Migration 3: Block Variables
```elixir
alter table(:blocks) do
  add :is_constant, :boolean, default: false  # inverted: false = IS a variable
  add :variable_name, :string
end

create unique_index(:blocks, [:sheet_id, :variable_name],
  where: "variable_name IS NOT NULL", name: :blocks_sheet_variable_unique)
```

### Migration 4: Sheet Versions
```elixir
create table(:sheet_versions) do
  add :sheet_id, references(:sheets, on_delete: :delete_all), null: false
  add :version_number, :integer, null: false
  add :snapshot, :map, null: false
  add :changed_by_id, references(:users, on_delete: :nilify_all)
  add :change_summary, :string

  timestamps(updated_at: false)
end

create index(:sheet_versions, [:sheet_id, :version_number])
create index(:sheet_versions, [:sheet_id, :inserted_at])
```

### Migration 5: Entity References
```elixir
create table(:entity_references) do
  add :source_type, :string, null: false
  add :source_id, :bigint, null: false
  add :target_type, :string, null: false
  add :target_id, :bigint, null: false
  add :context, :string

  timestamps()
end

create index(:entity_references, [:target_type, :target_id])
create index(:entity_references, [:source_type, :source_id])
create unique_index(:entity_references,
  [:source_type, :source_id, :target_type, :target_id, :context],
  name: :entity_references_unique)
```

### Migration 6: Soft Delete
```elixir
alter table(:sheets) do
  add :deleted_at, :utc_datetime
end

alter table(:blocks) do
  add :deleted_at, :utc_datetime
end

create index(:sheets, [:deleted_at])
create index(:blocks, [:deleted_at])
```

### Migration 7: Block Inheritance Fields
```elixir
alter table(:blocks) do
  add :scope, :string, default: "self"
  add :inherited_from_block_id, references(:blocks, on_delete: :nilify_all)
  add :detached, :boolean, default: false
  add :required, :boolean, default: false
end

alter table(:sheets) do
  add :hidden_inherited_block_ids, {:array, :integer}, default: []
end
```

### Migration 8: Block Column Layout Fields
```elixir
alter table(:blocks) do
  add :column_group_id, :uuid
  add :column_index, :integer, default: 0
end

create index(:blocks, [:sheet_id, :column_group_id],
  where: "column_group_id IS NOT NULL",
  name: :blocks_sheet_column_group_index)
```

---

## Implementation Order

Recommended order to minimize dependencies and allow incremental testing:

| Order | Task                                           | Dependencies              | Testable Outcome             |
|-------|------------------------------------------------|---------------------------|------------------------------|
| 1     | ✅ Boolean block                                | None                      | New block type works         |
| 2     | ✅ Date block                                   | None                      | Date picker works            |
| 3     | ✅ Sheet avatar (replace icon)                  | Assets system             | Avatar upload/display works  |
| 4     | ✅ Sheet banner                                 | Assets system             | Banner display works         |
| 5     | ✅ Sheet color                                  | None                      | Color picker works           |
| 6     | ✅ Soft delete                                  | None                      | Trash/restore works          |
| 7     | ✅ Block variables (is_constant, variable_name) | None                      | Variables marked correctly   |
| 8     | ✅ Shortcuts (sheets)                           | None                      | Shortcuts validated/saved    |
| 9     | ✅ Shortcuts (flows)                            | None                      | Flow shortcuts work          |
| 10    | ✅ Sheet tabs UI                                | None                      | Tab navigation works         |
| 11    | ✅ Sheet versions                               | None                      | Versions created/listed      |
| 12    | ✅ Version history UI                           | Sheet versions            | History tab works            |
| 13    | ✅ Reference block                              | Shortcuts                 | Can reference sheets/flows   |
| 14    | ✅ Mentions (Tiptap)                            | Shortcuts                 | # mentions work in rich_text |
| 15    | ✅ Entity references table                      | Mentions, Reference block | References tracked           |
| 16    | ✅ Backlinks UI                                 | Entity references         | Backlinks displayed          |
| 17    | ✅ Property inheritance                         | Tree structure            | Blocks cascade to children   |
| 18    | ✅ Column layout                                | None                      | Blocks side-by-side          |

---

## Testing Strategy

### Unit Tests
- [ ] Shortcut validation (format, uniqueness)
- [ ] Variable name generation (slugify, uniqueness)
- [ ] Version snapshot creation
- [ ] Change summary generation
- [ ] Reference extraction from rich_text
- [ ] Backlinks queries
- [ ] Property inheritance (create, detach, reattach, sync, hide/unhide)
- [ ] Column layout (create group, dissolve, auto-dissolve on delete)

### Integration Tests
- [ ] Boolean block CRUD
- [ ] Date block CRUD
- [ ] Sheet avatar upload and display
- [ ] Sheet banner upload and display
- [ ] Sheet color picker
- [ ] Reference block with search
- [ ] Sheet versioning flow
- [ ] Soft delete and restore
- [ ] Mention insertion and rendering
- [ ] Inherited blocks cascade to child sheets
- [ ] Column group creation and reordering

### E2E Tests
- [ ] Create sheet with new block types (boolean, date, reference)
- [ ] Upload sheet avatar and banner
- [ ] Set up shortcut and use in mention
- [ ] View backlinks
- [ ] Restore from version history
- [ ] Create parent sheet with children scope blocks, verify cascade
- [ ] Drag blocks into column layout

---

## Open Questions

1. **Cross-project references:** Should references work across projects? (Recommend: No, keep isolated)

2. **Shortcut conflicts:** When a shortcut is taken, should we suggest alternatives? (e.g., "mc.jaime-2")

3. **Version comparison:** Full diff view or just "restore this version"? (Recommend: Start with restore only)

4. **Mention preview on hover:** Worth the complexity? (Recommend: Defer to later)

---

## Success Criteria

- [x] New block types working (boolean, date, reference)
- [x] Sheet avatar working (replaces icon field)
- [x] Sheet banner working
- [x] Sheet color picker working
- [x] Shortcuts can be set on sheets and flows
- [x] Mentions with `#` work in rich_text blocks
- [x] Backlinks show what references a sheet
- [x] Version history accessible in References tab
- [x] Soft delete with trash recovery working
- [x] Property inheritance cascades blocks to child sheets
- [x] Column layout allows blocks side-by-side

---

*This plan will be incorporated into IMPLEMENTATION_PLAN.md once approved and implementation begins.*