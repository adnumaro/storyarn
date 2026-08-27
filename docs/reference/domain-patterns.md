# Domain Patterns & Conventions

> Owner: Engineering
>
> Last reviewed: 2026-08-27
>
> Source of truth: `lib/storyarn/`, `lib/storyarn_web/`,
> `config/architecture_boundaries.exs`, and the Mix convention/architecture checks

## Architecture model

Storyarn is a modular monolith: one Phoenix application, one supervision tree,
one `Storyarn.Repo`, one PostgreSQL schema and nine bounded contexts. A bounded
context is defined by language, invariants and ownership, not by having a
directory or a Phoenix-style context module.

The current strategic relationships, ordinary writers and deliberate
exceptions are documented in the [bounded-context map](context-map.md).

### Bounded contexts

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
| Platform | `Storyarn.Platform` | Commercial policy, notifications, product reactions and genuinely platform-wide control-plane behavior |

Platform is an organizational control-plane boundary, not a claim that billing,
notifications and analytics share one aggregate or ubiquitous language.
Discovery, realtime collaboration and technical adapters may live physically
under `platform/` while being classified as application or infrastructure code.
That does not create another bounded context or make those modules generally
shareable.

### Public facade rule

Code outside a bounded context enters through its root facade:

```text
StoryarnWeb.FlowLive      -> Storyarn.Flows
Storyarn.Workers.Flows.*  -> Storyarn.Flows
Storyarn.Projects         -> Storyarn.Platform
Mix.Tasks.Storyarn.*      -> owning root facade
```

Within one bounded context, capabilities collaborate through their capability
facades. A capability must not import another capability's private
`commands/`, `queries/`, `entities/`, `rules/`, `execution/`, `adapters/` or
`projections/` modules merely because both live below the same context.

Root facades are stable integration surfaces, not files where business logic
belongs. Prefer a clear delegate or a small request/value contract. Do not add
generic repository behaviours, macros or facade generators just to reduce line
count.

### Capability-first, role-second organization

Contexts contain business capabilities first. Each capability uses only the
responsibility folders it needs:

```text
lib/storyarn/{context}.ex
lib/storyarn/{context}/README.md
lib/storyarn/{context}/{capability}/
├── {capability}.ex       # internal capability facade, when collaboration needs one
├── commands/             # state-changing use cases and transaction boundaries
├── queries/              # read-only persistence operations
├── entities/             # context-owned mutable state and changesets
├── rules/                # deterministic policy and validation
├── execution/            # indivisible multi-step workflows
├── contracts/            # stable values and behaviours crossing a real seam
├── events/               # facts owned by the producing capability
├── projections/          # passive consumer-owned read mappings
├── records/              # controlled writable mappings or exact reconstitution
├── reference_data/       # immutable shipped catalogs
└── adapters/             # provider, PostgreSQL, OTP, storage or delivery translation
```

This is a navigation and ownership convention, not mandatory hexagonal
layering. Empty folders are forbidden. A transaction, fencing protocol or lock
order stays together when splitting it would weaken correctness.

### Persistence shapes

- A `projection` is a consumer-owned, read-only Ecto mapping. It declares only
  fields, associations and types; it has no `Repo` calls or ordinary changesets.
- A `record` may participate in controlled writes such as exact import,
  reconstitution, trash or repair. The owning README must name that authority.
- `reference_data` has no database identity or external I/O.
- `Repo` is shared technical infrastructure, not a domain layer.
- Two contexts may deliberately duplicate a table mapping or business
  interpretation. Shared SQL does not imply shared Elixir schemas.

ENG-92 protects code ownership. It does not assign one writer per table. That
separate decision belongs to ENG-103.

### Internal capabilities are not bounded contexts

The following namespaces organize capabilities inside their owner. Their
existence does not create another domain boundary:

| Owner | Internal capability examples |
| --- | --- |
| Projects | `Assets`, `References`, `Versioning`, `Imports`, `Exports`, `ProjectTemplates` |
| Platform | `Commercial`, `Notifications`, `Reactions`, `Onboarding`, delivery policy |
| AI | `Operations`, `Execution`, `Allowance`, `IntegrationCrud`, provider clients and model catalog |

Workers, Repo, storage transports, mail delivery, PubSub, telemetry and release
wiring are adapters or application composition. They are not bounded contexts.
Background jobs are grouped physically under `lib/storyarn/workers/{owner}/`
and the ratchet assigns each slice to that bounded context. Their flat
`Storyarn.Workers.*` module names are a stable Oban persistence ABI, not a
shared domain layer. Workers orchestrate through the public facade of the
capability owner.

### Architecture ratchet

`mix architecture.check` classifies all backend, Web and operator Mix-task
paths declared in `config/architecture_boundaries.exs`. All nine bounded
contexts are sealed. Cross-boundary calls are denied unless they are exact,
reviewed root-facade or technical contracts.

Migration exceptions are debt, not infrastructure. The current storage calls
from tools, Web and the OTP root into Projects are registered individually and
must disappear through ENG-107. New consumers cannot copy that relationship.

The ratchet sees compile/runtime file edges. It cannot detect that two contexts
write the same table or that a new call was added between two files already
connected. Review and ENG-103's persistence-ownership policy remain necessary.

Mix tasks are operator adapters. Every task is classified explicitly and may
call root facades, `Repo` where its startup contract requires it, and technical
infrastructure. A new task remains unclassified until its ownership is reviewed.

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

All real-time features use `Phoenix.PubSub` through the technical
`Storyarn.Platform.Collaboration` facade.
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
`lib/storyarn/projects/versioning/execution/builders/sheet_builder.ex:1135`) and ship untranslated.
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

The current object-store implementation still mixes technical provider behavior
with Project-specific blob, snapshot, import and cleanup policy under
`Storyarn.Projects.Assets.Storage`. That is a tracked seam, not the target
architecture.

- Projects may use that policy boundary internally.
- Existing Flows, Sheets, Scenes, Web and OTP callers are registered as exact
  ENG-107 migration exceptions.
- New external callers are forbidden.
- Do not move the entire module to a shared namespace: recoverable-blob deletion,
  snapshot/import cleanup grammar and purge authority must remain with Projects.
- ENG-107 will extract only neutral provider operations, hashing and generic
  locking while preserving keys, provider configuration, lock identities,
  errors and external I/O ordering.

Direct provider deletion remains reserved for explicit tests that simulate
provider-side loss or clean up isolated fixtures.
