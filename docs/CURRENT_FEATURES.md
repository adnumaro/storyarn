# Storyarn — Current Features

> **Last updated:** 2026-02-16
> **Stack:** Elixir 1.15+ / Phoenix 1.8 / LiveView 1.1 / PostgreSQL / Redis / Tailwind v4 / daisyUI

---

## Table of Contents

1. [Platform](#1-platform)
2. [Sheets](#2-sheets)
3. [Flows](#3-flows)
4. [Screenplay](#4-screenplay)
5. [Assets](#5-assets)

---

## 1. Platform

### 1.1 Authentication

- **Email registration** — passwordless by default; magic link sent to confirm account
- **Magic link login** — one-time token URL delivered by email; works for both new (confirms account) and existing users
- **Password login** — email + password with "Stay logged in" option (`remember_me`)
- **OAuth providers** — GitHub, Google, Discord; auto-confirms account on first use
- **Account linking** — connect/disconnect OAuth providers from an existing account; blocks unlink if it's the last auth method and no password is set
- **Rate limiting** — 5 login attempts/min/IP, 3 magic links/min/email, 3 registrations/min/IP (Hammer, ETS in dev, Redis in prod)
- **Sudo mode** — sensitive settings require re-authentication within the last 20 minutes

### 1.2 User Profile

- **Display name** (max 100 chars) and **avatar URL** (HTTPS only)
- **Email change** via confirmation link to new address (requires sudo mode)
- **Password change** with session re-creation (invalidates all other sessions)
- **Connected accounts** page — shows linked OAuth providers with connect/unlink actions

### 1.3 Workspaces

- **CRUD** — create, rename, describe, delete (owner only; cascades to all projects)
- **Auto-created on registration** — default workspace named `"{name}'s workspace"`
- **Slug** — auto-generated, globally unique, lowercase alphanumeric + hyphens
- **Banner URL** and **color** customization
- **Four roles** — owner, admin, member, viewer
  - Owner: full control
  - Admin: manage members, create projects
  - Member: create projects, view
  - Viewer: view only
- **Invitation system** — email invitations with role, 7-day expiry, hashed tokens; rate limited (10/hour/user/workspace)
- **Members management** — list members, change roles (owner-restricted), remove members (with confirm modal)

### 1.4 Projects

- **CRUD** — create (with auto-generated slug), rename, describe, delete (owner only, with confirm modal)
- **Three roles** — owner, editor, viewer
  - Owner: manage project + members + settings
  - Editor: edit content (sheets, flows, screenplays, assets)
  - Viewer: read-only access
- **Authorization cascade** — if no direct project membership, workspace role is inherited (admin/member → edit_content capability)
- **Invitation system** — same pattern as workspaces; email invitations with editor/viewer role, 7-day expiry
- **Project settings** — details, team members, pending invitations, maintenance (repair variable references), danger zone (delete)
- **Trash** — soft-deleted sheets listed with restore / permanent delete / empty trash actions; "kept for 30 days" retention note

### 1.5 Navigation & Layout

- **Five independent layouts:** app (sidebar), project (tool sidebar), auth (centered), public (landing), settings (nav sidebar)
- **Workspace sidebar** — fixed sidebar with workspace list, colored dot indicators, "New workspace" button, user dropdown with avatar/initials
- **Project sidebar** — tools section (Flows, Screenplays, Sheets, Assets), dynamic tree section (switches based on active tool), trash + settings links
- **Tree components** — hierarchical navigation for sheets, flows, and screenplays with drag-and-drop reordering
- **Theme toggle** — light/dark mode in all layouts
- **User dropdown** — display name, email, links to Profile/Preferences, dark mode toggle (keyboard shortcut `D`), logout

### 1.6 Collaboration (Real-Time)

- **Presence** — Phoenix Presence tracks online users per flow; avatar ring with tooltip in header; join/leave toast notifications
- **Cursor tracking** — real-time mouse cursor positions broadcast via PubSub (50ms throttle); colored SVG cursors with username labels; fade to 30% opacity after 3s inactivity
- **Node locking** — ETS-backed GenServer; 30-second auto-expiry; lock on node selection, release on deselect; lock indicator badge on locked nodes; prevents editing/deleting nodes locked by others
- **Remote changes** — node add/move/delete/restore and connection add/delete broadcast to all collaborators; toast notifications for remote actions
- **User colors** — deterministic 12-color palette based on user ID

### 1.7 Internationalization

- **Gettext** — all user-facing text externalized
- **Locales** — `en` (default), `es`
- **Translation domains** — `default` (UI), `errors` (validation), `emails` (notifications)
- **Locale plug** — sets locale on every request

### 1.8 Email Notifications

- **Magic link / confirmation** — one-time login and account confirmation links
- **Email change** — confirmation link to new address
- **Workspace invitation** — localized email with workspace name, inviter, role, acceptance URL, expiry
- **Project invitation** — same pattern with project details
- **Configurable sender** — name + email via application config

### 1.9 Security

- Bcrypt password hashing
- Hashed tokens in DB (raw tokens never stored)
- CSRF protection on all forms
- Content Security Policy header on all browser routes
- Sudo mode for sensitive settings
- Session fixation protection
- Rate limiting on registration, login, and invitations
- Defense in depth — authorization checked in both UI rendering and event handlers
- Cannot unlink last auth method

---

## 2. Sheets

### 2.1 Core Data Model

- **Name** (1–200 chars), **shortcut** (unique per project, format: `^[a-z0-9][a-z0-9.\-]*[a-z0-9]$`), **description** (rich text), **color** (hex), **position** (sibling order)
- **Tree structure** — self-referential `parent_id`; root sheets and nested children
- **Soft delete** — `deleted_at` timestamp; trash, restore, permanent delete
- **Associations** — project, parent/children, blocks, versions, avatar asset, banner asset

### 2.2 Blocks (Fields as Variables)

Nine block types:

| Type | Variable-capable | Config | Value |
|------|:---:|---|---|
| `text` | Yes | label, placeholder | string content |
| `rich_text` | Yes | label | HTML content (TipTap with `@mentions`) |
| `number` | Yes | label, placeholder | numeric content |
| `select` | Yes | label, placeholder, options `[{key, value}]` | selected key |
| `multi_select` | Yes | label, placeholder, options `[{key, value}]` | array of keys |
| `boolean` | Yes | label, mode (`two_state`) | true/false/nil |
| `date` | Yes | label | date value |
| `divider` | No | — | — |
| `reference` | No | label, allowed_types `["sheet","flow"]` | target_type + target_id |

- **Variable exposure** — blocks are variables unless type is `divider`/`reference` OR `is_constant: true`
- **Variable name** — auto-generated from label via slugify (e.g., "Health Points" → `health_points`); unique per sheet (suffixed `_2`, `_3` on collision)
- **Variable reference format** — `{sheet_shortcut}.{variable_name}` (e.g., `mc.jaime.health`)
- **Scope** — `self` (block stays on this sheet) or `children` (cascades to all descendants)
- **Required flag** — marks inherited blocks as mandatory for child sheets
- **Drag-and-drop reordering** via JS hook
- **Column layout** — blocks can be grouped into 2 or 3-column layouts; groups dissolve when fewer than 2 blocks remain

### 2.3 Property Inheritance

- Blocks with `scope: "children"` automatically cascade to all descendant sheets
- Each descendant gets its own instance block (`inherited_from_block_id` → source)
- **On sheet creation** — inherits all `scope: "children"` blocks from ancestor chain
- **On block creation** — propagates to existing descendants (with selection modal for which descendants to include)
- **On sheet move** — recalculates entire inheritance (removes old instances, creates new ones for new ancestor chain)
- **Config sync** — updating a parent block's config syncs to all non-detached instances; type change clears instance values
- **Detach** — marks an inherited instance as independent (stops syncing); provenance preserved
- **Reattach** — re-syncs config from source, re-enables syncing
- **Hide for children** — stops a specific ancestor block from cascading to a sheet's children (without deleting existing instances)
- **UI display** — inherited blocks shown with blue left border, grouped by source sheet with "Inherited from [Sheet]" headers and navigation links

### 2.4 Versioning (History)

- **Manual version creation** — optional title + description; auto-generated change summary (e.g., "Added 2 blocks, Modified 1 block")
- **Rate-limited auto-versioning** — `maybe_create_version` enforces 5-minute minimum interval between auto-snapshots
- **Full snapshot** — captures name, shortcut, avatar, banner, all blocks (type, position, config, value, constants, variables, scope, inheritance, column layout)
- **Version list** — paginated (20/page), version number badge, title/summary, author, date, "Current" badge
- **Restore** — applies snapshot: updates metadata, deletes all current blocks, recreates from snapshot
- **Delete** — removes version; clears `current_version_id` if it was the current
- **Set as current** — marks a version as the active reference point

### 2.5 Tabs

**Content Tab:**
- Inherited properties section (grouped by source sheet)
- Own properties section with drag-and-drop reordering
- Add block type picker with scope selector
- Per-block configuration panel (label, placeholder, options, constant toggle, required toggle, scope selector)
- Propagation modal for scope changes
- Children sheets section (links to child sheets)

**References Tab:**
- **Variable usage** — for each variable block: shows where it's read and written across all flows; links to flow + node; "Outdated" badge for stale references
- **Backlinks** — sheets, flows, and screenplays that reference this sheet; source type icons, deep-links to source (including `?element=id` for screenplays)

**Audio Tab:**
- All dialogue nodes across the project where this sheet is the speaker
- Grouped by flow (sorted alphabetically)
- Per voice line: text preview (80 chars), deep-link to flow editor (`?node=id`), audio player if attached, upload/select/remove audio controls

**History Tab:**
- Version list with create, restore, delete actions
- Create version modal with title/description fields
- Confirm modals for destructive actions

### 2.6 Avatar & Banner

- **Avatar** — image asset displayed in sidebar tree, breadcrumbs, card views; upload (max 5 MB) or remove; updates reflected across all navigation
- **Banner** — cover image at top of sheet view (responsive height); upload (max 10 MB) or remove; fallback to solid color when no image; color picker embedded in banner area
- **Sheet color** — hex color applied to banner fallback, sidebar indicator, and flow node coloring (when sheet is used as speaker)

### 2.7 Shortcuts

- Auto-generated from name on creation
- Regenerated when name changes (unless manually set)
- Editable inline (contenteditable with validation)
- Unique per project (enforced at DB level)
- Used as variable reference prefix: `{shortcut}.{variable_name}`

### 2.8 Other Features

- **Inline editable title** — contenteditable h1, saves on blur/enter, triggers version creation
- **Inline editable shortcut** — contenteditable span with `#` prefix, format validation, uniqueness check
- **Save status indicator** — :idle / :saved states, auto-resets after 4 seconds
- **Search** — ILIKE search on name and shortcut; used for `@mention` autocomplete, reference block pickers, speaker selection
- **Tree operations** — create, move (with cycle prevention), delete, reorder via drag-and-drop

---

## 3. Flows

### 3.1 Core Data Model

- **Name** (max 200 chars), **shortcut** (project-unique, same format as sheets), **description** (max 2000, rich text), **position**, **settings** (JSON map)
- **Tree structure** — `parent_id` self-referential; flows can have children AND content (not mutually exclusive)
- **Main flow** — one per project, shown with "Main" badge
- **Soft delete** — with trash, restore, permanent delete

### 3.2 Node Types

**Entry** — auto-created, one per flow (cannot delete or duplicate); green Play icon; no inputs, 1 output; shows referencing flows (subflow/exit nodes from other flows)

**Exit** — at least one required per flow; Square icon; 1 input, no outputs (terminal); three exit modes:
- `terminal` — flow ends here
- `flow_reference` — routes to another flow (circular reference detection)
- `caller_return` — returns to caller subflow
- **Outcome tags** — tag-based classification with project-wide autocomplete; displayed inline on node (first 3 + overflow)
- **Outcome color** — custom hex color for node fill
- **Technical ID** — auto-generatable: `{flow_slug}_{label}_{exit_count}`

**Dialogue** — blue MessageSquare icon (or speaker's sheet color); 1 input, dynamic outputs (one per response or single "output"); data:
- **Speaker** — links to a sheet; node takes sheet's color; avatar shown in header
- **Text** — rich HTML via TipTap with `@mention` support for sheets/flows
- **Stage directions** — plain text, italic/mono styling
- **Menu text** — for game UI context
- **Audio** — asset attachment; 🔊 indicator on node canvas
- **Technical ID** — auto-generatable: `{flow_slug}_{speaker}_{n}`
- **Localization ID** — auto-generated on create (`dialogue.{hex}`), regenerated on duplicate
- **Responses** — ordered list of `{id, text, condition, instruction}`; `[?]` badge on response pin when condition is set; connections auto-migrate when first response added or last removed

**Condition** — amber GitBranch icon; 1 input, dynamic outputs; two modes:
- **Standard** — 2 outputs: true + false; logic: ALL (AND) or ANY (OR)
- **Switch** — N outputs (one per rule with label) + default; toggleable from sidebar
- **Rule structure** — sheet, variable, operator, value; operators vary by block type (text: equals/contains/starts_with/etc., number: comparison operators, boolean: is_true/is_false/is_nil, select: equals/not_equals/is_nil, multi_select: contains/not_contains/is_empty, date: equals/before/after)
- **Stale reference detection** — warning icon when referenced variable is deleted or renamed

**Instruction** — green Zap icon; 1 input, 1 output (pass-through); assignment list with operators:
- `number`: set, add, subtract
- `boolean`: set_true, set_false, toggle
- `text/rich_text`: set, clear
- `select/multi_select/date`: set
- **Value types** — literal (typed value) or variable reference (references another variable)
- **Stale reference detection** — warning icon when referenced variable is stale

**Hub** — purple LogIn icon (or custom color); 1 input, 1 output; named anchor point:
- **Hub ID** — unique within flow, auto-generated if blank
- **Label** and **color** (hex)
- Hub ID rename cascades to all referencing jump nodes
- Hub deletion clears references on jumps (with warning flash)
- Canvas shows jump count nav link (zooms to all referencing jumps)

**Jump** — purple LogOut icon (inherits hub's color); 1 input, no outputs (terminal on canvas):
- **Target hub** — dropdown of all hubs in flow
- Canvas shows hub label as nav link (click zooms to hub)
- Error badge if no target set

**Scene** — cyan Clapperboard icon (or location sheet color); 1 input, 1 output (pass-through):
- **Location** — links to a sheet as the location
- **INT/EXT** — `int`, `ext`, `int_ext`, `ext_int`
- **Sub-location** (e.g., "MAIN LOBBY") and **time of day** (e.g., "NIGHT")
- **Description** — preview text
- **Technical ID** — auto-generatable
- Canvas shows slug line formatted as `"INT. MAIN LOBBY - NIGHT"` in bold uppercase

**Subflow** — indigo Box icon; 1 input, dynamic outputs (one per exit in referenced flow, excluding `flow_reference` exits):
- **Referenced flow** — picker with circular reference detection and self-reference prevention
- Dynamic output pins named `exit_{id}` with labels
- Canvas shows nav link with flow name + shortcut
- **Stale detection** — when referenced flow is deleted
- Double-click navigates to referenced flow

### 3.3 Connection System

- Connections store source/target node + source/target pin names + optional label
- **Validation** — no self-connections; exit/jump nodes have no outputs; entry nodes have no inputs; unique pin-pair constraint at DB level
- **Response pin migration** — adding first response migrates "output" connection; removing last migrates back

### 3.4 Canvas

- **Rete.js** graph engine with Lit (Shadow DOM) rendering
- **Zoom & pan** — mouse wheel zoom, drag to pan, fit-view on load
- **Grid** — radial dot background (24px spacing)
- **Minimap** — 200px plugin, registered after initial load to avoid per-node overhead
- **Level of Detail (LOD)** — two tiers: `full` (zoom > 0.45) and `simplified` (zoom < 0.40); hysteresis band prevents flicker; batched DOM updates (50 nodes/frame)
- **Node selection** — click to select + open sidebar; Ctrl+Click for multi-select
- **Node creation** — "Add Node" dropdown in header; all types except entry; random offset positioning
- **Node movement** — drag with 300ms debounced position save
- **Node duplication** — Ctrl/Cmd+D; per-type data cleanup (clears technical IDs, generates new localization IDs, etc.); +50px offset
- **Node deletion** — Delete/Backspace key; cannot delete entry or last exit; soft-delete with connection cascade; lock check
- **Performance** — deferred flow load (spinner overlay → async fetch), 3-phase bulk load (nodes → sockets → connections), LOD system, node update queue, debounced position push

### 3.5 Undo/Redo

- Rete.js History plugin with custom action types:
  - **DragAction** — tracks position changes; coalesces rapid drags on same node
  - **AddConnectionAction** / **RemoveConnectionAction** — undo/redo connection operations
  - **DeleteNodeAction** — undo restores node server-side; redo re-deletes
- History cleared on full flow refresh
- Not recorded during server bulk loads
- **Keyboard** — Ctrl/Cmd+Z (undo), Ctrl/Cmd+Y or Ctrl/Cmd+Shift+Z (redo)

### 3.6 Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Ctrl/Cmd+Z | Undo |
| Ctrl/Cmd+Y / Ctrl/Cmd+Shift+Z | Redo |
| Delete / Backspace | Delete selected node |
| Ctrl/Cmd+D | Duplicate selected node |
| Escape | Deselect node |
| Ctrl/Cmd+Shift+D | Toggle debug mode |
| F10 | Debug: step forward |
| F9 | Debug: step back |
| F5 | Debug: toggle auto-play/pause |
| F6 | Debug: reset |

### 3.7 Properties Panel (Sidebar)

- Opens on node selection (right panel)
- Per-type configuration sections (collapsible accordions)
- **Dialogue** — speaker select, stage directions, rich text editor, responses (add/remove/reorder with condition + instruction per response), menu text, audio picker, technical ID + localization ID, word count
- **Condition** — condition builder with logic selector, rule rows (variable picker, operator, value); switch mode toggle
- **Instruction** — description, assignment builder (variable, operator, value/variable-ref)
- **Hub** — hub ID, label, color picker, referencing jumps list
- **Jump** — target hub dropdown, navigate-to-hub button
- **Exit** — label, technical ID, exit mode radio, flow reference picker, outcome tags, outcome color picker, referencing flows
- **Scene** — location sheet picker, INT/EXT, sub-location, time of day, description, technical ID
- **Entry** — referencing flows list
- **Subflow** — flow reference picker, exit nodes list, navigate button

### 3.8 Debug Mode

**Session:**
- Toggle with "Debug" button or Ctrl/Cmd+Shift+D
- Session persisted across cross-flow navigation via ETS-backed store
- Resizable docked panel at bottom (drag handle, default 280px)

**Engine:**
- Pure functional evaluator — no DB access during execution
- Variables initialized from all project variables
- Step statuses: paused → ok → waiting_input → finished | error
- Cross-flow navigation: flow_jump (enter subflow) + flow_return (return to caller)
- Full state snapshot history for step-back
- Breakpoints per node (MapSet); auto-pause on breakpoint during auto-play

**Controls:**
- Play/Pause (auto-step at configurable speed: 200ms–3000ms)
- Step Forward / Step Back (via state snapshots)
- Reset / Stop
- Speed slider
- Start node selector

**Panel Tabs:**
1. **Console** — timestamped log entries (info/warning/error), response choices when waiting for input
2. **Variables** — filterable table with variable key, type, initial/previous/current values; inline editing (click to edit, type-aware inputs); "Changed Only" filter; color-coded by source (instruction=amber, user_override=blue)
3. **History** — timeline of variable changes (timestamp, node, old→new, source badge)
4. **Path** — execution path with step numbers, depth-indented for subflows, breakpoint dots, node type icons, outcome labels, flow separator bars

**Canvas Visual Feedback:**
- Pulsing highlight on active node
- Amber pulse when waiting for input
- Red indicator on error
- Subtle border on visited nodes
- Red dot on breakpoint nodes
- Animated dashed stroke on active connection; faded stroke on visited
- Auto-scroll (zoom-to-fit) on each step

### 3.9 Preview Mode

- Modal dialogue preview walking through connected nodes from a selected start
- Shows speaker avatar/initials, dialogue text (HTML sanitized), response buttons (condition badge)
- Max traversal depth: 50
- Auto-advances on single-output nodes

### 3.10 Cross-Flow Navigation

- Breadcrumb "Flows" link; "Back to {flow}" button when navigated via `?from=` param
- Subflow double-click navigates with `?from=` param for return
- Exit flow_reference navigates to target flow
- Entry shows referencing flows (clickable navigation)
- Hub ↔ Jump bidirectional zoom-and-highlight navigation
- Navigate-to-node from URL `?node=id` (zoom + select)

### 3.11 Variable Reference Tracking

- Tracks which flow nodes reference which sheet variables (by block_id)
- Updated on every node data change
- **Stale detection** — identifies nodes with references to deleted/renamed variables
- Canvas display — triangle-alert icon on stale condition/instruction nodes
- **Repair tool** — bulk-fixes stale references across all project flows (available in project settings)

### 3.12 Other Features

- **Inline editable title** — contenteditable h1, saves on blur/enter
- **Inline editable shortcut** — contenteditable span with validation
- **Save status indicator** — idle / saved states
- **Main flow** — one per project, set/unset via `set_main_flow`
- **Tree operations** — create, move, reorder, create child flow
- **Flow serialization** — resolves hub colors, subflow names/exits, exit references, entry referencing flows, stale ref flags for JS canvas

---

## 4. Screenplay

### 4.1 Two Editing Modes

**Fullscreen Dialogue Editor (flow-embedded):**
- Overlays the flow editor viewport when a dialogue node is double-clicked
- Speaker selector dropdown (all project sheets, uppercase names)
- Stage directions input (plain text, italic)
- Dialogue text via TipTap with `#mention` support
- Responses read-only preview with "Edit in sidebar" note
- Footer: speaker name, word count, Esc-to-close hint
- Keyboard: Esc closes, Tab from TipTap → stage directions focus

**Full Screenplay Editor (standalone tool):**
- Dedicated page at `/workspaces/:ws/projects/:proj/screenplays/:id`
- Single TipTap instance with industry-standard formatting
- Courier Prime monospace font
- US Letter dimensions (816px max-width), standard screenplay margins
- Dark theme support

### 4.2 Element Types

18 element types in three categories:

**Standard screenplay:**
- `scene_heading` — INT./EXT. location line (uppercase, bold)
- `action` — narrative description (default block type)
- `character` — character name (uppercase, 211px left margin)
- `dialogue` — spoken text (96px left margin, 336px max-width)
- `parenthetical` — acting direction (italic, wrapped in parens)
- `transition` — CUT TO:, FADE IN: (right-aligned; left-aligned for "IN:" endings)
- `dual_dialogue` — two-column simultaneous dialogue

**Interactive (map to flow nodes):**
- `conditional` — inline condition builder widget
- `instruction` — inline instruction builder widget
- `response` — inline response/choice list builder

**Flow navigation / utility:**
- `hub_marker` — hub reference marker
- `jump_marker` — jump target marker
- `note` — writer's note (amber border, not exported)
- `section` — outline header (bold, primary color underline)
- `page_break` — force page break (dashed line)
- `title_page` — metadata form (title, credit, author, draft_date, contact)

### 4.3 Keyboard Shortcuts & Smart Typing

| Key | Behavior |
|-----|----------|
| Enter | Split block, create next block with smart type progression (scene_heading→action, character→dialogue, dialogue→action, transition→scene_heading) |
| Tab | Cycle block type forward: action → sceneHeading → character → dialogue → parenthetical → transition |
| Shift+Tab | Cycle backward |
| Backspace (empty non-action) | Convert to action first |
| Escape | Blur editor |

### 4.4 Slash Command Palette

Type `/` in an empty block to open a filtered command menu:

*Screenplay:* Scene Heading, Action, Character, Dialogue, Parenthetical, Transition
*Interactive:* Condition, Instruction, Responses
*Utility:* Note, Section, Page Break

Keyboard navigation (Arrow Up/Down, Enter to select, Escape to close).

### 4.5 Auto-Detection

Input rules automatically convert block types as the user types:
- `INT. `, `EXT. `, `INT./EXT. `, `I/E. `, `EST. ` → scene heading
- `FADE IN:`, `FADE OUT.`, `CUT TO:`, `DISSOLVE TO:`, etc. → transition
- `(text)` in dialogue → parenthetical

### 4.6 Smart Formatting

- **CONT'D auto-badge** — decorative `(CONT'D)` appended to character blocks when the same speaker appears again without a continuation breaker (scene heading, transition, etc.)
- **Transition alignment** — auto-left-aligns transitions ending in "IN:" (e.g., `FADE IN:`); others right-aligned
- **Placeholder text** — per-type hints ("INT. LOCATION - DAY", "CHARACTER", "Dialogue...", etc.)

### 4.7 Character Sheet References

- Character blocks can link to project sheets via `sheetId` attribute
- Linked characters show `#` prefix badge with highlight background
- Cmd/Ctrl+Click navigates to linked sheet
- Auto-cleared when character block is emptied
- Search-based character assignment UI

### 4.8 Inline Mentions

- `#` trigger in any text block opens suggestion menu
- Server-side search across sheets and flows (name + shortcut)
- Rendered as `<span class="mention">` with data attributes
- Cmd/Ctrl+Click navigates to referenced entity

### 4.9 Read Mode

- Toggle via toolbar button (book-open / pencil icon)
- Hides interactive/utility blocks: conditional, instruction, response, note, hub_marker, jump_marker, title_page
- Standard screenplay blocks remain visible
- Editor set to non-editable

### 4.10 Interactive Atom Blocks

**Conditional:** inline condition builder with logic selector (ALL/ANY), rule rows (variable, operator, value), color-coded left border

**Instruction:** inline assignment builder with variable picker, operator, value; natural language rendering

**Response:** choice list builder with:
- Add/remove choices with text inputs
- Per-choice condition toggle (embedded condition builder)
- Per-choice instruction toggle (embedded instruction builder)
- Per-choice linked page (create, navigate, unlink)
- "Generate pages" button for batch page creation
- Status icons (green = all linked, yellow = some unlinked)

**Title Page:** metadata form (title, credit, author, draft_date, contact) in Courier Prime font

**Dual Dialogue:** two-column layout with character name, optional parenthetical, and dialogue per column

### 4.11 Bidirectional Flow Sync

**Screenplay → Flow (`sync_to_flow`):**
1. Loads full page tree (screenplay + linked child pages, up to depth 20)
2. Groups elements into dialogue groups and maps to flow node types
3. Diffs against existing synced nodes (create/update/delete)
4. Rebuilds connections (sequential + branch from response choices)
5. Positions nodes using tree-aware layout algorithm
6. Updates `linked_node_id` on each element

**Flow → Screenplay (`sync_from_flow`):**
1. DFS traversal from entry node to linearize the graph
2. Reverse-maps each node type to element attributes
3. Diffs existing elements (create/update/delete)
4. Preserves non-mappeable elements (note, section, page_break, title_page) with anchor-based positioning
5. Recursively syncs branching paths into linked child pages

**Link status indicators in toolbar:**
- Unlinked: "Create Flow" button
- Linked: flow name badge (clickable), "To Flow" push, "From Flow" pull, unlink
- Flow deleted: warning badge + unlink
- Flow missing: warning badge + unlink

### 4.12 Fountain Format

**Export:**
- Downloads `.fountain` file (slugified filename)
- Title page → Fountain key-value header
- Standard elements → industry-standard Fountain formatting
- HTML marks converted: `<strong>` → `**`, `<em>` → `*`
- Interactive types silently omitted
- Dual dialogue uses `^` suffix convention

**Import:**
- File picker accepting `.fountain` and `.txt`
- Parses title page, scene headings, characters, dialogue, parentheticals, transitions, actions, notes, sections, page breaks
- Detects indent profile (Final Draft export compatibility)
- Fountain marks → HTML: `***` → bold-italic, `**` → bold, `*` → italic
- Dual dialogue detected via `^` suffix
- **Auto-creates character sheets** — scans imported characters, creates project sheets, links character elements
- Replaces all existing elements on import (destructive, within transaction)

### 4.13 Page Tree (Branching Narratives)

- Screenplays organized in hierarchical tree (`parent_id`)
- Response choices can link to child screenplays for branching paths
- "Create page" / "Generate pages" creates child screenplays linked to choices
- Navigation between linked pages
- Sidebar tree with drag-and-drop reordering
- Soft-delete with restore

### 4.14 Client-Server Sync

- **Debounced 500ms** after each doc change; immediate flush on blur/destroy
- Full element list pushed as `sync_editor_content`
- Server-side: identifies removed elements (deletes), upserts changed elements, reorders, updates sheet back-references
- Interactive block data changes push `element_data_updated` back to client with `suppressedDispatch` (no loop)

### 4.15 Backlink Deep-Linking

- URL parameter `?element=<id>` scrolls to and flash-highlights the target element
- 1.5-second amber fade-out animation
- Used by sheet backlinks panel for cross-navigation

### 4.16 Other Features

- **Editable title** — contenteditable with EditableTitle hook
- **Element count badge** — "N elements" in toolbar
- **Draft status badge** — warning-colored "Draft" indicator
- **Authorization** — all mutations gated by `edit_content` permission; viewers see read-only mode

---

## 5. Assets

### 5.1 Core Data Model

- **Fields:** filename, content_type (MIME), size (bytes), key (storage path), url (public), metadata (JSON: width/height/thumbnail for images, duration for audio)
- **Associations:** belongs to project + uploaded_by user
- **Scoped to projects** — each project has its own isolated asset store
- **Unique constraint** — `(project_id, key)` prevents duplicate storage keys

### 5.2 Supported File Types

- **Images:** JPEG, PNG, GIF, WebP, SVG
- **Audio:** MP3, WAV, OGG, WebM
- **Documents:** PDF

### 5.3 Storage Backend

- **Behaviour-based** — pluggable adapter via config (`:local` or `:r2`)
- **Local adapter (dev)** — stores in `priv/static/uploads/`, served via Phoenix static plug
- **R2 adapter (production)** — Cloudflare R2 (S3-compatible) via ExAws; configurable CDN public URL; presigned upload/download URLs available
- **Key format:** `projects/{project_id}/assets/{uuid}/{sanitized_filename}`
- **Filename sanitization** — strips path components (no traversal), replaces special chars with `_`, downcased, truncated to 255 chars

### 5.4 Image Processing

- **Image library** (libvips via Vix NIF) — no system install required
- **Thumbnail generation** — 200px max dimension, JPEG output
- **Resize** — fit within 2048x2048 max
- **Dimension extraction** — width/height metadata
- **Optimization** — quality 85, metadata stripped
- Module exists and is functional; not yet wired into the web upload flow

### 5.5 Asset Library (Tool Page)

- **Route:** `/workspaces/:ws/projects/:proj/assets`
- **Filter tabs** — All, Images, Audio (with live counts refreshed on upload/delete)
- **Search** — live search by filename with 300ms debounce; case-insensitive ILIKE
- **Responsive grid** — 2→3→4 columns (collapses to 2 when detail panel open)
- **Card display** — thumbnail for images, music icon for audio, file icon for other; filename, human-readable size, type badge (color-coded)

### 5.6 Detail Panel

- Opens on card click (right side panel)
- **Preview** — `<img>` for images (max-h-48), `<audio controls>` for audio
- **Metadata** — filename, MIME type, size, upload date
- **Usage section** — all references with deep-links:
  - Flow nodes → link to flow editor
  - Sheet avatars → link to sheet with "(avatar)" label
  - Sheet banners → link to sheet with "(banner)" label
  - Total usage count badge
- **Delete** — confirm modal with context-aware message (usage count if referenced); deletes storage file + optional thumbnail + DB record
- Close button to deselect

### 5.7 Upload

- **Assets page** — `AssetUpload` hook; accepts image/* and audio/*; max 20 MB
- **Button states** — "Upload" / "Uploading..." with disabled state
- Server-side: base64 decode → MIME validation → key generation → storage upload → DB record → auto-select new asset → refresh counts

### 5.8 File Size Limits

| Context | Accepts | Max Size |
|---------|---------|----------|
| Asset library (general) | Images + Audio | 20 MB |
| Audio picker (flow editor) | Audio only | 20 MB |
| Audio tab (sheet) | Audio only | 20 MB |
| Sheet avatar | Images only | 5 MB |
| Sheet banner | Images only | 10 MB |

### 5.9 Sheet Integration

- **Avatar** (`avatar_asset_id`) — image shown in sidebar tree, breadcrumbs, card views; upload or pick from library; remove (unlinks, doesn't delete asset)
- **Banner** (`banner_asset_id`) — cover image at top of sheet; upload, change, or remove; fallback to solid color

### 5.10 Flow Integration

- **Audio on dialogue nodes** (`audio_asset_id`) — attach audio via AudioPicker component in sidebar; dropdown to select from project audio assets + upload button; 🔊 indicator on node canvas; remove (unlinks)
- **Audio tab on sheets** — centralized view of all voice lines for a character; per-node audio select/upload/remove directly from the sheet

### 5.11 Analytics

- **Count by type** — `%{"image" => N, "audio" => N}` (SQL group by MIME prefix)
- **Total storage size** — sum of all asset sizes per project (in bytes)
- **Usage tracking** — queries all references across flow nodes, sheet avatars, and sheet banners; excludes soft-deleted entities
