# Storyarn - Implementation Plan

> **Goal:** Build an "articy killer" - a web-based narrative design platform with real-time collaboration
>
> **Last Updated:** February 2026

## Confirmed Stack

- **Backend:** Elixir 1.15+ / Phoenix 1.8 / LiveView 1.1
- **Frontend:** LiveView + Rete.js (flow editor) + TailwindCSS v4 + daisyUI v5
- **Database:** PostgreSQL + Redis
- **Auth:** Email/password + OAuth (GitHub, Google, Discord) + Magic Links
- **Storage:** Cloudflare R2 (S3-compatible) / Local for dev
- **Collaboration:** Optimistic locking (evolve to CRDT later)
- **i18n:** Gettext (en, es)
- **Email:** Resend (production) / Mailpit (development)

## Development Tools

| Tool          | Purpose                                 | Command              |
|---------------|-----------------------------------------|----------------------|
| **Credo**     | Linting, code style, consistency        | `mix credo --strict` |
| **Sobelow**   | Security vulnerability scanning         | `mix sobelow`        |
| **Dialyxir**  | Static type analysis (Dialyzer wrapper) | `mix dialyzer`       |
| **ExMachina** | Test factories                          | Used in tests        |
| **Mox**       | Mocking (behaviours-based)              | Used in tests        |
| **Faker**     | Random test data generation             | Used in tests        |
| **Biome**     | JS linting & formatting                 | `npm run check`      |

### Code Conventions (Credo)

The project follows strict Credo rules (`mix credo --strict`):

| Rule                     | Description                                                           |
|--------------------------|-----------------------------------------------------------------------|
| **with → case**          | Single-clause `with` statements should use `case` instead             |
| **Nesting depth**        | Maximum nesting depth is 2 - extract to private functions             |
| **@moduledoc**           | All modules must have `@moduledoc` (use `false` for internal modules) |
| **Function grouping**    | Group all clauses of same function together                           |
| **Alphabetical aliases** | `alias Storyarn.{Accounts, Projects, Workspaces}`                     |

### Image Processing

The project uses **Image** library (libvips bindings) instead of Mogrify/ImageMagick for security reasons:
- ImageMagick: 638 CVEs historically
- libvips: 8 CVEs historically

```elixir
# lib/storyarn/assets/image_processor.ex
Image.thumbnail!(path, max_width, fit: :contain)
```

---

## Current Architecture

### Domain Model

```
users ← user_identities (OAuth providers)
        └→ workspaces (default workspace on signup)
            ├→ workspace_memberships (owner, admin, member, viewer)
            ├→ workspace_invitations
            └→ projects
                ├→ project_memberships (owner, editor, viewer)
                ├→ project_invitations
                ├→ pages (hierarchical tree with parent_id)
                │   └→ blocks (text, rich_text, number, select, multi_select, date, divider)
                ├→ assets (file uploads)
                └→ flows
                    ├→ flow_nodes (dialogue, hub, condition, instruction, jump)
                    └→ flow_connections
```

### Context Organization (Facade Pattern)

Large contexts are split into submodules with the main file as a facade using `defdelegate`:

```
lib/storyarn/
├── accounts.ex              # Facade (public API)
├── accounts/
│   ├── user.ex              # Schema
│   ├── user_token.ex        # Schema
│   ├── user_identity.ex     # Schema (OAuth)
│   ├── users.ex             # User lookups
│   ├── registration.ex      # Registration
│   ├── oauth.ex             # OAuth identity management
│   ├── sessions.ex          # Session tokens
│   ├── magic_links.ex       # Magic link auth
│   ├── emails.ex            # Email changes
│   ├── passwords.ex         # Password management
│   └── profiles.ex          # Profile and sudo mode
│
├── workspaces.ex            # Facade
├── workspaces/
│   ├── workspace.ex, workspace_membership.ex, workspace_invitation.ex
│   ├── workspace_crud.ex, memberships.ex, invitations.ex, slug_generator.ex
│
├── projects.ex              # Facade
├── projects/
│   ├── project.ex, project_membership.ex, project_invitation.ex
│   ├── project_crud.ex, memberships.ex, invitations.ex, slug_generator.ex
│
├── pages.ex                 # Main context (needs refactoring to facade pattern)
├── pages/
│   ├── page.ex              # Schema (tree hierarchy)
│   ├── block.ex             # Schema (dynamic content)
│   └── page_operations.ex   # Tree reordering
│
├── assets.ex                # Main context
├── assets/
│   ├── asset.ex             # Schema
│   ├── storage.ex           # Storage interface
│   ├── storage/local.ex     # Local filesystem
│   ├── storage/r2.ex        # Cloudflare R2
│   └── image_processor.ex   # libvips processing
│
├── flows.ex                 # Facade (NEW)
├── flows/
│   ├── flow.ex              # Schema
│   ├── flow_node.ex         # Schema (5 node types)
│   ├── flow_connection.ex   # Schema
│   ├── flow_crud.ex         # Flow CRUD operations
│   ├── node_crud.ex         # Node CRUD operations
│   └── connection_crud.ex   # Connection CRUD operations
│
└── authorization.ex         # Central authorization (role-based permissions)
```

---

## MVP Phases

### ✅ Phase 0: Base Infrastructure (Complete)

- [x] Phoenix project created
- [x] Docker compose (PostgreSQL + Redis + Mailpit)
- [x] Credo + Sobelow configured
- [x] TailwindCSS v4 with daisyUI v5
- [x] Biome for JS (lint + format)
- [x] Gettext locales (en, es)
- [x] GitHub Actions CI
- [x] Playwright E2E test structure

### ✅ Phase 1: Auth & Users (Complete)

- [x] User schema (email, hashed_password, display_name, avatar_url)
- [x] Registration/login with email + password
- [x] OAuth with GitHub, Google, Discord
- [x] Email verification via magic link
- [x] Password reset via magic link flow
- [x] Session management with token reissuing
- [x] Profile settings (display name, avatar)
- [x] Connected accounts management (link/unlink OAuth)
- [x] Sudo mode for sensitive operations
- [x] Rate limiting (ETS for dev, Redis for production)

> **Note on Password Reset:** Instead of a traditional "forgot password" flow, we use magic links.
> Users who forgot their password can request a magic link via the login page, which logs them in
> directly. Once logged in, they can set a new password in the settings page.

### ✅ Phase 2: Workspaces & Projects (Complete)

- [x] Workspace schema (name, slug, description)
- [x] Workspace memberships with 4 roles (owner, admin, member, viewer)
- [x] Workspace invitations via email with role selection
- [x] Workspace settings (general, members)
- [x] Default workspace created on user registration
- [x] Project schema (name, slug, description, workspace_id)
- [x] Project memberships with 3 roles (owner, editor, viewer)
- [x] Project invitations via email
- [x] Project settings
- [x] Workspace-centric navigation (sidebar with workspaces/projects)
- [x] Unified settings layout (account + workspace settings)
- [x] E2E tests for invitation flows

### ✅ Phase 3: Pages & Blocks System (Complete)

> **Architecture Change:** The original "Entities/Templates/Variables" system was redesigned and replaced with a simpler, more flexible "Pages & Blocks" architecture.

#### Phase 3.1: Pages System
- [x] Page schema with hierarchical tree (parent_id, position)
- [x] Page CRUD with cycle prevention validation
- [x] Breadcrumb navigation with ancestor chain
- [x] Page tree sidebar with expand/collapse
- [x] Drag & drop page reordering (SortableJS)
- [x] Drag & drop page moving between parents
- [x] Child page creation from tree
- [x] Page search in sidebar

#### Phase 3.2: Blocks System
- [x] Block schema (type, position, config, value)
- [x] 8 block types implemented:
  - `text` - Simple text input
  - `rich_text` - WYSIWYG editor (Tiptap)
  - `number` - Numeric input
  - `select` - Single select dropdown
  - `multi_select` - Multiple select with tags
  - `date` - Date picker
  - `divider` - Visual separator
  - *(expandable for future types)*
- [x] Block CRUD operations
- [x] Block configuration panel (right sidebar)
- [x] Per-block config (label, placeholder, options for selects)
- [x] Drag & drop block reordering
- [x] Save status indicator
- [x] Inline page name editing

#### Phase 3.3: Assets System
- [x] Cloudflare R2 integration (S3-compatible storage)
- [x] Asset schema (filename, size, content_type, key, project_id)
- [x] Storage abstraction (Local for dev, R2 for production)
- [x] Image processing with Image/libvips (thumbnails, resize)
- [x] Asset upload LiveComponent (drag-and-drop, progress, preview)
- [x] Unit tests

#### Phase 3.4: Code Quality Refactoring
- [x] Split Accounts context into submodules (facade pattern)
- [x] Split Workspaces context into submodules
- [x] Split Projects context into submodules
- [x] Fix Credo issues (with→case, nesting depth, @moduledoc)
- [x] Migrate from Heroicons to Lucide icons
- [x] Update to daisyUI v5 CSS variables

### ✅ Phase 4: Flow Editor - Core (Complete)

- [x] Flow schema and context (facade pattern with submodules)
- [x] Node schema (types: dialogue, hub, condition, instruction, jump)
- [x] Connection schema (source_node, target_node, pins, conditions)
- [x] Rete.js v2 with @retejs/lit-plugin for rendering
- [x] Rete.js integration with LiveView (FlowCanvas hook)
- [x] Custom Lit components (Shadow DOM + daisyUI CSS variables for theming)
  - StoryarnNode: colored headers, Lucide icons
  - StoryarnSocket: 10px subtle pins
  - StoryarnConnection: 2px smooth curves with label support
- [x] Node drag & drop on canvas
- [x] Node connections with visual lines
- [x] Node properties panel (sidebar)
- [x] Canvas zoom & pan
- [x] Server sync with duplicate event prevention
- [x] FlowLive.Index with LiveComponent form (stable modal pattern)
- [x] FlowLive.Show with full canvas editor
- [x] Mini-map navigation (rete-minimap-plugin)
- [x] Dot grid canvas background
- [x] Keyboard shortcuts (Delete, Ctrl+D duplicate, Escape deselect)
- [x] Connection labels and conditions UI (double-click to edit)

### ⏳ Phase 5: Flow Editor - Dialogue

- [ ] Dialogue node with speaker selector (from pages/entities)
- [ ] Rich text editor for dialogue content
- [ ] Branches/response options
- [ ] Conditions on branches (variable checks)
- [ ] Dialogue preview mode
- [ ] Variable interpolation in text (`{player_name}`)

### ⏳ Phase 6: Collaboration

- [ ] Phoenix Presence (who's online in project)
- [ ] Other users' cursor positions on canvas
- [ ] Node locking (prevent conflicts)
- [ ] Visual editing indicators (colored cursors)
- [ ] Change notifications (toast messages)

### ⏳ Phase 7: Export

- [ ] Export to JSON (custom Storyarn format)
- [ ] Export to JSON (articy-compatible format)
- [ ] Import from JSON
- [ ] Pre-export validation (broken connections, missing data)

### ⏳ Phase 8: Production Polish

- [ ] Performance profiling & optimization
- [ ] UX refinements based on testing
- [ ] Production deployment setup (fly.io or similar)
- [ ] Monitoring & logging (Sentry, AppSignal)

---

## JavaScript Dependencies

Current `assets/package.json`:

```json
{
  "@retejs/lit-plugin": "^2.0.x",
  "@tiptap/core": "^3.18.0",
  "@tiptap/pm": "^3.18.0",
  "@tiptap/starter-kit": "^3.18.0",
  "daisyui": "^5.5.14",
  "lit": "^3.x",
  "rete": "^2.0.3",
  "rete-area-plugin": "^2.0.3",
  "rete-connection-plugin": "^2.0.3",
  "rete-render-utils": "^2.0.2",
  "sortablejs": "^1.15.6",
  "topbar": "^3.0.0"
}
```

---

## JavaScript Hooks

Current hooks in `assets/js/hooks/`:

| Hook               | Purpose                                      |
|--------------------|----------------------------------------------|
| `flow_canvas.js`   | Rete.js flow editor canvas (NEW)             |
| `sortable_list.js` | Generic drag & drop for lists (blocks)       |
| `sortable_tree.js` | Tree structure drag & drop (pages)           |
| `tiptap_editor.js` | Rich text WYSIWYG editor                     |
| `tree.js`          | Tree UI interactions (expand/collapse)       |
| `tree_search.js`   | Search filtering in tree                     |
| `theme.js`         | Dark/light theme switching                   |

---

## 🌍 Internationalization (i18n)

> **Rule:** All user-facing text MUST be localized. No hardcoded strings.

### Supported Locales
- `en` - English (default)
- `es` - Spanish

### Usage

```elixir
# In templates
<h1>{gettext("Welcome")}</h1>
<p>{gettext("Hello, %{name}!", name: @user.name)}</p>

# In LiveView
put_flash(socket, :info, gettext("Project saved"))

# Pluralization
ngettext("1 page", "%{count} pages", @count)
```

### Commands

```bash
mix gettext.extract --merge    # Extract and merge strings
mix gettext.merge priv/gettext --locale fr  # Add new locale
```

---

## 🧪 Testing Strategy

### Test Files

```
test/
├── storyarn/
│   ├── accounts_test.exs
│   ├── workspaces_test.exs
│   ├── projects_test.exs
│   ├── pages_test.exs
│   ├── assets_test.exs
│   ├── flows_test.exs              # NEW
│   ├── authorization_test.exs
│   └── assets/image_processor_test.exs
├── storyarn_web/
│   ├── controllers/
│   ├── live/
│   │   ├── user_live/
│   │   ├── project_live/
│   │   ├── page_live/
│   │   ├── flow_live/              # NEW
│   │   └── settings_live/
│   └── user_auth_test.exs
└── e2e/
    └── projects_e2e_test.exs  # Playwright
```

### Commands

```bash
mix test                      # All unit + integration tests
mix test --cover              # With coverage
mix test.e2e                  # E2E tests (builds assets first)

# Run with visible browser
PLAYWRIGHT_HEADLESS=false mix test.e2e

# Before commit
mix precommit                 # compile + format + credo + test
```

---

## Database Schema

### Current Tables

```sql
-- Auth
users (id, email, hashed_password, display_name, avatar_url, confirmed_at, timestamps)
user_tokens (id, user_id, token, context, sent_to, timestamps)
user_identities (id, user_id, provider, provider_id, provider_email, provider_name, provider_avatar, provider_token, provider_refresh_token, timestamps)

-- Workspaces
workspaces (id, name, slug, description, timestamps)
workspace_memberships (id, workspace_id, user_id, role, timestamps)
workspace_invitations (id, workspace_id, email, role, token, invited_by_id, accepted_at, timestamps)

-- Projects
projects (id, workspace_id, name, slug, description, timestamps)
project_memberships (id, project_id, user_id, role, timestamps)
project_invitations (id, project_id, email, role, token, invited_by_id, accepted_at, timestamps)

-- Pages & Blocks
pages (id, project_id, name, icon, parent_id, position, timestamps)
blocks (id, page_id, type, position, config, value, timestamps)

-- Assets
assets (id, project_id, filename, size, content_type, key, timestamps)

-- Flows (NEW)
flows (id, project_id, name, description, is_main, settings, timestamps)
flow_nodes (id, flow_id, type, position_x, position_y, data, timestamps)
flow_connections (id, flow_id, source_node_id, source_pin, target_node_id, target_pin, label, condition, timestamps)
```

---

## Rete.js + LiveView Integration

### Architecture

1. **LiveView** handles:
   - Flow state (nodes, connections)
   - Persistence to database
   - Collaboration (change broadcasting via PubSub)
   - Properties panel

2. **Rete.js (JS Hook)** handles:
   - Canvas rendering (via @retejs/lit-plugin)
   - Drag & drop
   - Zoom/pan
   - Visual interactions

3. **Bidirectional communication:**
   ```
   LiveView State <---> JS Hook <---> Rete.js Canvas
                    pushEvent/handleEvent
   ```

### Hook Implementation

The FlowCanvas hook (`assets/js/hooks/flow_canvas.js`) implements:
- Rete.js v2 with Lit render plugin
- `isLoadingFromServer` flag to prevent duplicate events
- Event handlers for node/connection CRUD
- Debounced position updates

```javascript
// Key pattern: prevent duplicate events when syncing from server
this.isLoadingFromServer = true;
try {
  await this.addConnectionToEditor(data);
} finally {
  this.isLoadingFromServer = false;
}
```

---

## Node Types (articy-like)

### 1. Dialogue Node
```elixir
%{
  type: :dialogue,
  data: %{
    speaker: "",              # Speaker name or reference
    text: "Hello, traveler!"  # Dialogue text
  }
}
```

### 2. Hub Node
```elixir
%{
  type: :hub,
  data: %{
    label: "Quest Start"
    # Connection point with multiple outputs
  }
}
```

### 3. Condition Node
```elixir
%{
  type: :condition,
  data: %{
    expression: "player_gold >= 100"
    # Outputs: true, false
  }
}
```

### 4. Instruction Node
```elixir
%{
  type: :instruction,
  data: %{
    code: "set_variable('quest_started', true)"
  }
}
```

### 5. Jump Node
```elixir
%{
  type: :jump,
  data: %{
    target_flow_id: nil,    # Optional target flow
    target_node_id: nil     # Optional target node
  }
}
```

---

## Recent Commits History

| Commit  | Description                                                         |
|---------|---------------------------------------------------------------------|
| c748f36 | feat: Add Flow Editor with visual node-based editing                |
| 87ac8a3 | docs: Add rate limiting documentation to CLAUDE.md                  |
| 9820386 | feat: Add rate limiting and fix static analysis warnings            |
| 33ddac1 | docs: Add @spec type annotations to context modules                 |
| b3148f7 | docs: Update IMPLEMENTATION_PLAN.md with current status             |
| 458efe1 | chore: Remove obsolete planning documents                           |
| 6ac6912 | feat: Add Cloak encryption for OAuth tokens at rest                 |
| 17ddace | feat: Migrate from Heroicons to Lucide icons                        |

---

## Pending Refactoring Tasks

| Priority | Task                                | Status  |
|----------|-------------------------------------|---------|
| High     | Split `pages.ex` (facade pattern)   | ✅ Done  |
| High     | Encrypt OAuth tokens with Cloak     | ✅ Done  |
| Medium   | Split `block_components.ex`         | ✅ Done  |
| Medium   | Add `@spec` to contexts             | ✅ Done  |
| Medium   | Configure Redis for rate limiting   | ✅ Done  |
| Medium   | Validate inputs with Integer.parse  | ✅ Done  |

---

## Immediate Next Steps

1. **Phase 4: Flow Editor - Remaining Items**
   - Add mini-map navigation for large flows
   - Style nodes by type (colors, icons)
   - Connection labels and conditions UI
   - Keyboard shortcuts (delete, duplicate)

2. **Phase 5: Flow Editor - Dialogue**
   - Speaker selector linked to Pages
   - Rich text in dialogue nodes
   - Response branches UI

---

*Living document - update as the project progresses*
