# CLAUDE.md

## Project Overview

**Storyarn** is a narrative design platform (an "articy killer") for game development and interactive storytelling. Built with collaborative, real-time flow editing.

**Stack:** Elixir 1.15+ / Phoenix 1.8 / LiveView 1.1 / PostgreSQL / Redis / Tailwind v4 / daisyUI

## Convention References

**YOU MUST read these before writing code. Duplicating existing utilities is a bug.**

| File                                    | Purpose                                                             |
|-----------------------------------------|---------------------------------------------------------------------|
| `AGENTS.md`                             | Phoenix/LiveView/Ecto patterns (**MUST READ**)                      |
| @docs/conventions/shared-utilities.md   | **Shared utility registry — search here BEFORE writing any helper** |
| @docs/conventions/domain-patterns.md    | Context facades, CRUD templates, auth patterns                      |
| @docs/conventions/component-registry.md | All reusable HEEx components                                        |

## Related Documentation

| File                                  | Purpose                                     |
|---------------------------------------|---------------------------------------------|
| `docs/CURRENT_FEATURES.md`           | Comprehensive feature reference (canonical) |
| `IMPLEMENTATION_PLAN.md`              | Full roadmap and task breakdown             |
| `FUTURE_FEATURES.md`                  | Deferred features + competitive analysis    |

## Language Policy

**Everything MUST be in English.** All user-facing text uses Gettext:
```elixir
# ✅ Correct
put_flash(socket, :info, gettext("Project saved"))

# ❌ Wrong
put_flash(socket, :info, "Project saved")
```
Locales: `en` (default), `es`

## IMPORTANT: Reuse Existing Code

**NEVER duplicate existing utilities.** Before writing ANY helper, normalizer, validator, or shared function:

1. **Check `lib/storyarn/shared/`** — contains NameNormalizer, ShortcutHelpers, TreeOperations, SoftDelete, Validations, MapUtils, SearchHelpers, TimeHelpers, TokenGenerator
2. **Check `lib/storyarn_web/helpers/`** — contains Authorize (auth wrappers)
3. **Check `lib/storyarn_web/components/`** — contains all reusable UI components
4. **Read `docs/conventions/shared-utilities.md`** for the full registry with examples

**Common mistakes to avoid:**
- Writing slug/shortcut generation instead of using `NameNormalizer.slugify/1`, `variablify/1`, `shortcutify/1`
- Writing tree reorder/move logic instead of using `TreeOperations`
- Writing soft-delete logic instead of using `SoftDelete`
- Writing shortcut lifecycle logic instead of using `ShortcutHelpers`
- Writing `DateTime.utc_now() |> DateTime.truncate(:second)` instead of `TimeHelpers.now/0`
- Writing LIKE sanitization instead of using `SearchHelpers.sanitize_like_query/1`
- Writing map key conversion instead of using `MapUtils.stringify_keys/1`
- Writing shortcut/email validation instead of using `Validations.validate_shortcut/2`
- Rendering `raw(content)` without `HtmlSanitizer.sanitize_html/1`

## Commands

```bash
mix phx.server              # Dev server (localhost:4000)
mix test                    # Run tests
mix test.e2e                # E2E tests (Playwright)
mix precommit               # Before commit: format, credo, test
docker compose up -d        # Start PostgreSQL + Redis + Mailpit
```

## Architecture

```
lib/storyarn/                    # Domain (Contexts)
├── accounts.ex                  # Users, auth, sessions, OAuth
├── workspaces.ex                # Workspaces, memberships, invitations
├── projects.ex                  # Projects, memberships, invitations
├── sheets.ex                    # Sheets, blocks, variables, tables, versioning
├── flows.ex                     # Flows, nodes, connections, variable tracking
├── scenes.ex                    # Scenes, layers, zones, pins, annotations, connections
├── screenplays.ex               # Screenplays, elements, Fountain export/import
├── localization.ex              # Languages, texts, glossary, DeepL, export/import
├── collaboration.ex             # Presence, cursors, locking
├── assets.ex                    # File uploads (R2/S3, Local)
└── shared/                      # ← REUSABLE UTILITIES (see Convention References)

lib/storyarn_web/
├── components/                  # UI components (see docs/conventions/component-registry.md)
├── helpers/                     # Web helpers (Authorize)
├── live/
│   ├── flow_live/               # Flow editor
│   ├── sheet_live/              # Sheet editor
│   ├── scene_live/              # Scene editor
│   ├── screenplay_live/         # Screenplay editor
│   ├── localization_live/       # Localization editor
│   └── ...
└── router.ex
```

**Pattern:** Contexts use facade with `defdelegate` → submodules (e.g., `sheets.ex` → `sheets/sheet_crud.ex`). See @docs/conventions/domain-patterns.md for full pattern.

## Domain Model

```
User → WorkspaceMembership (owner|admin|member|viewer)
         └→ Workspace → Project → ProjectMembership (owner|editor|viewer)
                                    └→ Sheets, Flows, Assets
```

**Authorization:** `ProjectMembership.can?(role, :edit_content)` / `WorkspaceMembership.can?(role, :manage_members)`

## Variable System

**Sheet Blocks = Variables** (unless `is_constant: true`)

```
Sheet (shortcut: "mc.jaime")
├── Block "Health" (number)     → Variable: mc.jaime.health
├── Block "Class" (select)      → Variable: mc.jaime.class
└── Block "Name" (is_constant)  → NOT a variable
```

**Reference format:** `{sheet_shortcut}.{variable_name}`

**Block types → Operators:**
- `number`: equals, greater_than, less_than, etc.
- `select`: equals, not_equals, is_nil
- `multi_select`: contains, not_contains, is_empty
- `boolean`: is_true, is_false, is_nil
- `text`/`rich_text`: equals, contains, starts_with, is_empty
- `date`: equals, before, after
- `table`: cell-level variable references via `{sheet}.{table}.{row}.{column}`
- Non-variable: `reference`

**API:**
```elixir
Sheets.list_project_variables(project_id)
# → [%{sheet_shortcut: "mc.jaime", variable_name: "health", block_type: "number", options: nil}, ...]
```

**Condition structure:**
```elixir
%{
  "logic" => "all",  # "all" (AND) | "any" (OR)
  "rules" => [
    %{"sheet" => "mc.jaime", "variable" => "health", "operator" => "greater_than", "value" => "50"}
  ]
}
```

## Flow Editor

**Node types:** `entry`, `exit`, `dialogue`, `condition`, `instruction`, `hub`, `jump`, `slug_line`, `subflow`

**Dialogue node data:**
```elixir
%{
  "speaker_sheet_id" => nil,
  "text" => "",                    # Rich text (HTML)
  "stage_directions" => "",
  "menu_text" => "",
  "audio_asset_id" => nil,
  "technical_id" => "",
  "localization_id" => "",
  "responses" => [%{"id" => "", "text" => "", "condition" => "", "instruction" => ""}]
}
```

**Condition node data:**
```elixir
%{
  "expression" => "",
  "cases" => [%{"id" => "...", "value" => "true", "label" => "True"}, ...]
}
```

**Visual indicators:** 🔊 (audio) | [?] (response condition)

**Key files (per-node-type architecture):**
```
lib/storyarn_web/live/flow_live/
├── show.ex                              # Main LiveView (thin dispatcher)
├── node_type_registry.ex                # Module lookup map → per-type modules
├── nodes/
│   ├── dialogue/
│   │   └── node.ex                      # Metadata + handlers (responses, tech_id, screenplay)
│   ├── condition/
│   │   └── node.ex                      # Metadata + handlers (condition builder, switch mode)
│   ├── instruction/
│   │   └── node.ex                      # Metadata + handlers (instruction builder)
│   ├── hub/
│   │   └── node.ex                      # Metadata + on_select (load referencing_jumps)
│   ├── jump/
│   │   └── node.ex                      # Metadata only
│   ├── slug_line/
│   │   └── node.ex                      # Metadata + handlers (location, slug line)
│   ├── subflow/
│   │   └── node.ex                      # Metadata + handlers (flow reference, exits)
│   ├── entry/
│   │   └── node.ex                      # Metadata + on_select (load referencing_flows)
│   └── exit/
│       └── node.ex                      # Metadata + handlers (generate_technical_id)
├── components/
│   ├── flow_toolbar.ex                  # Floating node toolbar (per-type render_toolbar clauses)
│   ├── flow_header.ex                   # Flow header (scene backdrop, title)
│   ├── node_type_helpers.ex             # Shared icon component + word_count
│   ├── screenplay_editor.ex             # Dialogue full-screen editor
│   ├── builder_panel.ex                 # Condition/instruction builder panel
│   └── debug_panel.ex                   # Debug console + history + variables tabs
├── handlers/
│   ├── generic_node_handlers.ex         # Generic ops (select, move, delete, duplicate, etc.)
│   ├── editor_info_handlers.ex          # UI state updates
│   ├── collaboration_event_handlers.ex  # Presence, locking
│   ├── navigation_handlers.ex           # Flow navigation
│   ├── debug_handlers.ex                # Debug mode handlers
│   ├── debug_execution_handlers.ex      # Debug step/run handlers
│   └── debug_session_handlers.ex        # Debug session lifecycle
└── helpers/
    ├── node_helpers.ex                  # persist_node_update + shared utils
    ├── form_helpers.ex                  # Form building
    ├── connection_helpers.ex            # Connection validation
    ├── socket_helpers.ex                # Socket utilities
    ├── html_sanitizer.ex                # XSS-safe HTML sanitizer
    ├── navigation_history.ex            # Flow navigation history
    ├── variable_helpers.ex              # Variable resolution helpers
    └── collaboration_helpers.ex         # Presence helpers

assets/js/
├── hooks/                               # ONLY Phoenix LiveView hooks (flat)
│   ├── flow_canvas.js                   # Flow editor hook (orchestrator)
│   ├── scene_canvas.js                  # Scene editor hook
│   ├── screenplay_editor.js             # Screenplay editor hook
│   ├── instruction_builder.js           # Instruction builder hook
│   ├── tiptap_editor.js                 # Rich text editor hook
│   ├── story_player.js                  # Story player hook
│   ├── undo_redo.js                     # Undo/redo hook (sheets)
│   └── ...                              # All flat, no subdirs
├── flow_canvas/                         # Flow editor utilities (non-hooks)
│   ├── nodes/
│   │   ├── index.js                     # Registry: type → module lookup
│   │   ├── render_helpers.js            # Shared rendering utilities
│   │   ├── dialogue.js                  # Config, pins, rendering, formatting, rebuild check
│   │   ├── condition.js                 # Config, dynamic outputs, formatting
│   │   ├── instruction.js               # Config, preview formatting
│   │   ├── hub.js                       # Config, nav links, color
│   │   ├── jump.js                      # Config, nav links, indicators
│   │   ├── slug_line.js                 # Config, slug line formatting, location
│   │   ├── subflow.js                   # Config, flow reference, dynamic exits
│   │   ├── entry.js                     # Config, referencing flows, nav links
│   │   └── exit.js                      # Config, color logic
│   ├── node_config.js                   # Thin re-export from nodes/index.js + createIconSvg
│   ├── flow_node.js                     # Delegates pin creation to per-type createOutputs
│   ├── components/
│   │   ├── storyarn_node.js             # Delegates rendering to per-type functions
│   │   └── ...
│   ├── handlers/
│   │   ├── editor_handlers.js           # Generic rebuildNode, per-type needsRebuild
│   │   └── ...
│   └── (setup.js, event_bindings.js)
├── instruction_builder/                 # Instruction builder utilities (non-hooks)
│   ├── assignment_row.js
│   ├── combobox.js
│   └── sentence_templates.js
└── tiptap/                              # Tiptap extensions (non-hooks)
    └── mention_extension.js
```

**Per-type architecture principle:** Each `nodes/{type}/` directory contains a single `node.ex` with all metadata and handlers for that node type.

## Icon Convention

**NEVER use Unicode emojis or custom SVGs. Always use [Lucide](https://lucide.dev) icons.**

**HEEx templates (server-rendered):**
```elixir
<.icon name="box" class="size-3 opacity-60" />
<.icon name="square" class="size-4" />
```

**JS — Icon utilities** (`node_config.js`):

| Utility                          | Purpose                            | Default  |
|----------------------------------|------------------------------------|----------|
| `createIconHTML(Icon, { size })` | General-purpose → outerHTML string | 10px     |
| `createIconSvg(Icon)`            | Node header icons (stroke styling) | 16px     |

**Flow canvas JS (Shadow DOM — Rete.js):**
```javascript
import { unsafeSVG } from "lit/directives/unsafe-svg.js";
import { Box } from "lucide";
import { createIconHTML } from "../node_config.js";

// Pre-create as module-level constants
const BOX_ICON = createIconHTML(Box, { size: 12 });

// Render inside Lit html`` templates with unsafeSVG
html`<span>${unsafeSVG(BOX_ICON)} Label</span>`;
```

**Hooks / builders (regular DOM):**
```javascript
import { createElement, Plus } from "lucide";

// Append as live DOM element (not outerHTML)
button.appendChild(createElement(Plus, { width: 12, height: 12 }));
```

**Rules:**
- Node headers: `createIconSvg(Icon)` (16px, stroke styling)
- outerHTML strings (Lit/Shadow DOM, innerHTML): `createIconHTML(Icon, { size })`
- DOM element appends (hooks, builders): `createElement(Icon, { width, height })` directly
- Always pre-create icon constants at module level — never inside `render()`

## Dialog & Confirmation Policy

**NEVER use browser-native dialogs.** No `window.confirm()`, `window.alert()`, `window.prompt()`, or `data-confirm`.

- **Confirmations:** `<.confirm_modal>` + `show_modal(id)` trigger
- **Modals:** `<.modal>` from `core_components.ex`
- **Validation errors from JS hooks:** `this.pushEvent(...)` → `put_flash` on server

Reference implementation: `project_live/trash.ex`

## Popover & Dropdown Positioning Policy

**NEVER use raw CSS absolute/relative positioning for popovers/dropdowns.** They break inside `overflow:hidden/clip` containers (tables, sidebars, etc.).

**ALWAYS use `@floating-ui/dom`** via the shared utility:

```javascript
import { createFloatingPopover } from "../utils/floating_popover";

// Creates a container appended to document.body (escapes overflow)
// Positioned with floating-ui (auto-repositions on scroll/resize)
const fp = createFloatingPopover(triggerEl, {
  class: "bg-base-200 border border-base-content/20 rounded-lg shadow-lg",
  width: "14rem",
  placement: "bottom-start",  // default
  offset: 4,                  // default
});

fp.el.appendChild(content);   // populate the container
fp.open();                     // show + start autoUpdate
fp.close();                    // hide + stop autoUpdate
fp.destroy();                  // remove from DOM + cleanup
```

**HEEx pattern:** Use `<template data-role="popover-template">` for server-rendered content that the hook clones into the body-appended container. Since cloned elements are outside the LiveView DOM tree, the hook must re-push `phx-click`/`phx-keydown` events via `this.pushEvent()`/`this.pushEventTo()`.

**Reference implementations:**
- `hooks/table_cell_select.js` — Full pattern with `<template>` + event re-pushing
- `hooks/color_picker.js` — Uses floating-ui directly (builds DOM in JS)
- `utils/floating_popover.js` — The shared utility

**Known technical debt** (DaisyUI CSS dropdowns, not yet migrated):
- `SearchableSelect` hook — CSS absolute, breaks in overflow containers
- DaisyUI `.dropdown` class usage in sidebar trees, block menus, table column headers

## Storyarn-Specific Patterns

**Layouts** (5 independent, not nested):
```elixir
<Layouts.app ...>      # Main app with workspace sidebar
<Layouts.focus ...>    # Project view with tool sidebar (flows, sheets, etc.)
<Layouts.auth ...>     # Login/register (centered)
<Layouts.public ...>   # Public/landing pages
<Layouts.settings ...> # Settings with nav sidebar
```
The Story Player and Scene Exploration use `layout: false` with their own fullscreen layout inline.

**LiveView Authorization:**
```elixir
use StoryarnWeb.Helpers.Authorize

case authorize(socket, :edit_content) do
  :ok -> # proceed
  {:error, :unauthorized} -> put_flash(socket, :error, gettext("..."))
end
```
Actions: `:edit_content`, `:manage_project`, `:manage_members`, `:manage_workspace`

**Components** (`StoryarnWeb.Components.*`):
- `MemberComponents` - user_avatar, member_row, invitation_row
- `BlockComponents` - Sheet block rendering
- `TreeComponents` - Notion-style navigation
- `CollaborationComponents` - Presence, cursors
- `Sidebar`, `ProjectSidebar`, `SaveIndicator`

## Implementation Status

**Completed:** Auth, Workspaces, Projects, Sheets/Blocks (incl. tables, versioning, property inheritance), Assets, Flow Editor (all 9 node types, debug mode, story player, undo/redo), Scenes (canvas, exploration mode, actions/conditions), Screenplays (editor, Fountain import/export, flow sync), Localization (extraction, DeepL, glossary, reports), Collaboration (presence, cursors, locks)

**See `docs/CURRENT_FEATURES.md`** for the comprehensive feature reference.
