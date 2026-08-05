# Domain Patterns & Conventions

> Owner: Engineering
>
> Last reviewed: 2026-08-05
>
> Source of truth: `lib/storyarn/`, `lib/storyarn_web/`, and `lib/mix/tasks/convention_check.ex`

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
- Cross-context calls go through the facade: `Sheets.get_sheet/2`, not `Sheets.SheetCrud.get_sheet/2`

`mix convention.check` enforces this as the `facade_bypass` rule, but only for a
hardcoded submodule list (`@facade_submodules` in `lib/mix/tasks/convention_check.ex`)
and only under `lib/storyarn_web/`. The rule above is broader than the linter.

### Contexts and their submodules

| Context          | Facade                      | Key Submodules                                                                                                                                                                                                                                                                                                                                                       |
| ---------------- | --------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Accounts         | `Storyarn.Accounts`         | `Users`, `Registration`, `Sessions`, `Emails`, `Passwords`, `Profiles`, `Scope`, `UserNotifier`, `UserToken`                                                                                                                                                                                                                                                         |
| Workspaces       | `Storyarn.Workspaces`       | `WorkspaceCrud`, `Memberships`, `Invitations` (schemas: `WorkspaceMembership`, `WorkspaceInvitation`)                                                                                                                                                                                                                                                                |
| Projects         | `Storyarn.Projects`         | `ProjectCrud`, `Memberships`, `Invitations`, `Dashboard`, `ProjectTrash` (schemas: `ProjectMembership`, `ProjectInvitation`)                                                                                                                                                                                                                                         |
| Sheets           | `Storyarn.Sheets`           | `SheetCrud`, `SheetQueries`, `BlockCrud`, `TableCrud`, `GalleryCrud`, `AvatarCrud`, `PropertyInheritance`, `ReferenceTracker`, `TreeOperations`, `HealthChecker`, `FormulaResolver`                                                                                                                                                                                  |
| Flows            | `Storyarn.Flows`            | `FlowCrud`, `NodeCrud` (-> `NodeCreate`, `NodeUpdate`, `NodeDelete`), `ConnectionCrud`, `SequenceCrud`, `TreeOperations`, `VariableReferenceTracker`, `HubColors`, `HealthChecker`, `StructuralAnalysis`                                                                                                                                                             |
| Scenes           | `Storyarn.Scenes`           | `SceneCrud`, `LayerCrud`, `ZoneCrud`, `PinCrud`, `ConnectionCrud`, `AnnotationCrud`, `AmbientFlowCrud`, `ExplorationSessionCrud`, `TreeOperations`, `HealthChecker`, `ChangesetHelpers`                                                                                                                                                                              |
| Localization     | `Storyarn.Localization`     | `LanguageCrud`, `TextCrud`, `TextExtractor`, `BatchTranslator`, `GlossaryCrud`, `Reports`, `ExportImport`, `TranslationRunCrud`, `Providers.*`                                                                                                                                                                                                                       |
| Collaboration    | `Storyarn.Collaboration`    | `Colors`, `Presence`, `Locks`, `CursorTracker`                                                                                                                                                                                                                                                                                                                       |
| Assets           | `Storyarn.Assets`           | `Asset` (schema), `Storage` (behaviour), `Storage.Local`, `Storage.R2`, `ImageProcessor`, `BlobStore`, `StorageCompensation`, `StorageCleanupOwnershipReceipt`, `UploadPolicy`                                                                                                                                                                                       |
| AI               | `Storyarn.AI`               | `Operations`, `Execution`, `Executor`, `Allowance`, `Context`, `Audit`, `IntegrationCrud`, `InferenceProviders`, `ModelCatalog`, `CredentialResolver`                                                                                                                                                                                                                |
| References       | `Storyarn.References`       | `Backlinks`, `EntityTracker`, `VariableTracker`, `VariableUsage`, `ProjectReferenceIntegrity`, `AvatarIntegrity`                                                                                                                                                                                                                                                     |
| ProjectTemplates | `Storyarn.ProjectTemplates` | `Installation`, `PortableExport`, `PortableImport`, `PublicationRunner`, `TemplateQueries`, `Deletion`, `Authorization`, `Audit`                                                                                                                                                                                                                                     |
| Versioning       | `Storyarn.Versioning`       | `EntityVersion`, `VersionCrud`, `SnapshotBuilder`, `SnapshotStorage`, `SnapshotObjectFormat`, `SnapshotObjectStorage`, `SnapshotObjectPublicationClaim`, `ProjectSnapshotBuild`, `ProjectSnapshotCrud`, `ProjectSnapshotLifecycle`, `ProjectSnapshotPolicy`, `ProjectSnapshotReset`, `SnapshotCleanupIntent`, `ConflictDetector`, `RestorePolicy`, `ProjectRecovery` |
| Exports          | `Storyarn.Exports`          | `DataCollector`, `ExportOptions`, `Serializer`, `SerializerRegistry`, `Validator`, `ExpressionTranspiler`, `SizeGuard`, `LocalizationCatalog`                                                                                                                                                                                                                        |
| Imports          | `Storyarn.Imports`          | `Parser`, `ParserRegistry`, `Parsers.*`, `ImportPlan`, `PlanStorage`, `ErrorDeduplicator`                                                                                                                                                                                                                                                                            |
| Billing          | `Storyarn.Billing`          | `Plan`, `Subscription`, `SubscriptionCrud`, `Limits`, `StorageAccounting`, `StorageReservation`                                                                                                                                                                                                                                                                      |
| CommandPalette   | `Storyarn.CommandPalette`   | `Definition`, `Registry`, `Operation`                                                                                                                                                                                                                                                                                                                                |
| GlobalSearch     | `Storyarn.GlobalSearch`     | `Destinations`                                                                                                                                                                                                                                                                                                                                                       |
| Onboarding       | `Storyarn.Onboarding`       | `TutorialProgress`                                                                                                                                                                                                                                                                                                                                                   |
| Docs             | `Storyarn.Docs`             | `Guide`, `GuideBuilder`                                                                                                                                                                                                                                                                                                                                              |
| Blog             | `Storyarn.Blog`             | `Post`, `PostBuilder`                                                                                                                                                                                                                                                                                                                                                |
| Analytics        | `Storyarn.Analytics`        | `PostHogAdapter`, `NoopAdapter`                                                                                                                                                                                                                                                                                                                                      |
| RateLimiter      | `Storyarn.RateLimiter`      | `ETSBackend`, `RedisBackend`                                                                                                                                                                                                                                                                                                                                         |
| Shortcuts        | `Storyarn.Shortcuts`        | Centralized shortcut generation for all entity types (single module, no submodules)                                                                                                                                                                                                                                                                                  |

Facade-less directories — call the module directly, do not invent a facade:
`lib/storyarn/dashboards/` (`Cache`), `lib/storyarn/emails/` (`Layout`, `Templates`),
`lib/storyarn/product_metrics/` (`Taxonomy`), `lib/storyarn/publication/`,
`lib/storyarn/workers/` (Oban workers).

Single-module contexts with no directory: `Storyarn.FeatureFlags`, `Storyarn.Urls`,
`Storyarn.Vault`, `Storyarn.LiveVueEncoders`.

---

## CRUD Module Pattern

All CRUD modules follow the same structure. When creating a new one, follow this template:

```elixir
defmodule Storyarn.{Context}.{Entity}Crud do
  import Ecto.Query
  alias Storyarn.Repo
  alias Storyarn.{Context}.{Entity}
  # Each context has its OWN TreeOperations wrapper — alias the local one,
  # not Storyarn.Shared.TreeOperations:
  alias Storyarn.{Context}.TreeOperations
  # Import only what you need — not all CRUD modules use the same set:
  alias Storyarn.Shared.{MapUtils, ShortcutHelpers, SoftDelete}
  alias Storyarn.Shared.SearchHelpers  # only if search is needed
  alias Storyarn.Shortcuts              # centralized shortcut generators

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
    attrs = attrs
      |> MapUtils.stringify_keys()
      |> ShortcutHelpers.maybe_generate_shortcut(project.id, nil, &Shortcuts.generate_{entity}_shortcut/3)
      # position_fn is called as fn.(project_id, parent_id) — arity 2
      |> ShortcutHelpers.maybe_assign_position(project.id, parent_id, &TreeOperations.next_position/2)

    %Entity{project_id: project.id}
    |> Entity.create_changeset(attrs)
    |> Repo.insert()
  end

  # ========== Update ==========
  def update_{entity}(entity, attrs) do
    attrs = ShortcutHelpers.maybe_generate_shortcut_on_update(
      entity, attrs, &Shortcuts.generate_{entity}_shortcut/3,
      check_backlinks_fn: &has_backlinks?/1  # optional
    )

    entity
    |> Entity.update_changeset(attrs)
    |> Repo.update()
  end

  # ========== Delete (soft) ==========
  def delete_{entity}(entity) do
    SoftDelete.soft_delete_children(Entity, entity.project_id, entity.id,
      pre_delete: &clean_references/1  # optional cleanup callback
    )
  end
end
```

`Storyarn.Shared.TreeOperations.next_position/3` takes `(schema, project_id, parent_id)`.
Each context's local `TreeOperations` closes over the schema and exposes `next_position/2`.

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

**Validation:** Use `Storyarn.Shared.Validations.validate_shortcut/2` for shortcut fields.

**Do not re-implement the standard changesets** — `Storyarn.Shared.HierarchicalSchema`
already provides `delete_changeset/1`, `restore_changeset/1`, `move_changeset/2`,
`validate_core_fields/1`, `validate_description/1`, `deleted?/1`.

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

### In LiveComponents (check @can_edit assign):

```elixir
use StoryarnWeb.Helpers.Authorize

def handle_event("save", params, socket) do
  with_edit_authorization(socket, fn socket ->
    do_save(socket, params)
  end)
end
```

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
`lib/storyarn/versioning/builders/sheet_builder.ex:1273`) and ship untranslated.
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

Use `Storyarn.Shared.TreeOperations.build_tree_from_flat_list/1-2` — it groups once
instead of filtering the full list at every level:

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
Storyarn.Assets.Storage.upload(key, data, content_type)
Storyarn.Assets.Storage.delete(key)
Storyarn.Assets.Storage.get_url(key)

# Key generation
key = Assets.generate_key(project, filename)
# => "projects/{project_id}/assets/{id}/{sanitized_filename}"
```

Full behaviour: `upload/3`, `put_if_absent/3`, `delete/1`, `get_url/1`, `download/1`,
`stat/1`, `stream/4`, `presigned_upload_url/3`, `copy/2`, `copy_if_absent/2`,
`key_from_url/1`.

Adapters: `Storage.Local` (dev) and `Storage.R2` (prod, Cloudflare R2/S3-compatible).
Application code always goes through the `Storage` facade so deletion safety
checks cannot be bypassed. Direct adapter deletion is reserved for explicit
test-only helpers that simulate provider-side loss or clean up fixtures.
