# Storyarn - Implementation Plan

> **Goal:** Build an "articy killer" - a web-based narrative design platform with real-time collaboration

## Confirmed Stack

- **Backend:** Elixir + Phoenix 1.8 + LiveView
- **Frontend:** LiveView + Rete.js (flow editor)
- **Database:** PostgreSQL + Redis
- **Auth:** Email/password + OAuth (GitHub, Google, Discord)
- **Collaboration:** Optimistic locking (evolve to CRDT later)
- **i18n:** Gettext (included with Phoenix)
- **Rust:** Deferred until there's a real performance need

## Development Tools

| Tool          | Purpose                                 | Command              |
|---------------|-----------------------------------------|----------------------|
| **Credo**     | Linting, code style, consistency        | `mix credo --strict` |
| **Sobelow**   | Security vulnerability scanning         | `mix sobelow`        |
| **Dialyxir**  | Static type analysis (Dialyzer wrapper) | `mix dialyzer`       |
| **ExMachina** | Test factories                          | Used in tests        |
| **Mox**       | Mocking (behaviours-based)              | Used in tests        |
| **Faker**     | Random test data generation             | Used in tests        |

### Dialyzer Notes

First run builds a PLT (Persistent Lookup Table) and takes several minutes. Subsequent runs are fast.

```bash
# First time setup (slow, ~5 min)
mix dialyzer

# Subsequent runs (fast)
mix dialyzer --format short
```

Add `@spec` annotations to functions for better type checking:

```elixir
@spec create_project(User.t(), map()) :: {:ok, Project.t()} | {:error, Ecto.Changeset.t()}
def create_project(user, attrs) do
  # ...
end
```

### Test Factories (ExMachina)

```elixir
# test/support/factory.ex
defmodule Storyarn.Factory do
  use ExMachina.Ecto, repo: Storyarn.Repo

  def user_factory do
    %Storyarn.Accounts.User{
      email: sequence(:email, &"user#{&1}@example.com"),
      display_name: Faker.Person.name(),
      hashed_password: Bcrypt.hash_pwd_salt("password123")
    }
  end

  def project_factory do
    %Storyarn.Projects.Project{
      name: Faker.Company.name(),
      description: Faker.Lorem.paragraph(),
      owner: build(:user)
    }
  end
end
```

Usage in tests:

```elixir
# Build (in-memory)
user = build(:user)

# Insert (persisted to DB)
user = insert(:user)

# With overrides
admin = insert(:user, role: :admin)

# With associations
project = insert(:project, owner: insert(:user))
```

### Mocking with Mox

For external services (OAuth, emails, APIs):

```elixir
# test/support/mocks.ex
Mox.defmock(Storyarn.HTTPClientMock, for: Storyarn.HTTPClient.Behaviour)
Mox.defmock(Storyarn.MailerMock, for: Storyarn.Mailer.Behaviour)

# In test
import Mox

setup :verify_on_exit!

test "sends welcome email" do
  expect(Storyarn.MailerMock, :deliver, fn email ->
    assert email.to == "user@example.com"
    {:ok, %{}}
  end)

  # ... test code
end
```

---

## MVP Phases

### Phase 0: Base Infrastructure (Complete)
- [x] Phoenix project created
- [x] Docker compose (PostgreSQL + Redis)
- [x] Credo + Sobelow configured
- [x] Configure TailwindCSS v4 (with daisyUI)
- [x] Configure Biome for JS (lint + format)
- [x] Configure Gettext locales (en, es)
- [x] Basic CI setup (GitHub Actions)
- [x] Playwright E2E test structure

### Phase 1: Auth & Users (Complete)
- [x] User schema
- [x] Registration/login with email + password
- [x] OAuth with GitHub
- [x] OAuth with Google
- [x] OAuth with Discord
- [x] Email verification (via magic link)
- [x] Password reset (via magic link - users can login with magic link and set a new password in settings)
- [x] Session management
- [x] Profile settings (display name, avatar)
- [x] Connected accounts management (link/unlink OAuth providers)

> **Note on Password Reset:** Instead of a traditional "forgot password" flow, we use magic links.
> Users who forgot their password can request a magic link via the login page, which logs them in
> directly. Once logged in, they can set a new password in the settings page. This approach is
> simpler, more secure (no password reset tokens to expire), and provides a better UX.

### Phase 2: Projects & Teams (1 week)
- [ ] Project schema
- [ ] Project CRUD
- [ ] Project dashboard
- [ ] Project invitations
- [ ] Roles (owner, editor, viewer)
- [ ] Project settings

### Phase 3: Domain Model - Entities (2 weeks)
- [ ] Entity templates
- [ ] Characters
- [ ] Locations
- [ ] Items
- [ ] Variables (game state)
- [ ] Assets (images, audio)
- [ ] CRUD for each type
- [ ] Entity browser (sidebar)
- [ ] Search and filtering

### Phase 4: Flow Editor - Core (3 weeks)
- [ ] Flow schema
- [ ] Node schema (types: dialogue, hub, condition, instruction, jump)
- [ ] Connection schema
- [ ] Rete.js integration with LiveView
- [ ] Node rendering
- [ ] Node drag & drop
- [ ] Node connections
- [ ] Node properties panel
- [ ] Canvas zoom & pan
- [ ] Mini-map

### Phase 5: Flow Editor - Dialogue (2 weeks)
- [ ] Dialogue node with speaker selector
- [ ] Rich text editor for dialogues
- [ ] Branches/response options
- [ ] Conditions on branches
- [ ] Dialogue preview
- [ ] Variables in text (interpolation)

### Phase 6: Basic Collaboration (1 week)
- [ ] Phoenix Presence (who's online)
- [ ] Other users' cursors
- [ ] Node locking (who's editing)
- [ ] Visual editing indicators
- [ ] Change notifications

### Phase 7: Export (1 week)
- [ ] Export to JSON (custom format)
- [ ] Export to JSON (articy-compatible format)
- [ ] Import from JSON
- [ ] Pre-export validation

### Phase 8: Polish & Production (1 week)
- [ ] Performance profiling
- [ ] UX refinements
- [ ] Production deployment setup
- [ ] Monitoring & logging

---

## 🌍 Internationalization (i18n)

> **Fundamental rule:** All user-facing text MUST be localized. No hardcoded strings in templates or controllers.

### Technology: Gettext (Built-in)

Phoenix includes [Gettext](https://github.com/elixir-gettext/gettext) out of the box. No additional dependencies needed.

### Supported Locales

Initial locales:
- `en` - English (default)
- `es` - Spanish

More can be added later via `mix gettext.merge priv/gettext --locale <locale>`.

### File Structure

```
priv/gettext/
├── default.pot                    # Template (extracted strings)
├── errors.pot                     # Ecto/validation errors template
├── en/
│   └── LC_MESSAGES/
│       ├── default.po             # English translations
│       └── errors.po
└── es/
    └── LC_MESSAGES/
        ├── default.po             # Spanish translations
        └── errors.po
```

### Usage Patterns

#### In Templates (HEEx)
```heex
<h1><%= gettext("Welcome to Storyarn") %></h1>
<p><%= gettext("Create your first project") %></p>

<%!-- With interpolation --%>
<p><%= gettext("Hello, %{name}!", name: @user.name) %></p>

<%!-- Pluralization --%>
<p><%= ngettext("1 project", "%{count} projects", @count) %></p>
```

#### In LiveView/Controllers
```elixir
def mount(_params, _session, socket) do
  {:ok, assign(socket, page_title: gettext("Dashboard"))}
end

def handle_event("save", params, socket) do
  case save_project(params) do
    {:ok, _} ->
      {:noreply, put_flash(socket, :info, gettext("Project saved successfully"))}
    {:error, _} ->
      {:noreply, put_flash(socket, :error, gettext("Failed to save project"))}
  end
end
```

#### In Ecto Changesets
```elixir
def changeset(project, attrs) do
  project
  |> cast(attrs, [:name, :description])
  |> validate_required([:name], message: dgettext("errors", "can't be blank"))
  |> validate_length(:name, min: 3, message: dgettext("errors", "must be at least 3 characters"))
end
```

### Locale Detection & Switching

```elixir
# lib/storyarn_web/plugs/locale.ex
defmodule StoryarnWeb.Plugs.Locale do
  import Plug.Conn

  @locales Gettext.known_locales(StoryarnWeb.Gettext)

  def init(default), do: default

  def call(conn, default) do
    locale =
      get_locale_from_params(conn) ||
      get_locale_from_session(conn) ||
      get_locale_from_header(conn) ||
      default

    Gettext.put_locale(StoryarnWeb.Gettext, locale)
    conn |> put_session(:locale, locale)
  end

  defp get_locale_from_params(conn) do
    conn.params["locale"] |> validate_locale()
  end

  defp get_locale_from_session(conn) do
    get_session(conn, :locale) |> validate_locale()
  end

  defp get_locale_from_header(conn) do
    conn
    |> get_req_header("accept-language")
    |> List.first()
    |> parse_accept_language()
    |> validate_locale()
  end

  defp validate_locale(locale) when locale in @locales, do: locale
  defp validate_locale(_), do: nil

  defp parse_accept_language(nil), do: nil
  defp parse_accept_language(header) do
    header |> String.split(",") |> List.first() |> String.split("-") |> List.first()
  end
end
```

### LiveView Locale Handling

```elixir
# lib/storyarn_web/live/live_helpers.ex
defmodule StoryarnWeb.LiveHelpers do
  def on_mount(:default, _params, session, socket) do
    locale = session["locale"] || "en"
    Gettext.put_locale(StoryarnWeb.Gettext, locale)
    {:cont, socket}
  end
end

# In router.ex
live_session :authenticated, on_mount: [StoryarnWeb.LiveHelpers] do
  # ...
end
```

### Workflow Commands

```bash
# Extract all gettext calls from source code
mix gettext.extract

# Merge extracted strings into locale files
mix gettext.merge priv/gettext

# Extract and merge in one step
mix gettext.extract --merge

# Add a new locale
mix gettext.merge priv/gettext --locale fr
```

### Configuration

```elixir
# config/config.exs
config :storyarn, StoryarnWeb.Gettext,
  default_locale: "en",
  locales: ~w(en es)

# config/dev.exs (optional: warn on missing translations)
config :gettext, :default_locale, "en"
```

### i18n Rules

1. **Never hardcode user-facing strings** - Always use `gettext/1`, `dgettext/2`, or `ngettext/3`
2. **Use domains for organization** - `dgettext("errors", ...)`, `dgettext("emails", ...)`
3. **Keep keys in English** - The English text serves as the key and fallback
4. **Extract regularly** - Run `mix gettext.extract --merge` after adding new strings
5. **Test both locales** - Verify UI doesn't break with longer Spanish translations

### UI Language Switcher

Add a language switcher component to the layout:

```heex
<%!-- lib/storyarn_web/components/layouts/app.html.heex --%>
<div class="locale-switcher">
  <.link href={"?locale=en"} class={@locale == "en" && "active"}>EN</.link>
  <.link href={"?locale=es"} class={@locale == "es" && "active"}>ES</.link>
</div>
```

---

## 🧪 Testing Strategy

> **Fundamental rule:** All new code MUST have tests. A feature is not considered complete without its corresponding tests.

### Testing Levels

#### 1. Unit Tests (Contexts)
Tests for pure business logic in each context.

```
test/storyarn/
├── accounts_test.exs
├── projects_test.exs
├── entities_test.exs
├── flows_test.exs
├── collaboration_test.exs
└── exports_test.exs
```

**Required coverage:**
- All public context functions
- Changeset validations
- Domain logic

#### 2. Integration Tests (LiveView)
Integration tests for LiveViews and components.

```
test/storyarn_web/live/
├── auth/
│   ├── login_live_test.exs
│   ├── register_live_test.exs
│   └── reset_password_live_test.exs
├── dashboard_live_test.exs
├── project/
│   └── project_settings_live_test.exs
└── editor/
    ├── flow_editor_live_test.exs
    └── entity_browser_live_test.exs
```

**Required coverage:**
- Initial render
- User events (clicks, forms)
- State updates
- Navigation

#### 3. E2E Tests (Playwright)
End-to-end tests simulating real users in the browser.

```
e2e/
├── playwright.config.ts
├── fixtures/
│   └── auth.ts              # Login helpers
├── tests/
│   ├── auth.spec.ts         # Login, register, OAuth
│   ├── projects.spec.ts     # Project CRUD
│   ├── entities.spec.ts     # Entity CRUD
│   ├── flow-editor.spec.ts  # Flow editor (critical)
│   └── collaboration.spec.ts # Multi-user
└── utils/
    └── helpers.ts
```

**Critical E2E scenarios:**
- [ ] Complete registration/login flow
- [ ] Create and configure project
- [ ] Create entities (character, location)
- [ ] Flow editor: create nodes, connect, move
- [ ] Collaboration: two users editing simultaneously
- [ ] Export/Import project

### Playwright Setup

```bash
# Installation
cd e2e
npm init -y
npm install -D @playwright/test
npx playwright install
```

```typescript
// e2e/playwright.config.ts
import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './tests',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: 'html',
  use: {
    baseURL: 'http://localhost:4000',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },
  webServer: {
    command: 'mix phx.server',
    url: 'http://localhost:4000',
    reuseExistingServer: !process.env.CI,
    cwd: '..',
  },
});
```

### Testing Commands

```bash
# Unit + Integration tests
mix test                      # All tests
mix test --cover              # With coverage
mix test test/storyarn/       # Unit tests only
mix test test/storyarn_web/   # Integration tests only

# E2E tests (Playwright)
cd e2e && npx playwright test              # All E2E
cd e2e && npx playwright test --ui         # Visual mode
cd e2e && npx playwright test --debug      # Debug mode
cd e2e && npx playwright show-report       # View report

# Before commit
mix precommit                 # Compile + format + test
```

### Testing Requirements by Phase

| Phase                  | Required Tests                                                      |
|------------------------|---------------------------------------------------------------------|
| Phase 1: Auth          | Unit (Accounts) + LiveView (auth flows) + E2E (login/register)      |
| Phase 2: Projects      | Unit (Projects) + LiveView (dashboard, settings) + E2E (CRUD)       |
| Phase 3: Entities      | Unit (Entities) + LiveView (browser, forms) + E2E (CRUD)            |
| Phase 4: Flow Editor   | Unit (Flows) + LiveView (editor) + E2E (canvas interactions)        |
| Phase 5: Dialogue      | Unit (node types) + LiveView (dialogue panel) + E2E (full dialogue) |
| Phase 6: Collaboration | Unit (locks) + Channel tests + E2E (multi-user)                     |
| Phase 7: Export        | Unit (exporters) + E2E (export/import cycle)                        |

### CI Pipeline

```yaml
# .github/workflows/ci.yml
name: CI
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: postgres
        ports: ['5432:5432']
      redis:
        image: redis:7
        ports: ['6379:6379']

    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.15'
          otp-version: '26'

      - run: mix deps.get
      - run: mix compile --warnings-as-errors
      - run: mix format --check-formatted
      - run: mix credo --strict
      - run: mix test --cover

      # E2E tests
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - run: cd e2e && npm ci
      - run: cd e2e && npx playwright install --with-deps
      - run: cd e2e && npx playwright test

      - uses: actions/upload-artifact@v4
        if: failure()
        with:
          name: playwright-report
          path: e2e/playwright-report/
```

---

## Phoenix Context Architecture

```
lib/storyarn/
├── accounts/           # Users, auth, sessions
│   ├── user.ex
│   ├── user_token.ex
│   └── accounts.ex
│
├── projects/           # Projects, memberships
│   ├── project.ex
│   ├── membership.ex
│   └── projects.ex
│
├── entities/           # Characters, locations, items, variables
│   ├── entity.ex
│   ├── template.ex
│   ├── character.ex
│   ├── location.ex
│   ├── item.ex
│   ├── variable.ex
│   └── entities.ex
│
├── flows/              # Flows, nodes, connections
│   ├── flow.ex
│   ├── node.ex
│   ├── connection.ex
│   ├── node_types/
│   │   ├── dialogue.ex
│   │   ├── hub.ex
│   │   ├── condition.ex
│   │   ├── instruction.ex
│   │   └── jump.ex
│   └── flows.ex
│
├── collaboration/      # Presence, locking
│   ├── presence.ex
│   ├── lock.ex
│   └── collaboration.ex
│
├── exports/            # Export/import logic
│   ├── json_exporter.ex
│   ├── articy_exporter.ex
│   ├── importer.ex
│   └── exports.ex
│
└── assets/             # File uploads
    ├── asset.ex
    └── assets.ex
```

```
lib/storyarn_web/
├── components/         # Reusable components
├── controllers/        # Auth callbacks, exports
├── channels/           # Real-time collaboration
│   ├── project_channel.ex
│   └── user_socket.ex
├── live/
│   ├── auth/           # Login, register, etc
│   ├── dashboard/      # Project list
│   ├── project/        # Project settings
│   ├── editor/         # Main editor
│   │   ├── flow_editor_live.ex
│   │   ├── entity_browser_live.ex
│   │   └── properties_panel_live.ex
│   └── components/     # LiveComponents
└── hooks/              # JS hooks for Rete.js
```

---

## Database Schema (Initial)

### Users & Auth
```elixir
# users
- id: uuid
- email: string (unique)
- hashed_password: string
- confirmed_at: datetime
- avatar_url: string
- display_name: string
- timestamps

# user_tokens
- id: uuid
- user_id: uuid
- token: binary
- context: string (session, reset_password, confirm)
- sent_to: string
- timestamps

# user_identities (OAuth)
- id: uuid
- user_id: uuid
- provider: string (github, google, discord)
- provider_id: string
- provider_email: string
- provider_token: string (encrypted)
- timestamps
```

### Projects
```elixir
# projects
- id: uuid
- name: string
- description: text
- owner_id: uuid -> users
- settings: map (jsonb)
- timestamps

# project_memberships
- id: uuid
- project_id: uuid
- user_id: uuid
- role: enum (owner, editor, viewer)
- timestamps
```

### Entities
```elixir
# entity_templates
- id: uuid
- project_id: uuid
- name: string
- type: enum (character, location, item, custom)
- schema: map (jsonb) # Defines custom fields
- timestamps

# entities
- id: uuid
- project_id: uuid
- template_id: uuid
- display_name: string
- technical_name: string
- color: string
- data: map (jsonb) # Fields according to template
- timestamps

# variables
- id: uuid
- project_id: uuid
- name: string
- type: enum (boolean, integer, string)
- default_value: string
- description: text
- timestamps
```

### Flows
```elixir
# flows
- id: uuid
- project_id: uuid
- name: string
- description: text
- is_main: boolean
- settings: map
- timestamps

# flow_nodes
- id: uuid
- flow_id: uuid
- type: enum (dialogue, hub, condition, instruction, jump)
- position_x: float
- position_y: float
- data: map (jsonb) # Content according to type
- timestamps

# flow_connections
- id: uuid
- flow_id: uuid
- source_node_id: uuid
- source_pin: string (default, option_1, etc)
- target_node_id: uuid
- target_pin: string
- label: string
- condition: text
- timestamps
```

### Collaboration
```elixir
# node_locks
- id: uuid
- node_id: uuid
- user_id: uuid
- locked_at: datetime
- expires_at: datetime
```

---

## Rete.js + LiveView Integration

### Hybrid Strategy

1. **LiveView** handles:
   - Flow state (nodes, connections)
   - Persistence
   - Collaboration (change broadcasting)
   - Properties panel

2. **Rete.js (JS Hook)** handles:
   - Canvas rendering
   - Drag & drop
   - Zoom/pan
   - Visual interaction

3. **Bidirectional communication:**
   ```
   LiveView State <---> JS Hook <---> Rete.js Canvas
                    pushEvent/handleEvent
   ```

### Basic Hook
```javascript
// assets/js/hooks/flow_canvas.js
import { createEditor } from "../flow_editor/editor"

export const FlowCanvas = {
  mounted() {
    const initialData = JSON.parse(this.el.dataset.flowData)

    this.editor = createEditor(this.el, {
      nodes: initialData.nodes,
      connections: initialData.connections,

      // Events to LiveView
      onNodeMoved: (nodeId, x, y) => {
        this.pushEvent("node_moved", { id: nodeId, x, y })
      },
      onNodeSelected: (nodeId) => {
        this.pushEvent("node_selected", { id: nodeId })
      },
      onConnectionCreated: (source, target) => {
        this.pushEvent("connection_created", { source, target })
      },
      onNodeDeleted: (nodeId) => {
        this.pushEvent("node_deleted", { id: nodeId })
      }
    })

    // Events from LiveView (other users)
    this.handleEvent("node_updated", (node) => {
      this.editor.updateNode(node)
    })
    this.handleEvent("node_added", (node) => {
      this.editor.addNode(node)
    })
    this.handleEvent("node_removed", (nodeId) => {
      this.editor.removeNode(nodeId)
    })
  },

  updated() {
    // Sync when LiveView updates data
    const data = JSON.parse(this.el.dataset.flowData)
    this.editor.sync(data)
  },

  destroyed() {
    this.editor.destroy()
  }
}
```

---

## Node Types (articy-like)

### 1. Dialogue Node
```elixir
%{
  type: :dialogue,
  data: %{
    speaker_id: "entity-uuid",      # Who speaks
    text: "Hello, traveler!",       # Dialogue
    menu_text: "Greet",             # Short text for options
    stage_directions: "smiling",    # Acting directions
    features: %{                    # Custom fields
      emotion: "happy",
      voice_style: "cheerful"
    }
  }
}
```

### 2. Hub Node
```elixir
%{
  type: :hub,
  data: %{
    display_name: "Quest Start",
    # No narrative content, just a connection point
  }
}
```

### 3. Condition Node
```elixir
%{
  type: :condition,
  data: %{
    expression: "player_gold >= 100 and quest_accepted",
    # Outputs: true_pin, false_pin
  }
}
```

### 4. Instruction Node
```elixir
%{
  type: :instruction,
  data: %{
    instructions: [
      %{action: "set_variable", variable: "quest_started", value: true},
      %{action: "add_item", item_id: "entity-uuid", quantity: 1},
      %{action: "trigger_event", event: "cutscene_1"}
    ]
  }
}
```

### 5. Jump Node
```elixir
%{
  type: :jump,
  data: %{
    target_flow_id: "flow-uuid",
    target_node_id: "node-uuid"  # optional, flow start if nil
  }
}
```

---

## Milestones

### Milestone 1: "Hello Flow" (2 weeks)
**Goal:** Be able to create a project, add a flow, and place basic nodes.

Deliverables:
- Working auth (email + GitHub)
- Project CRUD
- Basic flow editor with Rete.js
- Hub-type nodes (no content)
- Basic connections

### Milestone 2: "First Dialogue" (2 weeks)
**Goal:** Be able to create a complete dialogue with a character.

Deliverables:
- Entity CRUD (Characters)
- Dialogue node with speaker
- Text editor for dialogues
- Response options (branches)

### Milestone 3: "Team Play" (1 week)
**Goal:** Basic collaboration working.

Deliverables:
- Invite users to project
- Presence (see who's online)
- Node locking
- Change broadcasting

### Milestone 4: "Ship It" (1 week)
**Goal:** Be able to export and use the content.

Deliverables:
- Export to JSON
- Import from JSON
- Flow validation
- Production deploy

---

## Immediate Next Steps

1. **Configure Tailwind** properly for the project
2. **Generate auth with `mix phx.gen.auth`**
3. **Create migrations** for users, projects, entities, flows
4. **Setup OAuth** with `ueberauth`
5. **Create base LiveView** for the editor
6. **Integrate Rete.js** with basic hook

---

## Dependencies to Add

```elixir
# mix.exs
{:ueberauth, "~> 0.10"},
{:ueberauth_github, "~> 0.8"},
{:ueberauth_google, "~> 0.12"},
{:ueberauth_discord, "~> 0.1"},  # or implement custom
{:argon2_elixir, "~> 4.0"},       # password hashing
{:redix, "~> 1.3"},               # Redis client
{:cachex, "~> 3.6"},              # Caching
{:oban, "~> 2.17"},               # Background jobs
{:ex_aws, "~> 2.5"},              # S3 uploads
{:ex_aws_s3, "~> 2.5"},
{:hackney, "~> 1.20"},            # HTTP client
```

```javascript
// package.json (assets/)
"rete": "^2.0.0",
"rete-area-plugin": "^2.0.0",
"rete-connection-plugin": "^2.0.0",
"rete-render-utils": "^2.0.0",
"@rete/render-utils": "^2.0.0",
// Choose renderer: vanilla, react, vue, svelte
```

---

## Technical Notes

### Rete.js 2.0 vs 1.x
Use Rete.js **v2** which has better architecture:
- Plugin system
- Multiple renderers
- Better TypeScript support
- More lightweight

### LiveView vs SPA for Editor
**LiveView is correct** for this case because:
- Centralized state (easier collaboration)
- No offline requirement
- Heavy canvas is in JS anyway
- Simplifies auth and sessions

### Redis Usage
- **PubSub:** Broadcasting changes between cluster nodes
- **Cache:** Active flows, frequently used entities
- **Locks:** Distributed locks for editing

---

*Living document - update as the project progresses*
