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
├── pages.ex                     # Pages, blocks, variables
├── flows.ex                     # Flows, nodes, connections
├── collaboration.ex             # Presence, cursors, locking
└── assets/                      # File uploads (R2/S3)

lib/storyarn_web/
├── components/                  # UI components
├── live/
│   ├── flow_live/               # Flow editor ← MAIN WORK AREA
│   ├── page_live/               # Page editor
│   └── ...
└── router.ex
```

**Pattern:** Contexts use facade with `defdelegate` → submodules (e.g., `pages.ex` → `pages/page_crud.ex`)

## Domain Model

```
User → WorkspaceMembership (owner|admin|member|viewer)
         └→ Workspace → Project → ProjectMembership (owner|editor|viewer)
                                    └→ Pages, Flows, Assets
```

**Authorization:** `ProjectMembership.can?(role, :edit_content)` / `WorkspaceMembership.can?(role, :manage_members)`

## Variable System

**Page Blocks = Variables** (unless `is_constant: true`)

```
Page (shortcut: "mc.jaime")
├── Block "Health" (number)     → Variable: mc.jaime.health
├── Block "Class" (select)      → Variable: mc.jaime.class
└── Block "Name" (is_constant)  → NOT a variable
```

**Reference format:** `{page_shortcut}.{variable_name}`

**Block types → Operators:**
- `number`: equals, greater_than, less_than, etc.
- `select`: equals, not_equals, is_nil
- `boolean`: is_true, is_false, is_nil
- `text`: equals, contains, starts_with, is_empty
- Non-variable: `divider`, `reference`

**API:**
```elixir
Pages.list_project_variables(project_id)
# → [%{page_shortcut: "mc.jaime", variable_name: "health", block_type: "number", options: nil}, ...]
```

**Condition structure:**
```elixir
%{
  "logic" => "all",  # "all" (AND) | "any" (OR)
  "rules" => [
    %{"page" => "mc.jaime", "variable" => "health", "operator" => "greater_than", "value" => "50"}
  ]
}
```

## Flow Editor

**Node types:** `start`, `end`, `dialogue`, `condition`, `hub`

**Dialogue node data:**
```elixir
%{
  "speaker_page_id" => nil,
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

**Key files:**
- `lib/storyarn_web/live/flow_live/show.ex` - Main LiveView
- `lib/storyarn_web/live/flow_live/components/properties_panels.ex` - Node panels
- `lib/storyarn_web/live/flow_live/components/node_type_helpers.ex` - Default data
- `assets/js/hooks/flow_canvas/components/storyarn_node.js` - Canvas rendering

## Storyarn-Specific Patterns

**Layouts** (3 independent, not nested):
```elixir
<Layouts.app ...>      # Main app with sidebar
<Layouts.auth ...>     # Login/register (centered)
<Layouts.settings ...> # Settings with nav
```

**LiveView Authorization:**
```elixir
use StoryarnWeb.LiveHelpers.Authorize

case authorize(socket, :edit_content) do
  :ok -> # proceed
  {:error, :unauthorized} -> put_flash(socket, :error, gettext("..."))
end
```
Actions: `:edit_content`, `:manage_project`, `:manage_members`, `:manage_workspace`

**Components** (`StoryarnWeb.Components.*`):
- `MemberComponents` - user_avatar, member_row, invitation_row
- `BlockComponents` - Page block rendering
- `TreeComponents` - Notion-style navigation
- `CollaborationComponents` - Presence, cursors
- `Sidebar`, `ProjectSidebar`, `SaveIndicator`

## Implementation Status

**Completed:** Auth, Workspaces, Projects, Pages/Blocks, Assets, Flow Editor, Collaboration, Dialogue Enhancement (1-4), Flow Node Improvements (Phases 1-2)

**In Progress:** Instruction Node + Variable System

**Next:** Dialogue Enhancement (5-7), Connection hardening, Export system
