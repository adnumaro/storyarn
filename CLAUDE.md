# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Storyarn is a narrative design platform (an "articy killer") built with Elixir/Phoenix 1.8. It provides collaborative, real-time narrative flow editing for game development and interactive storytelling.

**Stack:** Elixir 1.15+ / Phoenix 1.8 / LiveView 1.1 / PostgreSQL / Redis / Tailwind v4 / daisyUI / Resend (email)

## Related Documentation

**Read these files for complete project guidance:**

- `AGENTS.md` - Detailed Phoenix/LiveView/Ecto guidelines and patterns (MUST READ)
- `IMPLEMENTATION_PLAN.md` - Full roadmap, architecture, and task breakdown

## Language Policy

**Everything in this project MUST be written in English:**
- Code comments
- Documentation (README, CLAUDE.md, etc.)
- Commit messages
- Variable/function/module names
- Error messages and logs
- Gettext keys (the English text serves as the key)
- Test descriptions

No exceptions.

### Localization (i18n)

**All user-facing text MUST be localized using Gettext.** Never hardcode strings in templates or controllers.

```elixir
# ✅ Correct
<h1><%= gettext("Welcome") %></h1>
put_flash(socket, :info, gettext("Project saved"))

# ❌ Wrong - hardcoded string
<h1>Welcome</h1>
put_flash(socket, :info, "Project saved")
```

Supported locales: `en` (default), `es`. See `IMPLEMENTATION_PLAN.md` for full i18n guide.

## Common Commands

```bash
# Development
mix setup                    # Install deps, setup DB, build assets
mix phx.server               # Start dev server (localhost:4000)
iex -S mix phx.server        # Start with interactive shell

# Database
mix ecto.create              # Create database
mix ecto.migrate             # Run migrations
mix ecto.reset               # Drop and recreate DB with seeds

# Testing
mix test                     # Run all tests (excludes E2E)
mix test test/path_test.exs  # Run single test file
mix test --failed            # Rerun failed tests
mix test.e2e                 # Run E2E tests (Playwright)

# Code Quality
mix precommit                # Run before committing: compile, format, credo, test
mix credo --strict           # Static analysis (style/consistency)
mix dialyzer                 # Static type analysis (run separately, slow first time)
mix sobelow                  # Security scanning
mix format                   # Format code

# Docker (PostgreSQL + Redis + Mailpit)
docker compose up -d         # Start services
docker compose down          # Stop services

# JavaScript (from assets/)
npm run check                # Lint + format check (Biome)
npm run check:fix            # Auto-fix issues
```

## Email (Mailer)

- **Development**: Mailpit (SMTP on `localhost:1025`, Web UI at `http://localhost:8025`)
- **Production**: Resend API (configure `RESEND_API_KEY`)
- **Test**: `Swoosh.Adapters.Test` (no emails sent)

```bash
# Start Mailpit
docker compose up -d mailpit

# View emails in browser
open http://localhost:8025
```

## Rate Limiting

Auth endpoints are protected by rate limiting via `Storyarn.RateLimiter`:

| Endpoint       | Limit              | Key           |
|----------------|--------------------|--------------|
| Login          | 5/min              | IP address    |
| Magic link     | 3/min              | Email         |
| Registration   | 3/min              | IP address    |
| Invitations    | 10/hour/workspace  | User + target |

**Configuration:**
- Development/Test: ETS backend (in-memory)
- Production: Redis backend (configure `REDIS_URL`)
- Disabled in tests via `config :storyarn, Storyarn.RateLimiter, enabled: false`

## Architecture

```
lib/
├── storyarn/                    # Domain/Business Logic (Contexts)
│   ├── accounts.ex              # Facade → accounts/*.ex submodules
│   ├── accounts/
│   │   ├── users.ex             # User lookups
│   │   ├── registration.ex      # User registration
│   │   ├── oauth.ex             # OAuth identity management
│   │   ├── sessions.ex          # Session tokens
│   │   ├── magic_links.ex       # Magic link auth
│   │   ├── emails.ex            # Email changes
│   │   ├── passwords.ex         # Password management
│   │   └── profiles.ex          # Profile and sudo mode
│   ├── workspaces.ex            # Facade → workspaces/*.ex submodules
│   ├── workspaces/
│   │   ├── workspace_crud.ex    # CRUD operations
│   │   ├── memberships.ex       # Member management
│   │   ├── invitations.ex       # Invitation management
│   │   └── slug_generator.ex    # Unique slug generation
│   ├── projects.ex              # Facade → projects/*.ex submodules
│   ├── projects/
│   │   ├── project_crud.ex      # CRUD operations
│   │   ├── memberships.ex       # Member management
│   │   └── invitations.ex       # Invitation management
│   ├── pages.ex                 # Facade → pages/*.ex submodules
│   ├── pages/
│   │   ├── page_crud.ex         # Page CRUD operations
│   │   ├── block_crud.ex        # Block CRUD operations
│   │   └── tree_operations.ex   # Tree reordering
│   ├── flows.ex                 # Facade → flows/*.ex submodules
│   ├── flows/
│   │   ├── flow_crud.ex         # Flow CRUD operations
│   │   ├── node_crud.ex         # Node CRUD operations
│   │   └── connection_crud.ex   # Connection CRUD operations
│   ├── collaboration.ex         # Facade → collaboration/*.ex submodules
│   ├── collaboration/
│   │   ├── presence.ex          # Phoenix.Presence for online users
│   │   ├── cursor_tracker.ex    # PubSub cursor broadcasting
│   │   ├── locks.ex             # Node locking (GenServer)
│   │   └── colors.ex            # Deterministic user colors
│   ├── assets/                  # File uploads (R2/S3)
│   ├── rate_limiter.ex          # Rate limiting for auth endpoints
│   ├── application.ex           # OTP supervision tree
│   ├── repo.ex                  # Ecto repository
│   └── mailer.ex                # Email via Swoosh
│
├── storyarn_web/                # Web Layer
│   ├── components/
│   │   ├── core_components.ex   # UI components (<.input>, <.button>, <.icon>)
│   │   ├── layouts.ex           # Layouts (app, auth, settings)
│   │   ├── member_components.ex # Member/invitation display
│   │   ├── collaboration_components.ex # Online users, lock indicators
│   │   ├── block_components.ex  # Page block rendering
│   │   └── sidebar.ex           # Workspace sidebar
│   ├── controllers/             # Non-LiveView routes (OAuth, exports)
│   ├── live/                    # LiveView modules
│   │   ├── settings_live/       # User & workspace settings
│   │   ├── workspace_live/      # Workspace views
│   │   ├── project_live/        # Project views
│   │   ├── page_live/           # Page editor
│   │   └── flow_live/           # Flow editor
│   ├── live_helpers/            # LiveView helpers (authorization)
│   ├── channels/                # WebSocket channels (real-time)
│   ├── endpoint.ex              # Plug pipeline
│   └── router.ex                # Route definitions
│
├── storyarn.ex                  # Main module
└── storyarn_web.ex              # Web macros (:html, :live_view, :controller)
```

## Domain Model

### Workspaces & Projects

The app uses a **workspace-centric** navigation model:
- **Workspaces** are the top-level containers (like organizations)
- **Projects** belong to a workspace
- Users can belong to multiple workspaces with different roles
- Each user gets a default workspace on registration

```
User
 └── WorkspaceMembership (role: owner|admin|member|viewer)
      └── Workspace
           └── Project
                └── ProjectMembership (role: owner|editor|viewer)
                     └── Entities, Templates, Variables, Flows
```

### Roles & Permissions

**Workspace roles:**
- `owner` - Full control, can delete workspace, manage all members
- `admin` - Can manage members, create projects
- `member` - Can create projects, view workspace
- `viewer` - Read-only access

**Project roles:**
- `owner` - Full control, can delete project
- `editor` - Can edit content (entities, flows, etc.)
- `viewer` - Read-only access

Use `ProjectMembership.can?(role, action)` or `WorkspaceMembership.can?(role, action)` to check permissions.

## Key Conventions

### Context Organization (Facade Pattern)

Large contexts are split into focused submodules using the **facade pattern with `defdelegate`**:

```elixir
# Main context file (facade) - lib/storyarn/projects.ex
defmodule Storyarn.Projects do
  @moduledoc """
  The Projects context. Delegates to specialized submodules.
  """

  alias Storyarn.Projects.{Invitations, Memberships, ProjectCrud}

  # Delegations with full documentation
  @doc "Lists all projects the user has access to."
  defdelegate list_projects(scope), to: ProjectCrud

  @doc "Creates an invitation and sends the invitation email."
  defdelegate create_invitation(project, invited_by, email, role \\ "editor"), to: Invitations
end

# Submodule - lib/storyarn/projects/project_crud.ex
defmodule Storyarn.Projects.ProjectCrud do
  @moduledoc false  # Internal module, docs in facade

  def list_projects(scope), do: # implementation
end
```

**Guidelines:**
- Contexts should be **< 200-300 lines** - split if larger
- Main context file is the **public API** with `@doc` for each function
- Submodules use `@moduledoc false` (internal implementation)
- Group related functions in submodules (CRUD, memberships, invitations, etc.)

### Credo Conventions

Follow these Credo rules (enforced by `mix credo --strict`):

```elixir
# ❌ Wrong - single-clause `with` should use `case`
with :ok <- authorize(socket, :edit) do
  perform_action()
else
  {:error, :unauthorized} -> handle_error()
end

# ✅ Correct - use `case` for single conditions
case authorize(socket, :edit) do
  :ok -> perform_action()
  {:error, :unauthorized} -> handle_error()
end

# ❌ Wrong - nesting depth > 2
def handle_event("action", _, socket) do
  if condition1 do
    if condition2 do
      case result do  # Too deep!
        :ok -> ...
      end
    end
  end
end

# ✅ Correct - extract to private functions
def handle_event("action", _, socket) do
  if condition1 do
    do_action(socket)
  end
end

defp do_action(socket) do
  if condition2 do
    perform_action(socket)
  end
end
```

**Additional rules:**
- All modules must have `@moduledoc` (use `@moduledoc false` for internal modules)
- Group all clauses of same function together (no private functions in between)
- Alphabetize alias lists: `alias Storyarn.{Accounts, Projects, Workspaces}`

### Layouts

Three independent layouts (not nested):

```elixir
# Main app with workspace sidebar
<Layouts.app flash={@flash} current_scope={@current_scope} workspaces={@workspaces}>

# Auth pages (login, register) - centered, no sidebar
<Layouts.auth flash={@flash}>

# Settings pages - header + settings nav, no workspace sidebar
<Layouts.settings flash={@flash} current_scope={@current_scope} workspaces={@workspaces} current_path={@current_path}>
  <:title>Page Title</:title>
  <:subtitle>Description</:subtitle>
```

### LiveView Authorization

Use the authorization helper for protecting `handle_event` callbacks:

```elixir
use StoryarnWeb.LiveHelpers.Authorize

def handle_event("delete", _params, socket) do
  case authorize(socket, :edit_content) do
    :ok ->
      # perform action
      {:noreply, socket}

    {:error, :unauthorized} ->
      {:noreply, put_flash(socket, :error, gettext("You don't have permission..."))}
  end
end
```

Available actions: `:edit_content`, `:manage_project`, `:manage_members`, `:manage_workspace`, `:manage_workspace_members`

### Phoenix 1.8 / LiveView

- Use `<.icon name="hero-x-mark">` for Heroicons (never import Heroicons directly)
- Use `<.input field={@form[:field]}>` for form inputs
- Forms must use `to_form/2`: `assign(socket, form: to_form(changeset))`
- Never use `<.form let={f}>`, always use `<.form for={@form}>`
- Use LiveView streams for collections to avoid memory issues
- Routes in scopes are auto-aliased: `live "/users", UserLive` → `StoryarnWeb.UserLive`

### Elixir

- List access: Use `Enum.at(list, i)`, not `list[i]`
- Bind block results: `socket = if condition do ... end`
- Never nest modules in the same file
- Access struct fields directly (`struct.field`), not via Access (`struct[:field]`)
- Changeset fields: `Ecto.Changeset.get_field(changeset, :field)`
- HTTP client: Use `Req` (included), avoid HTTPoison/Tesla

### HEEx Templates

- Interpolation in attributes: `{@value}`, not `<%= %>`
- Block constructs in bodies: `<%= if ... do %>`
- Class lists must use brackets: `class={["base", @flag && "conditional"]}`
- Comments: `<%!-- comment --%>`
- No `if/else if` - use `cond` or `case`

### Ecto

- Schema `:text` columns use `:string` type
- Always preload associations accessed in templates
- Fields set programmatically (like `user_id`) must not be in `cast`
- `validate_number/2` does not support `:allow_nil`

### CSS/JS

- Tailwind v4 uses `@import "tailwindcss"` in app.css (no config file)
- daisyUI is installed via npm (`assets/package.json`), configured via `@plugin "daisyui"` in app.css
- Never use `@apply` in CSS
- All JS must be in `assets/js/`, imported via `app.js`
- No inline `<script>` tags in templates (except minimal theme init in root.html.heex)
- Hooks with managed DOM need `phx-update="ignore"`
- Native `<dialog>` modals use `JS.dispatch("phx:show-modal")` / `JS.dispatch("phx:hide-modal")` (NOT `JS.exec`)

### Shared Components

All components use the `StoryarnWeb.Components.*` namespace:

**MemberComponents** (`import StoryarnWeb.Components.MemberComponents`):
- `<.user_avatar user={@user} size="md" />` - Avatar with initials fallback
- `<.member_row member={@member} current_user_id={@id} can_manage={true} on_remove="remove" />` - Member display
- `<.invitation_row invitation={@inv} on_revoke="revoke" />` - Pending invitation

**CoreComponents** (auto-imported via `use StoryarnWeb, :live_view`):
- `<.empty_state icon="hero-folder-open" title="No items">Description</.empty_state>` - Empty list states
- `<.role_badge role="owner" />` - Role display badge (from UIComponents)

**Other Components:**
- `StoryarnWeb.Components.UIComponents` - OAuth buttons, role badges, empty states
- `StoryarnWeb.Components.TreeComponents` - Notion-style tree navigation
- `StoryarnWeb.Components.CollaborationComponents` - Real-time presence, cursor sharing
- `StoryarnWeb.Components.Sidebar` - Workspace sidebar navigation
- `StoryarnWeb.Components.ProjectSidebar` - Project pages tree sidebar
- `StoryarnWeb.Components.SaveIndicator` - Saving/saved status indicator
- `StoryarnWeb.Components.BlockComponents` - Page block rendering (text, select, etc.)

## Testing

### Unit & Integration Tests
- Use `Phoenix.LiveViewTest` with `LazyHTML` for assertions
- Test element presence with `has_element?(view, "#my-id")`
- Add unique DOM IDs to forms/buttons for testing
- Debug with `LazyHTML.filter(document, "selector") |> IO.inspect()`

### E2E Tests (PhoenixTest.Playwright)
- E2E tests live in `test/e2e/` and use PhoenixTest.Playwright
- Run with `mix test.e2e` (includes asset build)
- Tests are tagged with `@moduletag :e2e` and excluded from regular `mix test`
- Uses Ecto SQL Sandbox for database isolation
- Set `PLAYWRIGHT_HEADLESS=false` to see browser during tests

## Implementation Status

The project is in active development. See `IMPLEMENTATION_PLAN.md` for the full roadmap.

**Completed:**
- Phase 0: Base Infrastructure
- Phase 1: Auth & Users (email/password, OAuth, magic links)
- Phase 2: Workspaces & Projects (CRUD, invitations, roles, settings)
- Phase 3: Pages & Blocks (hierarchical pages, 8 block types)
- Phase 3.2: Assets System (R2 storage, uploads, thumbnails)
- Phase 4: Flow Editor - Core (Rete.js, 5 node types, canvas)
- Phase 5: Flow Editor - Dialogue (rich text, preview, speaker selection)
- Phase 6: Collaboration (presence, cursors, node locking, notifications)

**Next Up:**
- Phase 7: Export (JSON import/export)

**Contexts:**
- `Accounts` - Users, auth, sessions, OAuth identities ✓
- `Workspaces` - Workspaces, memberships, invitations ✓
- `Projects` - Projects, memberships, invitations ✓
- `Pages` - Hierarchical pages, blocks ✓
- `Assets` - File uploads (R2/S3) ✓
- `Flows` - Flow graphs, nodes, connections ✓
- `Collaboration` - Presence, cursors, locking ✓
- `Exports` - JSON import/export (planned)
