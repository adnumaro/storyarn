# Storyarn — Current Features

> **Last updated:** 2026-02-24
> **Stack:** Elixir 1.15+ / Phoenix 1.8 / LiveView 1.1 / PostgreSQL / Redis / Tailwind v4 / daisyUI

---

## Table of Contents

1. [Platform](#1-platform)
2. [Sheets](#2-sheets)
3. [Flows](#3-flows)
4. [Screenplay](#4-screenplay)
5. [Assets](#5-assets)
6. [Scenes](#6-scenes)
7. [Localization](#7-localization)

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

- **Five independent layouts:** app (sidebar), project (tool sidebar), auth (centered), public (landing), settings (nav sidebar). The Story Player uses `layout: false` and renders its own fullscreen layout inline.
- **Workspace sidebar** — fixed sidebar with workspace list, colored dot indicators, "New workspace" button, user dropdown with avatar/initials
- **Project sidebar** — tools section (Flows, Screenplays, Sheets, Assets), dynamic tree section (switches based on active tool), trash + settings links
- **Tree components** — hierarchical navigation for sheets, flows, and screenplays with drag-and-drop reordering
- **Theme toggle** — light/dark mode in all layouts
- **User dropdown** — display name, email, links to Profile/Preferences, dark mode toggle (keyboard shortcut `D`), logout

### 1.6 Collaboration (Real-Time)

**Scope:** Flow Editor only. Sheets, scenes, and screenplays have no collaboration infrastructure.

**PubSub topics per flow:** `flow:{id}:presence`, `flow:{id}:cursors`, `flow:{id}:locks`, `flow:{id}:changes`.

- **Presence** — Phoenix Presence tracks online users per flow; up to 5 avatar rings in header (stacked circles with colored border); overflow `+N` badge; current user excluded from display; join/leave toast notifications
- **Cursor tracking** — real-time mouse cursor positions broadcast via PubSub (50ms client throttle); screen-to-canvas coordinate transform for pan/zoom-aware positioning; colored SVG cursors with email-derived username labels; fade to 30% opacity after 3s inactivity; pauses on WebSocket disconnect, resumes on reconnect
- **Node locking** — ETS-backed GenServer (`Storyarn.Collaboration.Locks`); 30-second auto-expiry with 10-second cleanup sweep; lock on node selection, release on deselect/Escape/navigation; lock indicator badge (lock icon + username pill) on locked nodes (not shown for your own lock); prevents editing/deleting/duplicating nodes locked by others; `release_all` on disconnect
- **Remote changes** — structural changes only: node add/move/delete/restore and connection add/delete broadcast to all collaborators; node data edits (text, conditions, etc.) are NOT broadcast in real-time; toast notifications (3s auto-dismiss) at bottom-left for remote actions
- **User colors** — deterministic 12-color palette (Tailwind 500 variants) based on `user_id rem 12`; matching light palette (300 variants) available for trails
- **Disconnect/reconnect** — canvas fades to 50% opacity + pointer-events-none on disconnect; restored on reconnect with `request_flow_refresh` to resync state

### 1.7 Internationalization (UI)

- **Gettext backend** — `StoryarnWeb.Gettext` with `otp_app: :storyarn`; all user-facing text externalized via `gettext/1`, `dgettext/2`, `ngettext/3`, `dngettext/4`
- **Locales** — `en` (default), `es`; configured in `config/config.exs` as `locales: ~w(en es)`
- **Locale detection plug** (`StoryarnWeb.Plugs.Locale`) — priority: URL param (`?locale=es`) → session (`:locale` key) → `Accept-Language` header (first tag, region stripped) → default `"en"`; writes resolved locale back to session for persistence
- **13 translation domains** — one per feature area:

| Domain | Scope | Approx. strings |
|---|---|---|
| `default` | Generic UI, layouts, flash, core components | 57 |
| `errors` | Ecto changeset validation errors | 24 |
| `identity` | Auth, login, registration, sessions | 56 |
| `flows` | Flow editor — nodes, connections, sidebar, debugger, player | 285 |
| `scenes` | Scene canvas — pins, zones, annotations, toolbar, settings | 214 |
| `sheets` | Sheet editor — blocks, variables, versions | 220 |
| `projects` | Projects — CRUD, membership, invitations, trash | 111 |
| `workspaces` | Workspaces — CRUD, membership, invitations | 90 |
| `localization` | Content localization feature (game text translation) | 93 |
| `screenplays` | Screenplay editor — elements, toolbar, export | 74 |
| `settings` | User/workspace settings pages | 42 |
| `assets` | Asset library — uploads, management | 45 |
| `emails` | Email notification templates | 5 |

- **Spanish coverage** — ~98.7% (~1,299 of ~1,316 strings translated); 16 real gaps across `scenes` (10), `localization` (3), `sheets` (3)
- **Client-side i18n** — no JS i18n library; translated strings injected from server via `data-i18n` JSON attribute (used by scene canvas hooks for context menu labels, with English string fallbacks); flow canvas renders translated text via server-rendered HTML
- **Date/number formatting** — `Calendar.strftime` (English month names only, not locale-aware); no locale-aware number or currency formatting
- **No locale switcher UI** — locale change only via `?locale=` URL parameter (persists in session); no dropdown, menu item, or settings page option
- **LiveView limitation** — `Gettext.put_locale` runs in the HTTP plug only; LiveView WebSocket mounts do not re-set the locale from session (may default to `"en"` during live events)

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

Ten block types:

| Type           | Variable-capable  | Config                                       | Value                                  |
|----------------|:-----------------:|----------------------------------------------|----------------------------------------|
| `text`         |        Yes        | label, placeholder                           | string content                         |
| `rich_text`    |        Yes        | label                                        | HTML content (TipTap with `@mentions`) |
| `number`       |        Yes        | label, placeholder                           | numeric content                        |
| `select`       |        Yes        | label, placeholder, options `[{key, value}]` | selected key                           |
| `multi_select` |        Yes        | label, placeholder, options `[{key, value}]` | array of keys                          |
| `boolean`      |        Yes        | label, mode (`two_state`)                    | true/false/nil                         |
| `date`         |        Yes        | label                                        | date value                             |
| `table`        |        Yes        | label, typed columns                         | rows with cell data (see below)        |
| `divider`      |        No         | —                                            | —                                      |
| `reference`    |        No         | label, allowed_types `["sheet","flow"]`      | target_type + target_id                |

- **Variable exposure** — blocks are variables unless type is `divider`/`reference` OR `is_constant: true`
- **Variable name** — auto-generated from label via slugify (e.g., "Health Points" → `health_points`); unique per sheet (suffixed `_2`, `_3` on collision)
- **Variable reference format** — `{sheet_shortcut}.{variable_name}` (e.g., `mc.jaime.health`)
- **Scope** — `self` (block stays on this sheet) or `children` (cascades to all descendants)
- **Required flag** — marks inherited blocks as mandatory for child sheets
- **Drag-and-drop reordering** via JS hook
- **Column layout** — blocks can be grouped into 2 or 3-column layouts; groups dissolve when fewer than 2 blocks remain

**Table block details:**
- Columns with typed fields (`number`, `text`, `boolean`, `select`, `multi_select`, `date`, `reference`)
- Rows with auto-generated row IDs and cell data per column
- Automatic slug generation from column names
- Full CRUD for columns and rows; cell value management
- Inheritance support: table columns sync to child sheet instances
- Variable reference path: `{sheet_shortcut}.{table_name}.{row_id}.{column_slug}`

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

### 2.9 Undo/Redo

- **Keyboard shortcuts** — Ctrl/Cmd+Z (undo), Ctrl/Cmd+Y (redo)
- **Coalesced updates** — typing in the same field within a short window is grouped as a single undo entry to prevent excessive undo steps
- **Tracked actions** — sheet name changes, shortcut changes, block create/delete/update, table column/row operations
- **Stack management** — via `UndoRedoStack` with `UndoRedo` JS hook

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

- **Rete.js** graph engine with Lit (Shadow DOM) rendering via LitElement custom elements (`StoryarnNode`, `StoryarnSocket`, `StoryarnConnection`)
- **Zoom & pan** — mouse wheel zoom, drag to pan on empty area, auto fit-view on initial load (called twice: 100ms delay + requestAnimationFrame for minimap DOM). No dedicated "Fit All" button or keyboard shortcut.
- **Grid** — radial dot background (24px spacing, 1.5px dots at 8% base-content opacity, theme-aware via daisyUI `--b2`/`--bc` CSS variables)
- **Minimap** — 200px Rete minimap plugin, registered after initial load to avoid per-node overhead; click/drag to pan; viewport rectangle indicator; explicitly removed on destroy
- **Level of Detail (LOD)** — two tiers: `full` (zoom > 0.45) and `simplified` (zoom < 0.40); hysteresis band prevents flicker; batched DOM updates (50 nodes/frame); lock indicators re-attached after transition; simplified nodes: colored header + type label + bare sockets only (120px min-width vs 180px full)
- **Node selection** — click to select + open sidebar + acquire collaboration lock; Ctrl+Click for multi-select (accumulating mode); double-click opens preferred editing mode (dialogue → screenplay editor, subflow/exit → navigate to referenced flow)
- **Node creation** — "Add Node" dropdown in header; all types except entry; random offset positioning
- **Node movement** — drag with 300ms debounced position save via `node_moved` event
- **Node duplication** — Ctrl/Cmd+D; per-type data cleanup (clears technical IDs, generates new localization IDs, etc.); +50px offset
- **Node deletion** — Delete/Backspace key; cannot delete entry or last exit; soft-delete with connection cascade; lock check; hub deletion cascades to clear orphaned jump target references
- **Connections** — drag from output socket to input socket; sockets show crosshair cursor + scale(1.3) + primary color on hover; 20px invisible hit area under 2px visible stroke for easier selection; bezier curve with midpoint label rendering; default stroke: `oklch(--bc/0.4)` 2px, hover: primary color 3px
- **Node visual states** — `.selected` (blue ring), `.nav-highlight` (4-cycle pulse in hub color, 2500ms), `.debug-current` (pulsing primary border), `.debug-visited` (success border), `.debug-waiting` (pulsing warning border), `.debug-error` (error border + shadow), `.debug-breakpoint` (red 8px dot top-right)
- **Performance** — deferred flow load (spinner overlay → async fetch), 3-phase bulk load (nodes → sockets → connections), LOD system, node update queue, debounced position push

### 3.5 Undo/Redo

Rete.js History plugin (`rete-history-plugin`) with `timing: 200` ms and a custom preset containing four action types. Keyboard-only access (no toolbar buttons).

**Keyboard:** Ctrl/Cmd+Z (undo), Ctrl/Cmd+Y or Ctrl/Cmd+Shift+Z (redo). Blocked when focus is on `INPUT`, `TEXTAREA`, `SELECT`, or `contentEditable` elements.

**Action types:**

| Action | Captured data | Undo | Redo | Server event |
|---|---|---|---|---|
| `DragAction` | `nodeId`, `prev {x,y}`, `next {x,y}` | `area.translate(nodeId, prev)` → triggers existing `node_moved` debounce pipeline (300ms) | `area.translate(nodeId, next)` → same pipeline | `node_moved` (indirect, via `nodetranslated` handler) |
| `AddConnectionAction` | Full connection snapshot | `editor.removeConnection(id)` → `connection_deleted` | `editor.addConnection(conn)` → `connection_created` (skipped if either endpoint node deleted) | `connection_deleted` / `connection_created` |
| `RemoveConnectionAction` | Full connection snapshot | `editor.addConnection(conn)` → `connection_created` (skipped if either endpoint node deleted) | `editor.removeConnection(id)` → `connection_deleted` | `connection_created` / `connection_deleted` |
| `DeleteNodeAction` | Hook ref, database node ID | Pushes `restore_node` → server clears `deleted_at`, re-adds node + valid connections via `node_restored` event; idempotent (`{:ok, :already_active}` if already restored) | Sets `_historyTriggeredDelete` flag, pushes `delete_node` → server soft-deletes; flag prevents double-recording in history | `restore_node` / `delete_node` |

**Drag coalescing:** When a `nodetranslated` event fires while the node is in the `picked` set (user actively dragging), the preset checks `history.getRecent(400)` for an existing `DragAction` on the same node. If found, updates its `next` position and resets its timestamp instead of creating a new entry. Programmatic translates (from undo/redo or server-push) are skipped because the node is not in `picked`.

**History suppression during bulk loads** — two complementary mechanisms:
1. `isLoadingFromServer` reference counter — all preset pipe handlers check this flag and skip recording when > 0
2. Deferred plugin registration — `area.use(history)` is called only **after** all initial nodes and connections are loaded, so the preset pipes don't even exist during first load

**History clearing:** `history.clear()` is called on every `flow_updated` server event (full flow refresh due to hub deletion cascading to orphaned jumps, or collaborator bulk changes).

**What is NOT tracked:** Node creation, node duplication, node data edits (text, conditions, responses), connection rebuilds during `rebuildNode`, and programmatic translates outside of user drags

### 3.6 Keyboard Shortcuts

All canvas shortcuts are blocked when focus is in `INPUT`, `TEXTAREA`, `SELECT`, or `contentEditable` elements (prevents conflicts with sidebar text editors). Debug and toggle shortcuts fire regardless of focus.

**Canvas shortcuts** (blocked in text inputs):

| Shortcut                      | Action                                     | Condition                          |
|-------------------------------|--------------------------------------------|------------------------------------|
| Ctrl/Cmd+Z                    | Undo                                       | —                                  |
| Ctrl/Cmd+Y / Ctrl/Cmd+Shift+Z | Redo                                       | —                                  |
| Delete / Backspace            | Delete selected node                       | Node selected, not locked by other |
| Ctrl/Cmd+D                    | Duplicate selected node                    | Node selected                      |
| Escape                        | Deselect node, close sidebar, release lock | Node selected                      |

**Debug shortcuts** (always fire, requires debug session active via `[data-debug-active]`):

| Shortcut         | Action                   |
|------------------|--------------------------|
| Ctrl/Cmd+Shift+D | Toggle debug mode on/off |
| F10              | Step forward             |
| F9               | Step back                |
| F5               | Toggle auto-play/pause   |
| F6               | Reset                    |

**Global app shortcuts** (defined in `theme.js`, fire app-wide outside text inputs):

| Shortcut   | Action                    |
|------------|---------------------------|
| D          | Toggle dark/light theme   |
| E          | Navigate to user settings |

Note: There are no toolbar buttons for undo/redo — keyboard-only access. Multi-select (`Ctrl+Click`) accumulates selection but Delete/Duplicate operate on single selected node only. Copy/paste is not supported in the flow canvas (available in scenes only).

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

- Breadcrumb "Flows" link; Back/Forward buttons with full navigation history (Agent-persisted across remounts)
- Subflow double-click navigates to target flow (history tracked automatically)
- Keyboard shortcuts: Alt+Left (back), Alt+Right (forward)
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

### 3.12 Story Player

Full-screen cinematic playback mode for flows. Route: `/workspaces/:ws/projects/:proj/flows/:id/play`. Launched from the flow editor header via a "Play" button.

**Architecture:** `PlayerLive` (layout: false) → `PlayerEngine` (auto-advance loop) → `Slide` (pure render-data builder) → components (`PlayerSlide`, `PlayerChoices`, `PlayerToolbar`, `PlayerOutcome`).

**Engine (`PlayerEngine.step_until_interactive/3`):**
- Thin loop wrapper over `Evaluator.Engine.step/3` — the same pure-functional state machine used by the debugger
- Auto-advances through non-interactive nodes: `entry`, `hub`, `condition`, `instruction`, `jump`, `subflow`
- Stops at: `dialogue` (`:waiting_input`), `exit` (`:finished`), errors, and cross-flow signals (`:flow_jump`, `:flow_return`)
- Safety limit: 100 auto-steps per call; returns `{:error, state, skipped_nodes}` if exceeded
- Returns `skipped_nodes` list of `{node_id, node_type}` tuples for future journey tracking

**Slide types:**

| Type        | Node        | Fields                                                                                                                                                          |
|-------------|-------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `:dialogue` | `dialogue`  | Speaker name/initials/color (resolved from sheet), sanitized+interpolated text, stage directions, menu text, responses (id, text, valid, number, has_condition) |
| `:scene`    | `scene`     | Setting (INT/EXT), location name (from sheet), sub-location, time of day, sanitized+interpolated description                                                    |
| `:outcome`  | `exit`      | Label (falls back to strip_html of text, then "The End"), outcome color, outcome tags, step count, variables changed count, choices made count                  |
| `:empty`    | nil/unknown | Fallback "No content to display"                                                                                                                                |

**Variable interpolation:** `{reference.name}` patterns in dialogue text and scene descriptions are replaced with styled spans. Known variables get `.player-var` (purple badge), unknown get `.player-var-unknown` (orange badge). Values are HTML-escaped; lists are comma-joined.

**HTML sanitization:** Shared `HtmlSanitizer` module — allows 27 tags (p, br, em, strong, b, i, u, s, span, a, ul, ol, li, blockquote, code, pre, sub, sup, del, h1–h6, div). Strips `on*` event handlers, `style`/`srcdoc`/`formaction` attributes, and `javascript:` URIs. Disallowed tags unwrapped (children preserved). HTML comments removed.

**Two player modes:**
- **Player** (default, `eye` icon) — mimics end-user experience; invalid (condition-blocked) responses hidden
- **Analysis** (`scan-eye` icon) — shows ALL responses; invalid ones greyed out with red badge, disabled; `shield-question` icon on conditioned responses

**Outcome screen:** Accent color bar, title from exit label, outcome tag badges, stats row (steps / choices / variables changed), "Play again" + "Back to editor" buttons.

**Cross-flow navigation:** Full support for multi-flow playback via `Engine.push_flow_context/4` and `pop_flow_context/1`. Nested jumps handled recursively. Session state bridged across LiveView remounts via `DebugSessionStore` (Agent-based, 5-min TTL, one-shot store/take, keyed by `{user_id, project_id}`). Player sessions distinguished from debugger sessions by presence of `:player_mode` key.

**Step back:** `Engine.step_back/1` via state snapshots. Returns to the previous interactive node state.

**Keyboard shortcuts** (`StoryPlayer` JS hook, global `keydown` listener):

| Key                        | Action                            |
|----------------------------|-----------------------------------|
| Space / Enter / ArrowRight | Continue (advance to next node)   |
| ArrowLeft / Backspace      | Go back (step back)               |
| 1–9                        | Select Nth visible response       |
| P                          | Toggle player/analysis mode       |
| Escape                     | Exit player (back to flow editor) |

### 3.13 Other Features

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

| Key                          | Behavior                                                                                                                                         |
|------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------|
| Enter                        | Split block, create next block with smart type progression (scene_heading→action, character→dialogue, dialogue→action, transition→scene_heading) |
| Tab                          | Cycle block type forward: action → sceneHeading → character → dialogue → parenthetical → transition                                              |
| Shift+Tab                    | Cycle backward                                                                                                                                   |
| Backspace (empty non-action) | Convert to action first                                                                                                                          |
| Escape                       | Blur editor                                                                                                                                      |

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

- **Fields:** filename, content_type (MIME), size (bytes), key (storage path), url (public), metadata (JSON: width/height for images)
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

| Context                    | Accepts        | Max Size   |
|----------------------------|----------------|------------|
| Asset library (general)    | Images + Audio | 20 MB      |
| Audio picker (flow editor) | Audio only     | 20 MB      |
| Audio tab (sheet)          | Audio only     | 20 MB      |
| Sheet avatar               | Images only    | 5 MB       |
| Sheet banner               | Images only    | 10 MB      |

### 5.9 Sheet Integration

- **Avatar** (`avatar_asset_id`) — image shown in sidebar tree, breadcrumbs, card views; upload or pick from library; remove (unlinks, doesn't delete asset)
- **Banner** (`banner_asset_id`) — cover image at top of sheet; upload, change, or remove; fallback to solid color

### 5.10 Flow Integration

- **Audio on dialogue nodes** (`audio_asset_id`) — attach audio via AudioPicker component in sidebar; dropdown to select from project audio assets + upload button; 🔊 indicator on node canvas; remove (unlinks)
- **Audio tab on sheets** — centralized view of all voice lines for a character; per-node audio select/upload/remove directly from the sheet

### 5.11 Scene Integration

- **Background image** (`background_asset_id`) — scenes store a reference to an image asset used as the Leaflet overlay background; upload/change/remove from scene settings panel
- **Custom pin icons** (`icon_asset_id`) — scene pins can use a custom uploaded icon image (max 512 KB); displayed instead of the default Lucide icon; sheet-linked pins display the sheet's avatar image

### 5.12 Analytics

- **Count by type** — `%{"image" => N, "audio" => N}` (SQL group by MIME prefix)
- **Total storage size** — sum of all asset sizes per project (in bytes)
- **Usage tracking** — queries all references across flow nodes, sheet avatars, and sheet banners; excludes soft-deleted entities

---

## 6. Scenes

### 6.1 Core Data Model

- **Scene** — name (max 200), shortcut (project-unique), description (max 2000), width/height (pixels), scale_value/scale_unit (for ruler), position (sibling order)
- **Tree structure** — self-referential `parent_id`; scenes can nest arbitrarily deep
- **Background image** — `background_asset_id` FK to assets; displayed as Leaflet image overlay
- **Soft delete** — `deleted_at` timestamp; recursive child soft-delete; trash, restore, permanent delete
- **Coordinate system** — all positions stored as **percentages (0–100%)** of scene dimensions, making layouts resolution-independent

### 6.2 Element Types

**Layers** — ordered visibility groups; every scene auto-creates a default layer; each layer has: name, visible toggle, position, fog of war settings (fog_enabled, fog_color, fog_opacity). Cannot delete last layer; deleting a layer nullifies `layer_id` on its elements.

**Zones** — polygonal regions defined by 3–100 vertices (percentage coords). Four drawing shapes:
- **Rectangle** — drag bounding box → 4 vertices
- **Triangle** — drag base → 3 vertices
- **Circle** — drag radius → approximated as 32-point polygon
- **Freeform** — click points, close by clicking near first point or pressing Escape

Zone fields: name (max 200), vertices, fill_color, opacity (0–1), border_color, border_style (solid/dashed/dotted), border_width (0–10), tooltip (max 500), locked, target_type (sheet/flow/scene), target_id, action_type (none/instruction/display), action_data (map), condition (map), condition_effect (hide/disable). Vertex editing mode allows individual vertex drag.

**Pins** — point markers with types: `location`, `character`, `event`, `custom`. Fields: label (max 200), position_x/y (%), pin_type, icon (Lucide name), color, opacity (0–1), size (sm/md/lg), tooltip (max 500), locked, target_type (sheet/flow/scene/url), target_id, sheet_id (direct sheet link), icon_asset_id (custom uploaded icon, max 512KB), action_type (none/instruction/display), action_data (map), condition (map), condition_effect (hide/disable). Sheet-linked pins display the sheet's avatar image.

**Connections** — lines between two pins with: line_style (solid/dashed/dotted), line_width (0–10), color, label (max 200), bidirectional toggle, show_label toggle, waypoints (max 50 `{x,y}` percentage coords). Self-connections prevented. Both pins must belong to same scene.

**Annotations** — free-floating text labels: text (1–500 chars), position_x/y (%), font_size (sm/md/lg), color, locked.

### 6.3 Canvas

- **Leaflet.js** with `L.CRS.Simple` (flat image coordinate space, no geographic projection)
- **Pan/zoom** — native Leaflet; scroll to zoom, drag to pan
- **Minimap** — bottom-right thumbnail Leaflet instance with red viewport rectangle; click to navigate; reset-zoom and toggle buttons
- **Background** — uploaded image as Leaflet image overlay; settings panel for upload/change/remove

### 6.4 Canvas Tools (Dock)

Bottom dock in edit mode, 10 tools in 5 groups:

| Tool           | Shortcut  | Description                                                          |
|----------------|-----------|----------------------------------------------------------------------|
| Select         | Shift+V   | Click to select, drag to move                                        |
| Pan            | Shift+H   | Drag scene, scroll to zoom                                           |
| Rectangle zone | Shift+R   | Draw rectangular zone                                                |
| Triangle zone  | Shift+T   | Draw triangular zone                                                 |
| Circle zone    | Shift+C   | Draw circular zone                                                   |
| Freeform zone  | Shift+F   | Click polygon points, close to finish                                |
| Free Pin       | Shift+P   | Click canvas to place pin                                            |
| From Sheet     | —         | Open sheet picker, then click to place character pin linked to sheet |
| Annotation     | Shift+N   | Click canvas to place text note (auto-focuses for inline editing)    |
| Connector      | Shift+L   | Click source pin, then target pin to create connection               |
| Ruler          | Shift+M   | Click two points to measure distance                                 |

Dock hidden in view mode.

### 6.5 Floating Element Toolbar

FigJam-style floating toolbar above selected element. Content varies by type:

**Zone:** Name input, fill color (swatches + opacity slider), border (style/width/color), layer picker, lock toggle, More (...): tooltip, link-to target picker (sheet/flow/scene), action type (none/instruction/display), condition builder, condition effect (hide/disable)

**Pin:** Label input, type picker (location/character/event/custom with icons), color + opacity, size (S/M/L pills), layer picker, lock toggle, More (...): tooltip, link-to (sheet/flow/scene/url), change icon (upload overlay), action type (none/instruction/display), condition builder, condition effect (hide/disable)

**Connection:** Label input, line style (style/width/color), show-label toggle, bidirectional toggle, More (...): straighten path (clears waypoints)

**Annotation:** Color swatch, size (S/M/L), layer picker, lock toggle

### 6.6 Color System

Two preset rows: vivid (12 Tailwind colors + black) and pastel (11 pastels + white) plus a custom color picker (native browser input). All stored as hex (`#RGB`, `#RRGGBB`, or `#RRGGBBAA`).

### 6.7 Layer System

Top-left layer bar overlay on canvas:
- Visibility toggle (eye/eye-off) per layer
- Click layer name to set as active (new elements assigned to active layer)
- Fog of War indicator (cloud-fog icon) when enabled
- Kebab menu: rename (inline), enable/disable fog, delete (protected — cannot delete last layer)
- Reorder layers via `reorder_layers` event

### 6.8 Zone → Child Scene Drill-Down

Double-click a named zone → `create_child_scene_from_zone`:
1. Zone must have a name (error if blank)
2. `ZoneImageExtractor` crops parent's background to zone's bounding box, upscales to min 1000px, sharpens (sigma=1.5), saves as WebP asset
3. Creates child scene with: zone name, parent_id, extracted background, computed dimensions, proportional scale_value
4. Updates zone with `target_type: "scene"`, `target_id: child_scene.id`
5. Navigates to child scene

If no background image, creates 1000x1000px child scene without background. Child scenes display a boundary polygon fog overlay (zone vertices normalized to child coordinate space).

### 6.9 Keyboard Shortcuts

All shortcuts require edit mode and are blocked in text inputs.

| Shortcut                      | Action                                               |
|-------------------------------|------------------------------------------------------|
| Delete / Backspace            | Delete selected element                              |
| Escape                        | Deselect; cancel in-progress zone/connection drawing |
| Ctrl/Cmd+Z                    | Undo                                                 |
| Ctrl/Cmd+Shift+Z / Ctrl/Cmd+Y | Redo                                                 |
| Ctrl/Cmd+Shift+D              | Duplicate selected element                           |
| Ctrl/Cmd+Shift+C              | Copy selected element (to localStorage)              |
| Ctrl/Cmd+Shift+V              | Paste (from localStorage, +5% offset)                |
| Shift+V/H/R/T/C/F/P/N/L/M     | Switch tool (see dock table above)                   |

### 6.10 Undo/Redo

Server-side undo/redo. Stacks stored in socket assigns, max depth 50 each.

**Tracked operations** (delete only):

| Operation         | Undo                                 | Redo                         |
|-------------------|--------------------------------------|------------------------------|
| Delete pin        | Recreates pin with all fields        | Re-deletes the recreated pin |
| Delete zone       | Recreates zone with all fields       | Re-deletes                   |
| Delete connection | Recreates connection with all fields | Re-deletes                   |
| Delete annotation | Recreates annotation with all fields | Re-deletes                   |

Undo clears redo stack. Flash messages: "Pin deleted. Press Ctrl+Z to undo." / "Undo: pin restored."

Note: Create, move, and edit operations are NOT tracked in undo history (only deletes).

### 6.11 Copy/Paste & Duplicate

- **Copy** (Ctrl/Cmd+Shift+C) → stores element data in `localStorage` key `"storyarn_scene_clipboard"`
- **Paste** (Ctrl/Cmd+Shift+V) → creates copy at +5% offset in both axes; respects active layer
- **Duplicate** (Ctrl/Cmd+Shift+D or context menu) → same as copy+paste; label gets " (copy)" suffix; sheet/target links NOT copied
- Connections cannot be copied/pasted/duplicated
- Locked elements cannot be duplicated

### 6.12 Context Menu

Right-click on empty canvas: "Add Pin Here", "Add Annotation Here"

Right-click on element: Edit Properties, Connect To..., Edit Vertices (zones only), Duplicate, Bring to Front, Send to Back, Lock/Unlock, Delete

### 6.13 Locking

Zones, pins, and annotations can be locked via the floating toolbar toggle. Locked elements cannot be dragged, deleted, or duplicated (error flash shown).

### 6.14 Search Panel

Top-left below layer bar:
- Search input with 300ms debounce, case-insensitive match on label/name/text
- Type filter tabs (when query non-empty): All / Pins / Zones / Notes / Lines
- Results list (clickable to focus + select)
- Non-matching elements dimmed on canvas; matching elements remain bright

### 6.15 Legend

Auto-generated bottom-right panel. Groups:
- **Pins** by `(pin_type, color)` — icon + type label + count
- **Zones** by `fill_color` — swatch + count
- **Connections** by `(line_style, color)` — line preview + count

Only shown when scene has at least one element. Click to expand/collapse.

### 6.16 Ruler Tool

Click two points to measure distance. Displays:
- Orange dashed line with circle markers at endpoints
- Midpoint label: real-world distance if scale configured (e.g., "42 km"), otherwise percentage of scene width
- Multiple measurements simultaneously; Escape or tool switch clears all
- Measurements are ephemeral (not persisted)

### 6.17 Export

- **PNG** — `modern-screenshot` (`domToPng`) at 2x retina scale; Leaflet controls hidden during capture; downloads as `{scene_name}.png`
- **SVG** — custom serializer: zones → `<polygon>`, connections → `<polyline>` + label `<text>`, pins → `<circle>` + `<text>`, annotations → `<text>`; hidden layers excluded; downloads as `{scene_name}.svg`

### 6.18 Scene Settings

Gear icon in header opens floating panel:
- **Background Image:** upload (JPEG/PNG/GIF/WebP, no SVG), change, remove
- **Scene Scale:** scale_value (number) + scale_unit (string) — defines "1 scene width = N units" for ruler
- **Dimensions:** read-only width x height px display

### 6.19 Header & Navigation

- Back link to scenes index
- **Breadcrumb** showing ancestor scene names (clickable, up to depth 50)
- **Editable scene name** (contenteditable, saves on blur)
- **Shortcut badge** (`#shortcut`)
- **Export dropdown** (PNG / SVG)
- **Scene Settings** gear button (edit mode only)
- **View/Edit mode toggle** (segmented control; only for users with `edit_content` permission)
- **Highlight from URL** — `?highlight=pin:ID` or `?highlight=zone:ID` focuses and selects element on load

### 6.20 Hierarchical Scene Tree

Sidebar tree with:
- Expand/collapse nodes
- Up to 10 zones + 10 pins previewed per scene; overflow as "N more zones…" / "N more pins…"
- Drag-to-reorder among siblings
- "Add child scene" per node
- "Move to Trash" per node
- Filter/search input ("Filter scenes…")
- Zone → child scene drill-down links

### 6.21 Backlinks

`Scenes.get_elements_for_target(target_type, target_id)` returns all zones and pins across all scenes that link to a given sheet/flow/scene — used for "Appears on these scenes" views.

### 6.22 Authorization

All edit operations gated by `ProjectMembership.can?(role, :edit_content)` via `with_auth/3` helper.

**View-only users can:** view scene, pan/zoom, search elements, export.

**View-only users cannot:** create/edit/delete elements, manage layers, change settings/background, access dock or floating toolbar.

### 6.23 Actions & Conditions

Zones and pins support interactive behavior for the exploration/player mode:

- **Action types:**
  - `none` — element acts as a pure navigation target (links to sheet/flow/scene/url)
  - `instruction` — executes variable assignments when clicked (via action_data map containing assignment rules)
  - `display` — displays a variable value when clicked
- **Conditions** — variable-based condition expressions (same condition builder as flow nodes); evaluated against current variable state
- **Condition effects:**
  - `hide` — element is not rendered when condition is false
  - `disable` — element is rendered but non-interactive when condition is false
- UI: condition builder and action configuration in the "More (...)" popover of the floating toolbar

### 6.24 Exploration Mode (Player)

Full-screen exploration mode for scenes. Route: `/workspaces/:ws/projects/:proj/scenes/:id/explore`.

- **Architecture:** `ExplorationLive` (layout: false) renders a Leaflet canvas with interactive zones and pins
- **Interactions:**
  - Click zones/pins with `action_type="instruction"` to execute variable assignments
  - Click zones/pins with target links to navigate (sheet/flow/scene)
  - Launch flows overlaid on a dimmed scene background
- **Flow execution** — full flow engine integration: auto-advances through non-interactive nodes, stops at dialogue (waiting for input), handles cross-flow jumps and returns
- **Variable state** — tracked across scene/flow navigation; condition evaluation uses live variable state
- **Keyboard:** Escape exits flow overlay; standard flow player controls when a flow is active

### 6.25 Collaboration

No real-time collaboration for scenes. No presence, cursor sharing, or conflict resolution. Last write wins at DB level.

---

## 7. Localization

Content localization system for translating game text (dialogue, descriptions, labels) into multiple languages. Completely separate from the UI i18n system (Section 1.7). Built on automatic text extraction, manual editing, machine translation via DeepL, export/import, glossary management, and reporting.

### 7.1 Core Data Model

**ProjectLanguage** — one record per locale per project:
- `locale_code` (BCP 47, 2–10 chars, e.g., "en", "zh-CN"), `name` (display name, 1–100), `is_source` (boolean, exactly one per project enforced via partial unique index), `position` (sort order)
- Unique constraint: `(project_id, locale_code)`

**LocalizedText** — one row per translatable field per locale:
- **Source fields:** `source_type` (one of: `flow_node`, `block`, `sheet`, `flow`), `source_id`, `source_field` (e.g., `text`, `response.r1_123.text`), `source_text` (original content, may contain HTML), `source_text_hash` (SHA-256 for change detection), `word_count` (auto-computed, HTML stripped). Note: `screenplay` is defined as a valid source_type in the schema but screenplay text extraction is not yet implemented.
- **Translation fields:** `locale_code`, `translated_text`, `status` (workflow: `pending` → `draft` → `in_progress` → `review` → `final`), `machine_translated` (boolean), `last_translated_at`, `translated_by_id` (user FK)
- **Review fields:** `translator_notes`, `reviewer_notes`, `last_reviewed_at`, `reviewed_by_id` (user FK)
- **Voice-over fields:** `vo_status` (`none` → `needed` → `recorded` → `approved`), `vo_asset_id` (FK to audio asset)
- **Speaker tracking:** `speaker_sheet_id` (FK to sheet, for word-count-by-speaker reporting)
- Composite unique key: `(source_type, source_id, source_field, locale_code)`
- **Auto-downgrade rule:** when `upsert_text` detects `source_text_hash` changed and current status is `final`, it auto-downgrades to `review`

**GlossaryEntry** — per-project terminology definitions:
- `source_term`, `source_locale`, `target_term` (nil = use source as-is), `target_locale`, `context` (usage notes), `do_not_translate` (boolean, for proper nouns)
- Unique constraint: `(project_id, source_term, source_locale, target_locale)`

**ProviderConfig** — machine translation provider settings:
- `provider` ("deepl" only currently), `api_key_encrypted` (Cloak encryption), `api_endpoint` (free vs pro), `is_active`, `settings` (JSON), `deepl_glossary_ids` (map of language-pair → DeepL glossary ID)
- Unique constraint: `(project_id, provider)`

### 7.2 Automatic Text Extraction

`Localization.extract_all/1` performs a full project re-sync. Additionally, extraction runs **automatically** on every relevant CRUD operation:

**Triggers and extracted fields:**

| Entity | Trigger | Fields extracted |
|---|---|---|
| Dialogue node | Node create/update | `text` (rich HTML), `stage_directions`, `menu_text`, per-response `response.<id>.text` |
| Scene node | Node create/update | `description` |
| Exit node | Node create/update | `label` |
| Flow | Flow create/update | `name`, `description` |
| Sheet | Sheet create/update | `name`, `description` |
| Text block | Block create/update | `config.label`, `value.content` |
| Select block | Block create/update | `config.label`, per-option `config.options.<key>` |
| Other blocks | Block create/update | `config.label` only |

**Cleanup:** Entity deletions trigger `delete_texts_for_source/2`. Response removal triggers `delete_texts_for_source_field/3` to clean orphaned field-level rows.

**Dialogue speaker tracking:** For dialogue node texts, `speaker_sheet_id` is stored on each localized text row to enable word-count-by-speaker reporting.

### 7.3 Language Management

- **Source language** — auto-created from `workspace.source_locale` on first visit (`ensure_source_language/1`); displayed as primary badge with flag icon; cannot be removed
- **Target languages** — added via "Add Language" dropdown (filters out already-added locales); adding a language triggers immediate `extract_all` to populate `localized_text` rows for the new locale
- **Language registry** — static list of ~49 languages covering all DeepL-supported targets plus major game localization markets; each entry: `{code, name, native, region}`
- **Set source language** — atomic transaction: unset old source, set new source
- **Remove language** — deletes language record and all its translations (with confirmation modal)
- **Reorder languages** — bulk position update by ordered ID list

### 7.4 Translation Index Page

Route: `/workspaces/:ws/projects/:proj/localization`

- **Language bar** — source language (primary badge), target languages as chips with inline remove button
- **Locale selector** — dropdown to switch between target locales for the translation table
- **Progress bar** — shows `final / total` count with percentage for selected locale
- **Filters** — status filter (pending/draft/in_progress/review/final), source type filter (flow_node/block/sheet/flow/screenplay), full-text search (300ms debounce)
- **Translation table** — columns: source text (truncated), translated text (truncated), MT badge (if machine translated), status badge (color-coded), word count
- **Per-row actions** — edit link (pencil icon), single-translate button (sparkles icon, shown only when DeepL configured and no translation exists yet)
- **Batch actions** — "Translate All Pending" button (shown only when DeepL provider active), "Sync" button (re-runs full extraction)
- **Export dropdown** — Excel (.xlsx) and CSV (.csv) download
- **Report link** — navigates to analytics page
- **Pagination** — page size 50, previous/next buttons

### 7.5 Translation Edit Page

Route: `/workspaces/:ws/projects/:proj/localization/:id`

- **Two-column layout** — left: source text (read-only, rendered as HTML via `raw/1`) with word count below; right: translation editor
- **Form fields** — `translated_text` (textarea), `status` (select with all 5 workflow statuses), `translator_notes` (textarea)
- **Save** — updates text + sets `last_translated_at` to now
- **"Translate with DeepL"** button — calls `translate_single/2`, refreshes form (only shown when DeepL configured)
- **Metadata row** — machine_translated badge, last_translated_at timestamp
- **Header subtitle** — shows `source_type/source_field` in monospace

### 7.6 Machine Translation (DeepL)

- **Provider architecture** — `TranslationProvider` behaviour with callbacks: `translate/5`, `get_usage/1`, `supported_languages/1`, `create_glossary/5` (optional), `delete_glossary/2` (optional)
- **DeepL adapter** — uses `Req` HTTP client; supports both free (`api-free.deepl.com`) and pro endpoints
- **Batch translation** — `translate_batch/3` sends all `status: "pending"` texts for a locale in chunks of 50; sets `machine_translated: true` and `status: "draft"` on success
- **Single translation** — `translate_single/2` translates one text by ID
- **HTML handling** — if text contains `<`, uses `tag_handling: "html"` in DeepL API
- **Variable preservation** — `HtmlHandler.pre_translate/1` wraps `{variable_name}` patterns in `<span translate="no">` before sending to DeepL; `post_translate/1` strips those spans from the response
- **Glossary integration** — per-language-pair glossary IDs stored in `ProviderConfig.deepl_glossary_ids`; glossary terms sent as TSV format
- **Error handling** — specific atoms: `:rate_limited` (429), `:quota_exceeded` (456), `:invalid_api_key` (403)
- **API key encryption** — stored via Cloak (`Storyarn.Shared.EncryptedBinary`)

### 7.7 Glossary

- **Entries** — source_term + source_locale → target_term + target_locale pairs, with optional context notes and "do not translate" flag
- **CRUD** — create, update (target_term/context/do_not_translate), delete
- **Filtering** — by locale pair and search term
- **DeepL integration** — `get_glossary_entries_for_pair/3` returns `[{source, target}]` tuples formatted for the DeepL glossary API

### 7.8 Export/Import

**Export:**
- **Excel (.xlsx)** — `export_xlsx/2` generates binary Excel file; includes ID, source_type, source_field, source_text, translated_text, status columns
- **CSV** — `export_csv/2` generates CSV string; same columns
- **Filtered exports** — export controller accepts optional `status` and `source_type` query params for filtered downloads
- **Download** — via `LocalizationExportController`; sets content-type + `content-disposition: attachment`; filename: `{project-slug}_translations_{locale}.xlsx`

**Import:**
- **CSV import** — `import_csv/1` reads ID column, updates `translated_text` and `status` columns by `localized_text.id`
- No upload UI yet — function exists in `ExportImport` module but no LiveView form wired

### 7.9 Reports

Route: `/workspaces/:ws/projects/:proj/localization/report`

Four sections:

1. **Progress by Language** — progress bar per target language showing `final / total` count and percentage
2. **Word Counts by Speaker** — table with speaker sheet name (or "No speaker"), line count, word count; locale selector to switch view
3. **Voice-Over Progress** — stat cards for `none` / `needed` / `recorded` / `approved` counts for selected locale
4. **Content Breakdown** — badges showing counts per source type (Nodes, Blocks, Sheets, Flows, Screenplays)

### 7.10 Translation Workflow

```
pending → draft → in_progress → review → final
```

- **pending** — newly extracted, no translation yet
- **draft** — machine translated or initial human translation
- **in_progress** — translator actively working
- **review** — translation complete, awaiting review
- **final** — reviewed and approved
- **Auto-downgrade** — if source text changes after reaching `final`, status reverts to `review`

### 7.11 Voice-Over Tracking

```
none → needed → recorded → approved
```

- Each `localized_text` row tracks voice-over status independently
- `vo_asset_id` links to an uploaded audio asset for the recorded line
- Report page aggregates VO progress statistics per locale

### 7.12 Integration with `localization_id`

The `localization_id` field on dialogue nodes (e.g., `dialogue.a3f2b1`) is a **separate concept** — it's a human-readable key for **external localization tools** (Crowdin, Lokalise), not used internally by the localization system. Auto-generated on node creation, regenerated on duplicate, editable in the sidebar. Also emitted in screenplay exports for external pipeline integration.

### 7.13 Sidebar Integration

Localization appears as a top-level tool link in the project sidebar (Lucide `languages` icon), alongside Flows, Screenplays, Sheets, and Assets. Active state matched on any path under `/localization` (index, edit, report).
