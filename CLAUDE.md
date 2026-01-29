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
mix test                     # Run all tests
mix test test/path_test.exs  # Run single test file
mix test --failed            # Rerun failed tests

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

## Architecture

```
lib/
├── storyarn/                    # Domain/Business Logic (Contexts)
│   ├── application.ex           # OTP supervision tree
│   ├── repo.ex                  # Ecto repository
│   └── mailer.ex                # Email via Swoosh
│
├── storyarn_web/                # Web Layer
│   ├── components/
│   │   ├── core_components.ex   # UI components (<.input>, <.button>, <.icon>)
│   │   └── layouts.ex           # App/root layouts
│   ├── controllers/             # Non-LiveView routes
│   ├── live/                    # LiveView modules
│   ├── channels/                # WebSocket channels (real-time)
│   ├── endpoint.ex              # Plug pipeline
│   └── router.ex                # Route definitions
│
├── storyarn.ex                  # Main module
└── storyarn_web.ex              # Web macros (:html, :live_view, :controller)
```

## Key Conventions

### Phoenix 1.8 / LiveView

- Wrap LiveView templates with `<Layouts.app flash={@flash}>...</Layouts.app>`
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
- Never use `@apply` in CSS
- All JS must be in `assets/js/`, imported via `app.js`
- No inline `<script>` tags in templates
- Hooks with managed DOM need `phx-update="ignore"`

## Testing

- Use `Phoenix.LiveViewTest` with `LazyHTML` for assertions
- Test element presence with `has_element?(view, "#my-id")`
- Add unique DOM IDs to forms/buttons for testing
- Debug with `LazyHTML.filter(document, "selector") |> IO.inspect()`

## Implementation Status

The project is in early development (Phase 0). See `IMPLEMENTATION_PLAN.md` for the full roadmap. Planned contexts:

- `Accounts` - Users, auth, sessions
- `Projects` - Projects, memberships, roles
- `Entities` - Characters, locations, items, variables
- `Flows` - Flow graphs, nodes, connections
- `Collaboration` - Presence, locking
- `Exports` - JSON import/export
