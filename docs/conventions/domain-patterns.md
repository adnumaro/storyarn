# Domain Patterns & Conventions

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

### Contexts and their submodules

| Context       | Facade                   | Key Submodules                                                                                                                                                              |
|---------------|--------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Sheets        | `Storyarn.Sheets`        | `SheetCrud`, `SheetQueries`, `BlockCrud`, `TableCrud`, `PropertyInheritance`, `ReferenceTracker`, `Versioning`, `TreeOperations`                                            |
| Flows         | `Storyarn.Flows`         | `FlowCrud`, `NodeCrud` (→ `NodeCreate`, `NodeUpdate`, `NodeDelete`), `ConnectionCrud`, `TreeOperations`, `VariableReferenceTracker`, `HubColors`                            |
| Scenes        | `Storyarn.Scenes`        | `SceneCrud`, `LayerCrud`, `ZoneCrud`, `PinCrud`, `ConnectionCrud`, `AnnotationCrud`, `TreeOperations`                                                                       |
| Screenplays   | `Storyarn.Screenplays`   | `ScreenplayCrud`, `ElementCrud`, `ScreenplayQueries`, `TreeOperations`, `ElementGrouping`, `FlowSync`, `LinkedPageCrud`, `AutoDetect`, `Export.Fountain`, `Import.Fountain` |
| Localization  | `Storyarn.Localization`* | `LanguageCrud`, `TextCrud`, `TextExtractor`, `BatchTranslator`, `GlossaryCrud`, `Reports`, `ExportImport`                                                                   |
| Assets        | `Storyarn.Assets`        | `Asset` (schema), `Storage` (behaviour), `Storage.Local`, `Storage.R2`, `ImageProcessor`                                                                                    |
| Collaboration | `Storyarn.Collaboration` | `Colors`, `Presence`, `Locks`, `CursorTracker`                                                                                                                              |
| Projects      | `Storyarn.Projects`      | `ProjectCrud`, `Memberships`, `Invitations` (schemas: `ProjectMembership`, `ProjectInvitation`)                                                                             |
| Workspaces    | `Storyarn.Workspaces`    | `WorkspaceCrud`, `Memberships`, `Invitations` (schemas: `WorkspaceMembership`, `WorkspaceInvitation`)                                                                       |
| Accounts      | `Storyarn.Accounts`      | `Users`, `Registration`, `OAuth`, `Sessions`, `MagicLinks`, `Emails`, `Passwords`, `Profiles`                                                                               |

*Localization facade lives at `lib/storyarn/localization/localization.ex` (non-standard path).

---

## CRUD Module Pattern

All CRUD modules follow the same structure. When creating a new one, follow this template:

```elixir
defmodule Storyarn.{Context}.{Entity}Crud do
  import Ecto.Query
  alias Storyarn.Repo
  alias Storyarn.{Context}.{Entity}
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

---

## LiveView Organization

```
lib/storyarn_web/live/{domain}_live/
├── show.ex                    # Main LiveView (thin dispatcher)
├── index.ex                   # List view (if exists)
├── handlers/                  # Event handler modules
│   ├── {feature}_handlers.ex
│   └── ...
├── helpers/                   # Pure helper functions
│   ├── {feature}_helpers.ex
│   └── ...
└── components/                # LiveComponents specific to this domain
    ├── {feature}_section.ex
    └── ...
```

**Rules:**
- `show.ex` dispatches to handler modules — avoid growing past 300 lines
- Handler modules receive `(params, socket)` and return `{:noreply, socket}`
- Helpers are pure functions (no socket mutation)
- Components use LiveComponent pattern with `use StoryarnWeb, :live_component`

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

### Private helpers with auth (e.g., map_live/show.ex pattern):

```elixir
defp with_auth(socket, action, fun) do
  case authorize(socket, action) do
    :ok -> fun.()
    {:error, :unauthorized} -> {:noreply, unauthorized_flash(socket)}
  end
end
```

**Match the existing pattern in the file** — some files use `with_authorization`, others use a private `with_auth` wrapper.

---

## PubSub Pattern

All real-time features use `Phoenix.PubSub` through the `Collaboration` context:

```elixir
# Subscribe in mount
Collaboration.subscribe_presence(flow_id)
Collaboration.subscribe_changes(flow_id)
Collaboration.subscribe_locks(flow_id)
Collaboration.subscribe_cursors(flow_id)

# Broadcast changes
Collaboration.broadcast_change(flow_id, :node_updated, %{node_id: id})

# Handle in LiveView
def handle_info({:remote_change, action, payload}, socket), do: ...
def handle_info({:lock_change, action, payload}, socket), do: ...
def handle_info({:cursor_update, data}, socket), do: ...
def handle_info({:cursor_leave, user_id}, socket), do: ...
```

Topic format: `"flow:{flow_id}:{channel}"` where channel is `presence`, `changes`, `locks`, or `cursors`.

---

## Gettext Convention

All user-facing text uses domain-specific Gettext:

| Domain       | Function                                    | Example               |
|--------------|---------------------------------------------|-----------------------|
| Generic      | `gettext("Saved")`                          | Default domain        |
| Sheets       | `dgettext("sheets", "Untitled")`            | Sheet-specific        |
| Flows        | `dgettext("flows", "Add node")`             | Flow-specific         |
| Scenes       | `dgettext("scenes", "Default Layer")`       | Scene-specific        |
| Screenplays  | `dgettext("screenplays", "New Screenplay")` | Screenplay-specific   |
| Localization | `dgettext("localization", "Pending")`       | Localization-specific |
| Identity     | `dgettext("identity", "Sign in")`           | Auth/user-specific    |
| Settings     | `dgettext("settings", "General")`           | Settings-specific     |

**NEVER use hardcoded strings for user-facing text.**

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
```elixir
def list_tree(project_id) do
  entities = list_all(project_id)
  build_tree(entities, nil)  # nil = root level
end

defp build_tree(all, parent_id) do
  all
  |> Enum.filter(&(&1.parent_id == parent_id))
  |> Enum.map(fn entity ->
    %{entity | children: build_tree(all, entity.id)}
  end)
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
Storyarn.Assets.Storage.adapter().upload(key, data, content_type)
Storyarn.Assets.Storage.adapter().delete(key)
Storyarn.Assets.Storage.adapter().get_url(key)

# Key generation
key = Assets.generate_key(project, filename)
# => "projects/{project_id}/assets/{uuid}/{sanitized_filename}"
```

Adapters: `Storage.Local` (dev) and `Storage.R2` (prod, Cloudflare R2/S3-compatible).
