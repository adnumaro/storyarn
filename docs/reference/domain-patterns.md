# Domain Patterns & Conventions

> Owner: Engineering
>
> Last reviewed: 2026-08-25
>
> Source of truth: `lib/storyarn/`, `lib/storyarn_web/`,
> `config/architecture_boundaries.exs`, and the Mix convention/architecture checks

## Context Facade Pattern

Every domain uses the same structure. NEVER bypass the facade.

```
lib/storyarn/{context}.ex          # Facade — ONLY entry point for external callers
lib/storyarn/{context}/
├── {entity}.ex                    # Ecto schema
├── {entity}_crud.ex               # CRUD operations
├── {entity}_queries.ex            # Read-only queries (optional)
└── {helper}.ex                    # Domain-specific helpers
```

**Rules:**

- Facade exposes public API via `defdelegate` to submodules
- LiveViews call `Context.function()`, NEVER `Context.SubModule.function()`
- Submodules can call each other within the same context
- Calls to an allowed supporting context go through its public facade, never one
  of its internals

`mix convention.check` enforces this as the `facade_bypass` rule, but only for a
hardcoded submodule list (`@facade_submodules` in `lib/mix/tasks/convention_check.ex`)
and only under `lib/storyarn_web/`. The rule above is broader than the linter.

### ENG-92 bounded-context ratchet

Storyarn currently recognizes nine bounded contexts: `Accounts`, `Workspaces`,
`Projects`, `Sheets`, `Flows`, `Scenes`, `Localization`, `AI`, and `Platform`.
Capabilities such as Assets, References, Versioning, Imports, Exports,
ProjectTemplates, Billing, Notifications, and Analytics belong to one of those
contexts; they are not bounded contexts merely because they have a namespace.

For the eight contexts sealed by ENG-92, new code dependencies between bounded
contexts are denied by default. A
durable cross-boundary contract must target a public context facade or an
explicitly classified technical contract. Temporary internal dependencies are
migration debt and must remain visible to the ratchet; they cannot be hidden as
permanent exceptions. Consumer-owned Ecto records may map the existing shared
tables, but must not associate to schemas owned by another boundary. ENG-92
keeps the shared Repo and SQL schema while decoupling code ownership.

`mix architecture.check` compares the JSON `mix xref` graph with that policy.
`Platform` is a supporting control-plane context, not a technical catch-all.
Infrastructure is classified separately and may contain only adapters and
application composition without business ownership. `AI` is accepted as its
own bounded context, but its existing dependency graph is intentionally not
sealed in this pass and remains transitionally classified by the ratchet. Its
eventual relationship with Projects remains a strategic decision, not an
excuse for other contexts to call its internals.

The ratchet operates at xref file-edge granularity. If a source file already has
a baselined edge to a target file, another call between that same pair is not
distinguishable in the JSON graph. Review must therefore still reject semantic
expansion inside a legacy edge; the automated gate prevents new file edges and
dependency-kind strengthening, not individual call sites.

### Bounded contexts and ownership

| Bounded context | Public facade | Owned business capabilities |
| --- | --- | --- |
| Accounts | `Storyarn.Accounts` | Users, authentication, profiles and account lifecycle |
| Workspaces | `Storyarn.Workspaces` | Workspaces, memberships, invitations and workspace policy |
| Projects | `Storyarn.Projects` | Project identity/lifecycle, dashboard, assets, templates, imports, exports, snapshots, reconstitution and project-wide integrity |
| Sheets | `Storyarn.Sheets` | Sheets, blocks, tables, galleries, formulas, variable definitions/usages and Sheet versioning |
| Flows | `Storyarn.Flows` | Flows, nodes, connections, sequences, evaluation, health and Flow versioning |
| Scenes | `Storyarn.Scenes` | Scenes, layers, zones, pins, connections, exploration, health and Scene versioning |
| Localization | `Storyarn.Localization` | Languages, localized text, glossary, extraction, translation runs, reports and localization transport |
| AI | `Storyarn.AI` | AI policies, integrations, model/provider selection, execution, audit and future AI product behavior |
| Platform | `Storyarn.Platform` | Billing/catalog/entitlements, notifications, product analytics and genuinely platform-wide control-plane policy |

### Internal capabilities are not bounded contexts

The following namespaces organize capabilities inside their owner. Their
existence does not create another domain boundary:

| Owner | Internal capability examples |
| --- | --- |
| Projects | `Assets`, `References`, `Versioning`, `Imports`, `Exports`, `ProjectTemplates` |
| Platform | `Billing`, `Notifications`, `Analytics`, `Collaboration`, `RateLimiter`, `GlobalSearch` |
| AI | `Operations`, `Execution`, `Allowance`, `IntegrationCrud`, provider clients and model catalog |

Workers, Repo, storage transports, mail delivery, PubSub, telemetry and release
wiring are adapters or application composition. They are not bounded contexts.
Background jobs are grouped physically under `lib/storyarn/workers/{owner}/`
and the ratchet assigns each slice to that bounded context. Their flat
`Storyarn.Workers.*` module names are a stable Oban persistence ABI, not a
shared domain layer. Workers orchestrate through the public facade of the
capability owner.

Snapshot lifecycle classes such as `ProjectSnapshotLifecycle`,
`ProjectSnapshotReconciliation`, `SnapshotArchiveStorage` and
`SnapshotCleanupIntent` are internal Projects capabilities.

---

## CRUD Module Pattern

All CRUD modules follow the same structure. When creating a new one, follow this template:

```elixir
defmodule Storyarn.{Context}.{Entity}Crud do
  import Ecto.Query
  alias Storyarn.Repo
  alias Storyarn.{Context}.{Entity}
  # Each context owns its TreeOperations semantics.
  alias Storyarn.{Context}.TreeOperations
  # Entity-specific shortcut policy is consumer-owned.
  alias Storyarn.{Context}.ShortcutGenerator
  # Import only what this context actually owns and uses.
  alias Storyarn.Platform.Shared.MapUtils
  alias Storyarn.Platform.Shared.SearchHelpers  # only if search is needed

  # ========== Queries ==========
  def list_{entities}(project_id) do
    from(e in Entity,
      where: e.project_id == ^project_id and is_nil(e.deleted_at),
      order_by: [asc: e.position, asc: e.name]
    )
    |> Repo.all()
  end

  def get_{entity}(project_id, id) do
    Repo.get_by(Entity, id: id, project_id: project_id)
  end

  def search_{entities}(project_id, query, opts \\ []) do
    sanitized = SearchHelpers.sanitize_like_query(query)
    # ... ILIKE search
  end

  # ========== Create ==========
  def create_{entity}(project, attrs) do
    attrs =
      attrs
      |> MapUtils.stringify_keys()
      |> ShortcutGenerator.prepare_create(project.id, nil)
      |> Map.put_new("position", TreeOperations.next_position(project.id, parent_id))

    %Entity{project_id: project.id}
    |> Entity.create_changeset(attrs)
    |> Repo.insert()
  end

  # ========== Update ==========
  def update_{entity}(entity, attrs) do
    attrs = MapUtils.stringify_keys(attrs)
    # Apply the owning context's shortcut/backlink policy here.

    entity
    |> Entity.update_changeset(attrs)
    |> Repo.update()
  end
end
```

The calls above are illustrative: use the owning context's actual local API.
Do not create a global tree, shortcut, or soft-delete helper to make the sample compile.
Deletion and restoration must remain explicit context operations because their
invariants differ between Sheets, Flows, Scenes, Projects and Workspaces.

---

## Schema Pattern

All hierarchical entities share these fields:

```elixir
schema "{entities}" do
  field :name, :string                    # Required, 1-200 chars
  field :shortcut, :string                # Unique per project
  field :description, :string             # Optional rich text
  field :position, :integer, default: 0   # Order among siblings
  field :deleted_at, :utc_datetime        # Soft delete

  belongs_to :project, Project
  belongs_to :parent, __MODULE__            # auto-generates parent_id field
  has_many :children, __MODULE__, foreign_key: :parent_id

  timestamps(type: :utc_datetime)
end
```

**Changesets:** Always separate by operation: `create_changeset/2`, `update_changeset/2`, `move_changeset/2`, `delete_changeset/1`, `restore_changeset/1`

**Validation:** Use the owning context's schema policy, such as
`Storyarn.Sheets.Schema` or `Storyarn.Scenes.Schema`. Do not import Project
validation rules into another bounded context.

Changesets and hierarchy invariants are consumer-owned. Duplication is
preferable to reintroducing a shared business superclass.

---

## LiveView Organization

```
lib/storyarn_web/live/{domain}_live/
├── show.ex                    # Main LiveView (thin dispatcher)
├── index.ex                   # List view (if exists)
├── handlers/                  # Event handler modules
│   ├── {feature}_handlers.ex
│   └── ...
└── helpers/                   # Pure helper functions
    ├── {feature}_helpers.ex
    └── ...
```

**Rules:**

- `show.ex` dispatches to handler modules — keep new code out of it
- Handler modules receive `(params, socket)` and return `{:noreply, socket}`
- Helpers are pure functions (no socket mutation)
- Rendering is Vue: `show.ex` serializes props and renders a single `<.vue>` boundary.
  There is no per-domain `components/` directory except `project_live/components/`
  (`settings_components.ex`); everything else lives in `assets/app/`.

The three canvas/editor dispatchers are far over any reasonable size budget
(`sheet_live/show.ex` 1108 lines, `flow_live/show.ex` 1699, `scene_live/show.ex` 2139).
Extract into `handlers/` or `helpers/` rather than adding to them.

---

## Authorization in LiveViews

**Every mutating `handle_event` MUST be authorized.** UI-only hiding is NOT sufficient.

### In LiveViews (check membership role):

```elixir
use StoryarnWeb.Helpers.Authorize

def handle_event("delete", params, socket) do
  with_authorization(socket, :edit_content, fn socket ->
    do_delete(socket, params)
  end)
end
```

### Compatibility helper for project editing

```elixir
use StoryarnWeb.Helpers.Authorize

def handle_event("save", params, socket) do
  with_edit_authorization(socket, fn socket ->
    do_save(socket, params)
  end)
end
```

`with_edit_authorization/2` is only a compatibility spelling for
`with_authorization(socket, :edit_content, ...)`. It reauthorizes through
`Projects` and never trusts the cached `@can_edit` assign.

### Private helpers with auth (e.g., scene_live/show.ex pattern):

```elixir
defp with_auth(socket, action, fun) do
  case authorize(socket, action) do
    :ok -> fun.()
    {:error, :unauthorized} -> {:noreply, unauthorized_flash(socket)}
  end
end
```

**Match the existing pattern in the file** — some files use `with_authorization`, others use a private `with_auth` wrapper.

Actions: `:edit_content`, `:use_ai`, `:manage_project`, `:manage_members`,
`:manage_workspace`, `:manage_workspace_members`.

Roles: project = `owner | editor | viewer`; workspace = `owner | admin | member | viewer`.

---

## PubSub Pattern

All real-time features use `Phoenix.PubSub` through the `Collaboration` context.
Every editor function takes a **scope tuple** `{type, id}` where type is an atom —
`{:flow, flow.id}`, `{:sheet, sheet.id}`, `{:scene, scene.id}`, `{:project, project.id}`
— not a bare id.

```elixir
# Subscribe in mount
Collaboration.subscribe_presence(scope)
Collaboration.subscribe_changes(scope)
Collaboration.subscribe_locks(scope)
Collaboration.subscribe_cursors(scope)

# Broadcast changes — prefer the _from variants in handle_event to avoid echo
Collaboration.broadcast_change_from(self(), scope, :node_updated, %{node_id: id})

# Handle in LiveView
def handle_info({:remote_change, action, payload}, socket), do: ...
def handle_info({:lock_change, action, payload}, socket), do: ...
def handle_info({:cursor_update, data}, socket), do: ...
def handle_info({:cursor_leave, user_id}, socket), do: ...
```

Topic format: `"{type}:{id}:{channel}"` where channel is `presence`, `changes`,
`locks`, or `cursors`.

Project-wide channels take a bare `project_id`, not a scope tuple:

| Channel    | Subscribe                | Topic                     |
| ---------- | ------------------------ | ------------------------- |
| Flow graph | `subscribe_flow_graph/1` | `project:{id}:flow_graph` |
| Dashboard  | `subscribe_dashboard/1`  | `project:{id}:dashboard`  |

---

## Gettext Convention

All user-facing text uses domain-specific Gettext. One domain per `.pot` file in
`priv/gettext/`:

| Domain       | Function                               | Example               |
| ------------ | -------------------------------------- | --------------------- |
| Generic      | `gettext("Saved")`                     | `default` domain      |
| Sheets       | `dgettext("sheets", "Untitled")`       | Sheet-specific        |
| Flows        | `dgettext("flows", "Add node")`        | Flow-specific         |
| Scenes       | `dgettext("scenes", "Default Layer")`  | Scene-specific        |
| Localization | `dgettext("localization", "Pending")`  | Localization-specific |
| Identity     | `dgettext("identity", "Sign in")`      | Auth/user-specific    |
| Settings     | `dgettext("settings", "General")`      | Settings-specific     |
| Projects     | `dgettext("projects", "New Project")`  | Project-specific      |
| Workspaces   | `dgettext("workspaces", "Members")`    | Workspace-specific    |
| Assets       | `dgettext("assets", "Upload")`         | Asset library         |
| Versioning   | `dgettext("versioning", "Restore")`    | Versions & snapshots  |
| Integrations | `dgettext("integrations", "Provider")` | AI integrations       |
| Drafts       | `dgettext("drafts", "Draft")`          | Draft surfaces        |
| Public       | `dgettext("public", "Pricing")`        | Marketing pages       |
| Docs         | `dgettext("docs", "Guides")`           | Documentation         |
| Blog         | `dgettext("blog", "Read more")`        | Blog                  |
| Emails       | `dgettext("emails", "Welcome")`        | Transactional email   |
| Errors       | — **dormant**                          | See note below        |

**NEVER use hardcoded strings for user-facing text.** `mix convention.check` catches
only the `put_flash` case (`put_flash_without_gettext`, web files only).

`priv/gettext/errors.pot` still exists but **nothing calls `dgettext("errors", …)`**.
`translate_error/1` was deleted from `core_components.ex`; changeset errors are now
interpolated raw (`String.replace` over `%{key}` — see `format_changeset_error/1` in
`lib/storyarn/projects/versioning/builders/sheet_builder.ex:1273`) and ship untranslated.
Do not route new error text through that domain expecting translation.

### After adding, moving or deleting a `dgettext` call

**Run `mix gettext.extract --merge` and commit the result.** `mix precommit` and
`just quality-lint` fail otherwise (`mix gettext.extract --check-up-to-date`),
including when the call only changed line number — the task compares `#:`
reference lines too. Extraction is all-or-nothing: there is no per-domain flag, so
to keep a feature PR reviewable, extract everything and revert every domain but
yours.

The merge then leaves work in `priv/gettext/es/LC_MESSAGES/`, and
`test/storyarn/publication/locales_test.exs` blocks on all of it — across all 19
domains, not just the public ones:

- **Fill every empty `msgstr`.** Informal second person ("Selecciona…", "No tienes
  permiso…"). Keep `hub`, `jump`, `subflow`, `entry`, `exit`, `sequence`,
  `waypoint`, `fog`, `API key` in English — but the catalog outranks that list:
  `flow`, `sheet` and `zone` are already _flujo_, _ficha_ and _zona_.
- **Review every `#, fuzzy` entry and drop the flag.** `Gettext.Compiler` filters
  on `obsolete` alone (`deps/gettext/lib/gettext/compiler.ex:514`) — it has no
  notion of `fuzzy` at runtime, so the merge's nearest-neighbour guess ships
  verbatim. `scenes.po` answered `Asset not found.` with _"Ficha no encontrada."_
  ("Sheet not found") that way.
- **Leave `en` msgstrs empty.** Gettext falls back to the msgid, already English,
  so a filled `en` msgstr is an _override_ of the source string — and the merge
  writes those on its own. It fuzzy-matched three new `projects` msgids onto
  neighbours, one of them answering `Project name` with _"Project Trash"_; clear
  the flags without reading them and the override is what ships. One had been
  sitting in `en/flows.po` since an earlier merge, telling English users _"Could
  not update node positions."_ when they failed to update the scene map.
- **Keep interpolations identical** between msgid and msgstr — same names, same
  `%{...}` form. A placeholder the message never binds prints literally on screen.

Worth two minutes after a large merge, though no test does it: group a catalog by
`msgstr` and inspect every value claimed by more than one `msgid`. That is the
fingerprint of the merge copying, and it is how eight distinct `scenes` errors
were found all reading "No se pudo actualizar el contenido.".

---

## Ecto Query Patterns

### Soft-delete filtering (ALWAYS add):

```elixir
from(e in Entity, where: is_nil(e.deleted_at))
```

### Search with LIKE (ALWAYS sanitize):

```elixir
sanitized = SearchHelpers.sanitize_like_query(query)
from(e in Entity, where: ilike(e.name, ^"%#{sanitized}%"))
```

### Tree building (in-memory from flat list):

Use the owning context's `TreeOperations.build_tree_from_flat_list` implementation.
It should group once instead of filtering the full list at every level:

```elixir
def list_tree(project_id) do
  project_id
  |> list_all()
  |> TreeOperations.build_tree_from_flat_list()  # nil root by default
end
```

### Preload strategy:

- **List operations:** Minimal preloads (just what's needed for display)
- **Get/show operations:** Full preloads for the detail view
- **Canvas operations:** Aggressive preloads in single query to avoid N+1

---

## Storage Pattern (Assets)

```elixir
# Behaviour + Adapter pattern
Storyarn.Projects.Assets.Storage.upload(key, data, content_type)
Storyarn.Projects.Assets.Storage.delete(key)
Storyarn.Projects.Assets.Storage.get_url(key)

# Key generation
key = Assets.generate_key(project, filename)
# => "projects/{project_id}/assets/{id}/{sanitized_filename}"
```

Full behaviour: `upload/3`, `put_if_absent/3`, `delete/1`, `get_url/1`, `download/1`,
`stat/1`, `stream/4`, `presigned_upload_url/3`, `presigned_download_url/3`,
`copy/2`, `copy_if_absent/2`, `key_from_url/1`.

Adapters: `Storage.Local` (dev) and the legacy-named `Storage.R2` adapter
(S3-compatible storage; Fly Tigris in production).
Application code always goes through the `Storage` facade so deletion safety
checks cannot be bypassed. Direct adapter deletion is reserved for explicit
test-only helpers that simulate provider-side loss or clean up fixtures.
