# Phase 7.5: Pages Enhancement

> **Goal:** Evolve Pages into a more powerful wiki-like system with variables, references, and version control
>
> **Priority:** Before Phase 7 (Export) - this defines the data model that will be exported
>
> **Last Updated:** February 3, 2026

## Overview

This phase enhances the Pages system to be more like Notion/articy:draft, adding:
- Blocks as variables (accessible from flow scripting)
- Reference system with shortcuts (`#shortcut.path`)
- Bidirectional links (backlinks)
- Page versioning and history
- New block types (boolean, reference)
- Page avatar (image upload replacing icon field)

---

## Architecture Changes

### Pages Domain Model (After)

```
pages
├── id, project_id, name, parent_id, position
├── avatar_asset_id   # REPLACES icon: Page avatar/thumbnail (FK to assets)
├── shortcut          # NEW: User-defined alias (unique per project)
├── banner_asset_id   # NEW: Optional header image (FK to assets)
└── timestamps

blocks
├── id, page_id, type, position, config, value
├── is_variable       # NEW: boolean - if true, accessible from scripting
├── variable_name     # NEW: auto-generated from label (slugified)
└── timestamps

page_versions         # NEW TABLE
├── id, page_id
├── version_number
├── snapshot (JSONB)  # {name, avatar_asset_id, shortcut, blocks: [...]}
├── changed_by_id (FK user)
├── change_summary    # Auto-generated: "Added 2 blocks, modified text"
└── created_at

entity_references     # NEW TABLE (for backlinks tracking)
├── id
├── source_type       # "page" | "flow" | "flow_node"
├── source_id
├── target_type       # "page" | "flow"
├── target_id
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
- [x] Add `shortcut` field to `pages` table (string, nullable)
- [x] Add `shortcut` field to `flows` table (string, nullable)
- [x] Add unique index on `(project_id, shortcut)` for both tables
- [x] Validation: shortcut format (lowercase, alphanumeric, dots allowed, no spaces)
- [x] Validation: unique within each table per project
- [x] Schema validation in Page and Flow modules
- [x] UI: Shortcut field in page header (inline editable with #prefix)
- [x] UI: Shortcut field in flow header (inline editable with #prefix)

**Shortcut Format:**
```
Valid:   mc.jaime, loc.tavern, items.sword, quest-1
Invalid: MC.Jaime (uppercase), my shortcut (spaces), @mention (special chars)
```

#### 7.5.1.2 Page Avatar (replaces icon) ✅ DONE
- [x] Add `avatar_asset_id` field to `pages` table (FK to assets, nullable)
- [x] Remove/deprecate `icon` field (migration to drop or keep for backwards compat)
- [x] Preload avatar asset in page queries
- [x] UI: Avatar display in page header (circular/rounded image)
- [x] UI: Avatar display in sidebar tree (small thumbnail)
- [x] UI: Click to upload/change avatar
- [x] UI: Remove avatar option (fallback to default icon or initials)
- [x] Integration with existing Assets system (asset picker or direct upload)

#### 7.5.1.3 Page Banner ✅ DONE
- [x] Add `banner_asset_id` field to `pages` table (FK to assets, nullable)
- [x] Preload banner asset in page queries
- [x] UI: Banner display at top of page (like Notion)
- [x] UI: "Add cover" button when no banner
- [x] UI: Change/remove banner options
- [x] Integration with existing Assets system (direct upload via BannerUpload hook)

#### 7.5.1.4 Page Tabs System ✅ DONE
- [x] Refactor PageLive.Show to support tabs
- [x] Tab 1: **Content** - Current block editor view (default)
- [x] Tab 2: **References** - Backlinks + version history (placeholder)
- [x] Tab navigation component (daisyUI tabs)
- [x] Tab state in socket assigns (URL preservation can be added later)

---

### 7.5.2 Block Variables

#### 7.5.2.1 Variable Fields
- [x] Add `is_constant` field to `blocks` table (boolean, default: false) - inverted logic
- [x] Add `variable_name` field to `blocks` table (string, nullable)
- [x] Auto-generate `variable_name` from label on block create/update
- [x] Slugify function: "Health Points" → "health_points"
- [x] Ensure unique `variable_name` within page (DB constraint)
- [x] Handle name collisions: "health", "health_2", "health_3"

#### 7.5.2.2 Variable Configuration UI
- [x] Add "Use as constant" toggle in block config panel (is_constant)
- [x] Show generated variable name (read-only display)
- [ ] Show full path: `#shortcut.variable_name` or `#pages.path.variable_name`
- [x] Visual indicator on constant blocks (green lock icon with tooltip)

#### 7.5.2.3 Variable Access Path Resolution
- [ ] Function to resolve variable path: `#mc.jaime.health` → block value
- [ ] Support shortcut-based paths: `#shortcut.variable`
- [ ] Support full paths: `#pages.characters.jaime.health`
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
| divider      | No              | - |
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

#### 7.5.3.2 Reference Block ✅ DONE
- [x] Add "reference" to block types enum
- [x] Schema: config `{label, allowed_types}` where allowed_types is ["page", "flow"] or subset
- [x] Schema: value `{target_type, target_id}`
- [x] UI: Select with search (combobox pattern)
- [x] Search by: name, shortcut
- [x] Display: Show target name + type icon + shortcut if exists
- [x] Validation: Target must exist and be in same project
- [x] Handle deleted targets gracefully (show "Deleted reference" state)
- [x] Config panel: Allowed types selection (checkboxes for pages/flows)

---

### 7.5.4 Mentions System (`#`)

#### 7.5.4.1 Tiptap Mention Extension
- [ ] Install/configure @tiptap/extension-mention
- [ ] Custom trigger character: `#` (not `@`)
- [ ] Suggestion list component (dropdown with search)
- [ ] Fetch suggestions from server (pages + flows with shortcuts)
- [ ] Search by: shortcut, name, path
- [ ] Show: icon + name + shortcut (if exists)
- [ ] Insert mention as custom node with target info

#### 7.5.4.2 Mention Rendering
- [ ] Render mentions as styled inline elements (chip/badge style)
- [ ] Click to navigate to referenced entity
- [ ] Hover to show preview (optional, can defer)
- [ ] Handle broken references (target deleted)

#### 7.5.4.3 Server Integration
- [ ] API endpoint for mention suggestions: `GET /api/projects/:id/mentions?q=search`
- [ ] Returns: `[{type, id, name, shortcut, path}]`
- [ ] LiveView event handler for Tiptap to fetch suggestions
- [ ] Extract mentions from saved content for backlinks tracking

---

### 7.5.5 Version Control

#### 7.5.5.1 Database Schema ✅ DONE
- [x] Create `page_versions` table (migration)
- [x] Indexes on `(page_id, version_number)` and `(page_id, inserted_at)`
- [x] Unique constraint on `(page_id, version_number)`

#### 7.5.5.2 Snapshot Creation ✅ DONE
- [x] Function: `Pages.create_version/2` - creates snapshot of current page state
- [x] Auto-generate change summary by diffing with previous version
- [x] Snapshot includes: name, avatar, shortcut, banner, all blocks with values
- [x] Functions: `list_versions/2`, `get_version/2`, `get_latest_version/1`, `count_versions/1`

#### 7.5.5.3 Automatic Versioning Triggers ✅ DONE
- [ ] Create version after 60 seconds of inactivity (debounced) - deferred
- [x] Create version on significant changes:
  - Block added or deleted
  - Page name changed
  - Shortcut changed
- [x] Rate limit: max 1 version per 5 minutes per page
- [ ] GenServer or Process to handle debouncing per page - deferred (using simple rate limit instead)

#### 7.5.5.4 Version History UI (References Tab) ✅ DONE
- [x] List of versions with: version number, date, author, summary
- [ ] Click to view version (read-only page view) - deferred
- [ ] Compare two versions (diff view) - deferred
- [x] Restore version button (restores page metadata, creates new version)

#### 7.5.5.5 Retention Policy
- [ ] Config: max versions per page (default: 50)
- [ ] Config: max age (default: 30 days)
- [ ] Background job to clean old versions
- [ ] Keep at least N versions regardless of age

---

### 7.5.6 Soft Delete (Trash)

#### 7.5.6.1 Pages Soft Delete
- [x] Add `deleted_at` field to `pages` table
- [x] Update queries to exclude deleted pages by default
- [x] "Move to trash" instead of hard delete (context functions)
- [x] Trash view: list deleted pages with restore/permanent delete options
- [ ] Auto-purge after 30 days (background job)

#### 7.5.6.2 Blocks Soft Delete
- [x] Add `deleted_at` field to `blocks` table
- [x] Update block queries to exclude deleted blocks
- [ ] Track deleted blocks in page version history
- [ ] Option to restore individual blocks from version history

---

### 7.5.7 Backlinks (References Tab)

#### 7.5.7.1 Reference Tracking
- [ ] Create `entity_references` table (migration)
- [ ] Extract references when saving:
  - From rich_text blocks (mentions)
  - From reference blocks
  - From flow node speaker field
  - From flow connection conditions (future)
- [ ] Update references atomically with content saves
- [ ] Handle reference cleanup when source is deleted

#### 7.5.7.2 Backlinks UI (References Tab)
- [ ] Query: "What references this page?"
- [ ] Group by source type (Pages, Flows)
- [ ] Show: source name, context (which block/field), link to source
- [ ] Empty state when no references

---

## UI/UX Specifications

### Page Layout (After)

```
┌─────────────────────────────────────────────────────────────┐
│ [Banner Image - optional, full width]                       │
├─────────────────────────────────────────────────────────────┤
│ [Avatar]  Page Name                       [⚙️ Settings]     │
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
alter table(:pages) do
  add :shortcut, :string
end

alter table(:flows) do
  add :shortcut, :string
end

create unique_index(:pages, [:project_id, :shortcut],
  where: "shortcut IS NOT NULL", name: :pages_project_shortcut_unique)
create unique_index(:flows, [:project_id, :shortcut],
  where: "shortcut IS NOT NULL", name: :flows_project_shortcut_unique)
```

### Migration 2: Page Avatar & Banner
```elixir
alter table(:pages) do
  add :avatar_asset_id, references(:assets, on_delete: :nilify_all)
  add :banner_asset_id, references(:assets, on_delete: :nilify_all)
  # Optionally remove icon field or keep for migration period
  # remove :icon
end
```

### Migration 3: Block Variables
```elixir
alter table(:blocks) do
  add :is_variable, :boolean, default: false
  add :variable_name, :string
end

create unique_index(:blocks, [:page_id, :variable_name],
  where: "variable_name IS NOT NULL", name: :blocks_page_variable_unique)
```

### Migration 4: Page Versions
```elixir
create table(:page_versions) do
  add :page_id, references(:pages, on_delete: :delete_all), null: false
  add :version_number, :integer, null: false
  add :snapshot, :map, null: false
  add :changed_by_id, references(:users, on_delete: :nilify_all)
  add :change_summary, :string

  timestamps(updated_at: false)
end

create index(:page_versions, [:page_id, :version_number])
create index(:page_versions, [:page_id, :inserted_at])
```

### Migration 5: Entity References
```elixir
create table(:entity_references) do
  add :source_type, :string, null: false
  add :source_id, :binary_id, null: false
  add :target_type, :string, null: false
  add :target_id, :binary_id, null: false
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
alter table(:pages) do
  add :deleted_at, :utc_datetime
end

alter table(:blocks) do
  add :deleted_at, :utc_datetime
end

create index(:pages, [:deleted_at])
create index(:blocks, [:deleted_at])
```

---

## Implementation Order

Recommended order to minimize dependencies and allow incremental testing:

| Order | Task                                           | Dependencies              | Testable Outcome             |
|-------|------------------------------------------------|---------------------------|------------------------------|
| 1     | ✅ Boolean block                                | None                      | New block type works         |
| 2     | ✅ Page avatar (replace icon)                   | Assets system             | Avatar upload/display works  |
| 3     | ✅ Page banner                                  | Assets system             | Banner display works         |
| 4     | ✅ Soft delete                                  | None                      | Trash/restore works          |
| 5     | ✅ Block variables (is_constant, variable_name) | None                      | Variables marked correctly   |
| 6     | ✅ Shortcuts (pages)                            | None                      | Shortcuts validated/saved    |
| 7     | ✅ Shortcuts (flows)                            | None                      | Flow shortcuts work          |
| 8     | ✅ Page tabs UI                                 | None                      | Tab navigation works         |
| 9     | ✅ Page versions                                | None                      | Versions created/listed      |
| 10    | ✅ Version history UI                           | Page versions             | History tab works            |
| 11    | ✅ Reference block                              | Shortcuts                 | Can reference pages/flows    |
| 12    | Mentions (Tiptap)                              | Shortcuts                 | # mentions work in rich_text |
| 13    | Entity references table                        | Mentions, Reference block | References tracked           |
| 14    | Backlinks UI                                   | Entity references         | Backlinks displayed          |

---

## Testing Strategy

### Unit Tests
- [ ] Shortcut validation (format, uniqueness)
- [ ] Variable name generation (slugify, uniqueness)
- [ ] Version snapshot creation
- [ ] Change summary generation
- [ ] Reference extraction from rich_text
- [ ] Backlinks queries

### Integration Tests
- [ ] Boolean block CRUD
- [ ] Page avatar upload and display
- [ ] Page banner upload and display
- [ ] Reference block with search
- [ ] Page versioning flow
- [ ] Soft delete and restore
- [ ] Mention insertion and rendering

### E2E Tests
- [ ] Create page with new block types (boolean, reference)
- [ ] Upload page avatar and banner
- [ ] Set up shortcut and use in mention
- [ ] View backlinks
- [ ] Restore from version history

---

## Open Questions

1. **Cross-project references:** Should references work across projects? (Recommend: No, keep isolated)

2. **Shortcut conflicts:** When a shortcut is taken, should we suggest alternatives? (e.g., "mc.jaime-2")

3. **Version comparison:** Full diff view or just "restore this version"? (Recommend: Start with restore only)

4. **Mention preview on hover:** Worth the complexity? (Recommend: Defer to later)

---

## Success Criteria

- [x] New block types working (boolean) ✅
- [x] New block types working (reference) ✅
- [x] Page avatar working (replaces icon field) ✅
- [x] Page banner working ✅
- [x] Shortcuts can be set on pages and flows ✅
- [ ] Mentions with `#` work in rich_text blocks
- [ ] Backlinks show what references a page
- [ ] Version history accessible in References tab
- [ ] Soft delete with trash recovery working

---

*This plan will be incorporated into IMPLEMENTATION_PLAN.md once approved and implementation begins.*
sog