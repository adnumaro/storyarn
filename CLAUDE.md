# CLAUDE.md

## Project Overview

**Storyarn** is a narrative design platform (an "articy killer") for game development and interactive storytelling. Built with collaborative, real-time flow editing.

**Stack:** Elixir 1.15+ / Phoenix 1.8 / LiveView 1.1 / PostgreSQL / Redis / Tailwind v4 / daisyUI

## Related Documentation

| File                            | Purpose                                            |
|---------------------------------|----------------------------------------------------|
| `AGENTS.md`                     | Phoenix/LiveView/Ecto patterns (**MUST READ**)     |
| `IMPLEMENTATION_PLAN.md`        | Full roadmap and task breakdown                    |
| `DIALOGUE_NODE_ENHANCEMENT.md`  | Dialogue node features (Phases 1-4 ✓, 5-7 pending) |
| `CONDITION_NODE_ENHANCEMENT.md` | Condition node variable integration (pending)      |
| `INSTRUCTION_VARIABLE_SYSTEM_PLAN.md` | Instruction node + variable tracking (pending) |
| `FLOW_NODES_IMPROVEMENT_PLAN.md` | Flow node fixes and improvements (Phases 1-2 ✓) |
| `FUTURE_FEATURES.md`           | Deferred features + competitive analysis           |

## Language Policy

**Everything MUST be in English.** All user-facing text uses Gettext:
```elixir
# ✅ Correct
put_flash(socket, :info, gettext("Project saved"))

# ❌ Wrong
put_flash(socket, :info, "Project saved")
```
Locales: `en` (default), `es`

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
├── sheets.ex                    # Sheets, blocks, variables
├── flows.ex                     # Flows, nodes, connections
├── collaboration.ex             # Presence, cursors, locking
└── assets/                      # File uploads (R2/S3)

lib/storyarn_web/
├── components/                  # UI components
├── live/
│   ├── flow_live/               # Flow editor ← MAIN WORK AREA
│   ├── sheet_live/              # Sheet editor
│   └── ...
└── router.ex
```

**Pattern:** Contexts use facade with `defdelegate` → submodules (e.g., `sheets.ex` → `sheets/sheet_crud.ex`)

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
- `boolean`: is_true, is_false, is_nil
- `text`: equals, contains, starts_with, is_empty
- Non-variable: `divider`, `reference`

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

**Node types:** `start`, `end`, `dialogue`, `condition`, `hub`

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
  "input_condition" => "",         # Visibility guard
  "output_instruction" => "",      # Side effect on exit
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

**Visual indicators:** 🔒 (input_condition) | ⚡ (output_instruction) | 🔊 (audio) | [?] (response condition)

**Key files (per-node-type architecture):**
```
lib/storyarn_web/live/flow_live/
├── show.ex                              # Main LiveView (thin dispatcher)
├── node_type_registry.ex                # Module lookup map → per-type modules
├── nodes/
│   ├── dialogue/
│   │   ├── node.ex                      # Metadata + handlers (responses, tech_id, screenplay)
│   │   └── config_sidebar.ex            # Sidebar panel HTML
│   ├── condition/
│   │   ├── node.ex                      # Metadata + handlers (condition builder, switch mode)
│   │   └── config_sidebar.ex
│   ├── instruction/
│   │   ├── node.ex                      # Metadata + handlers (instruction builder)
│   │   └── config_sidebar.ex
│   ├── hub/
│   │   ├── node.ex                      # Metadata + on_select (load referencing_jumps)
│   │   └── config_sidebar.ex
│   ├── jump/
│   │   ├── node.ex                      # Metadata only
│   │   └── config_sidebar.ex
│   ├── entry/
│   │   ├── node.ex                      # Metadata only
│   │   └── config_sidebar.ex
│   └── exit/
│       ├── node.ex                      # Metadata + handlers (generate_technical_id)
│       └── config_sidebar.ex
├── components/
│   ├── properties_panels.ex             # Shared frame, delegates to per-type sidebar
│   ├── node_type_helpers.ex             # Shared icon component + word_count
│   └── screenplay_editor.ex             # Dialogue full-screen editor
├── handlers/
│   ├── generic_node_handlers.ex         # Generic ops (select, move, delete, duplicate, etc.)
│   ├── editor_info_handlers.ex          # UI state updates
│   └── collaboration_event_handlers.ex  # Presence, locking
└── helpers/
    ├── node_helpers.ex                  # persist_node_update + shared utils
    ├── form_helpers.ex                  # Form building
    ├── connection_helpers.ex            # Connection validation
    ├── socket_helpers.ex                # Socket utilities
    └── collaboration_helpers.ex         # Presence helpers

assets/js/
├── hooks/                               # ONLY Phoenix LiveView hooks (flat)
│   ├── flow_canvas.js                   # Flow editor hook (orchestrator)
│   ├── instruction_builder.js           # Instruction builder hook
│   ├── tiptap_editor.js                # Rich text editor hook
│   └── ...                              # 12 more hooks (all flat, no subdirs)
├── flow_canvas/                         # Flow editor utilities (non-hooks)
│   ├── nodes/
│   │   ├── index.js                     # Registry: type → module lookup
│   │   ├── dialogue.js                  # Config, pins, rendering, formatting, rebuild check
│   │   ├── condition.js                 # Config, dynamic outputs, formatting
│   │   ├── instruction.js               # Config, preview formatting
│   │   ├── hub.js                       # Config, nav links, color
│   │   ├── jump.js                      # Config, nav links, indicators
│   │   ├── entry.js                     # Config only
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

**Per-type architecture principle:** Each `nodes/{type}/` directory tells you everything that node type does — read 2 files to understand the full behavior.

## Storyarn-Specific Patterns

**Layouts** (3 independent, not nested):
```elixir
<Layouts.app ...>      # Main app with sidebar
<Layouts.auth ...>     # Login/register (centered)
<Layouts.settings ...> # Settings with nav
```

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

**Completed:** Auth, Workspaces, Projects, Sheets/Blocks, Assets, Flow Editor, Collaboration, Dialogue Enhancement (1-4), Flow Node Improvements (Phases 1-2)

**In Progress:** Instruction Node + Variable System

**Next:** Dialogue Enhancement (5-7), Connection hardening, Export system
