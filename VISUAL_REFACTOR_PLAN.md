# Storyarn - Visual Refactoring Plan

> **Objetivo:** Transformar la UI actual (centrada, simple) a un diseño con sidebar de workspaces y layout profesional según el mockup de referencia.

## Referencia Visual

El mockup muestra:
- **Sidebar izquierda:** Logo + lista de workspaces + botón "New workspace" + avatar de usuario
- **Área principal:** Header con banner personalizable (imagen + título + descripción) + grid de proyectos
- **Tema oscuro** como base

---

## Fase 0: Modelo de Datos - Workspaces

### 0.1 Crear migración para Workspaces

```elixir
# priv/repo/migrations/xxx_create_workspaces.exs
create table(:workspaces, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :name, :string, null: false
  add :description, :text
  add :slug, :string, null: false  # URL-friendly identifier
  add :banner_url, :string         # Header image
  add :color, :string              # Accent color (optional)
  add :owner_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

  timestamps(type: :utc_datetime)
end

create unique_index(:workspaces, [:slug])
create index(:workspaces, [:owner_id])
```

### 0.2 Crear migración para Workspace Memberships

```elixir
# priv/repo/migrations/xxx_create_workspace_memberships.exs
create table(:workspace_memberships, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :delete_all), null: false
  add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
  add :role, :string, null: false, default: "member"  # owner, admin, member, viewer

  timestamps(type: :utc_datetime)
end

create unique_index(:workspace_memberships, [:workspace_id, :user_id])
create index(:workspace_memberships, [:user_id])
```

### 0.3 Modificar Projects para pertenecer a Workspace

```elixir
# priv/repo/migrations/xxx_add_workspace_to_projects.exs
alter table(:projects) do
  add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :delete_all)
end

create index(:projects, [:workspace_id])
```

### 0.4 Crear schemas y contexto

- `lib/storyarn/workspaces/workspace.ex`
- `lib/storyarn/workspaces/workspace_membership.ex`
- `lib/storyarn/workspaces.ex` (contexto)

### 0.5 Lógica de permisos en cascada

```elixir
# lib/storyarn/authorization.ex
defmodule Storyarn.Authorization do
  @moduledoc """
  Permission resolution with workspace-level inheritance and project-level override.

  Priority: Project membership > Workspace membership > No access
  """

  alias Storyarn.{Projects, Workspaces}

  @roles_hierarchy %{
    "owner" => 4,
    "admin" => 3,
    "member" => 2,
    "viewer" => 1
  }

  @doc """
  Get the effective role for a user on a specific project.
  Project-level membership overrides workspace-level membership.
  """
  def get_effective_role(user, project) do
    case Projects.get_membership(project, user) do
      %{role: role} ->
        {:ok, role, :project}
      nil ->
        case Workspaces.get_membership(project.workspace, user) do
          %{role: role} -> {:ok, role, :workspace}
          nil -> {:error, :no_access}
        end
    end
  end

  def can?(user, action, resource) do
    # Implementation based on role and action
  end
end
```

---

## Fase 0.5: Onboarding - Workspace por defecto

### Flujo de registro actualizado

Cuando un usuario se registra, automáticamente se crea:
1. Un **Workspace** por defecto con el usuario como **owner**
2. El usuario es redirigido a este workspace tras el login

### Nombre del workspace por defecto (i18n)

```elixir
# priv/gettext/en/LC_MESSAGES/default.po
msgid "%{name}'s workspace"
msgstr "%{name}'s workspace"

# priv/gettext/es/LC_MESSAGES/default.po
msgid "%{name}'s workspace"
msgstr "Workspace de %{name}"
```

### Implementación en el contexto Accounts

```elixir
# lib/storyarn/accounts.ex
def register_user(attrs) do
  Ecto.Multi.new()
  |> Ecto.Multi.insert(:user, User.registration_changeset(%User{}, attrs))
  |> Ecto.Multi.run(:workspace, fn repo, %{user: user} ->
    workspace_name = default_workspace_name(user)

    %Workspace{}
    |> Workspace.changeset(%{
      name: workspace_name,
      slug: generate_slug(workspace_name, user.id),
      owner_id: user.id
    })
    |> repo.insert()
  end)
  |> Ecto.Multi.run(:membership, fn repo, %{user: user, workspace: workspace} ->
    %WorkspaceMembership{}
    |> WorkspaceMembership.changeset(%{
      workspace_id: workspace.id,
      user_id: user.id,
      role: "owner"
    })
    |> repo.insert()
  end)
  |> Repo.transaction()
  |> case do
    {:ok, %{user: user}} -> {:ok, user}
    {:error, :user, changeset, _} -> {:error, changeset}
    {:error, _, _, _} -> {:error, :workspace_creation_failed}
  end
end

defp default_workspace_name(user) do
  name = user.display_name || String.split(user.email, "@") |> List.first()
  Gettext.gettext(StoryarnWeb.Gettext, "%{name}'s workspace", name: name)
end

defp generate_slug(name, user_id) do
  base_slug = Slug.slugify(name)
  # Añadir sufijo único para evitar colisiones
  "#{base_slug}-#{String.slice(user_id, 0, 8)}"
end
```

### Redirect después del login

```elixir
# lib/storyarn_web/controllers/user_session_controller.ex
def create(conn, %{"user" => user_params}) do
  # ... autenticación ...

  # Redirect al workspace por defecto del usuario
  default_workspace = Workspaces.get_default_workspace(user)
  redirect_path = if default_workspace do
    ~p"/workspaces/#{default_workspace.slug}"
  else
    ~p"/workspaces/new"  # Fallback si no tiene workspace
  end

  conn
  |> put_flash(:info, gettext("Welcome back!"))
  |> redirect(to: redirect_path)
end
```

### Obtener workspace por defecto

```elixir
# lib/storyarn/workspaces.ex
@doc """
Returns the user's default workspace.
Priority: First owned workspace, then first workspace with membership.
"""
def get_default_workspace(user) do
  # Primero buscar workspace donde es owner
  Repo.one(
    from w in Workspace,
    join: m in WorkspaceMembership, on: m.workspace_id == w.id,
    where: m.user_id == ^user.id,
    order_by: [
      desc: fragment("CASE WHEN ? = 'owner' THEN 1 ELSE 0 END", m.role),
      asc: w.inserted_at
    ],
    limit: 1
  )
end
```

### Cambios en la página inicial

| Antes | Después |
|-------|---------|
| `/` → Landing page (Phoenix welcome) | `/` → Redirect a `/workspaces/:slug` si autenticado |
| `/projects` → Dashboard de proyectos | `/workspaces/:slug` → Dashboard del workspace |
| Login redirect → `/projects` | Login redirect → `/workspaces/:default-slug` |

### Router actualizado

```elixir
# lib/storyarn_web/router.ex

# Página raíz
scope "/", StoryarnWeb do
  pipe_through :browser

  # Si está autenticado, redirect al workspace default
  # Si no, mostrar landing page
  get "/", PageController, :home
end

# En PageController
def home(conn, _params) do
  if conn.assigns[:current_user] do
    workspace = Workspaces.get_default_workspace(conn.assigns.current_user)
    redirect(conn, to: ~p"/workspaces/#{workspace.slug}")
  else
    render(conn, :home)  # Landing page para visitantes
  end
end
```

---

## Fase 1: Layout Principal

### 1.1 Crear nuevo layout con sidebar

Reemplazar el layout actual centrado por un layout de dos columnas:

```
┌─────────────────────────────────────────────────────────┐
│ [Logo]              (opcional: breadcrumb/search)       │  <- Top bar (opcional)
├──────────┬──────────────────────────────────────────────┤
│          │                                              │
│ Sidebar  │              Main Content                    │
│          │                                              │
│ - WS 1   │  ┌─────────────────────────────────────┐    │
│ - WS 2   │  │  Banner + Title + Description       │    │
│ - WS 3   │  └─────────────────────────────────────┘    │
│          │                                              │
│ + New    │  ┌───┐ ┌───┐ ┌───┐                         │
│          │  │ P │ │ P │ │ P │  <- Project cards        │
│          │  └───┘ └───┘ └───┘                         │
│          │                                              │
├──────────┴──────────────────────────────────────────────┤
│ [Avatar] Benjamin                                       │  <- User footer (sidebar)
└─────────────────────────────────────────────────────────┘
```

### 1.2 Archivos a crear/modificar

```
lib/storyarn_web/components/
├── layouts/
│   ├── root.html.heex          # Modificar: quitar nav superior
│   ├── app.html.heex           # Nuevo: layout con sidebar
│   └── auth.html.heex          # Nuevo: layout sin sidebar (login/register)
├── layouts.ex                   # Modificar: nuevos componentes
├── sidebar.ex                   # Nuevo: componente sidebar
└── core_components.ex           # Modificar: nuevos componentes base
```

### 1.3 Componente Sidebar

```elixir
# lib/storyarn_web/components/sidebar.ex
defmodule StoryarnWeb.Components.Sidebar do
  use Phoenix.Component
  import StoryarnWeb.CoreComponents

  attr :current_user, :map, required: true
  attr :workspaces, :list, required: true
  attr :current_workspace, :map, default: nil

  def sidebar(assigns) do
    ~H"""
    <aside class="w-64 h-screen bg-base-200 flex flex-col">
      <!-- Logo -->
      <div class="p-4 border-b border-base-300">
        <.link navigate={~p"/"} class="text-xl font-bold">
          Storyarn
        </.link>
      </div>

      <!-- Workspaces list -->
      <nav class="flex-1 overflow-y-auto p-2">
        <div class="text-xs uppercase text-base-content/50 px-2 py-1">
          Workspaces
        </div>
        <ul class="menu menu-sm">
          <li :for={workspace <- @workspaces}>
            <.link
              navigate={~p"/workspaces/#{workspace.slug}"}
              class={[@current_workspace && @current_workspace.id == workspace.id && "active"]}
            >
              <span class="w-2 h-2 rounded-full" style={"background: #{workspace.color || '#6366f1'}"}></span>
              <%= workspace.name %>
            </.link>
          </li>
        </ul>
      </nav>

      <!-- New workspace button -->
      <div class="p-2 border-t border-base-300">
        <.link navigate={~p"/workspaces/new"} class="btn btn-ghost btn-sm w-full justify-start">
          <.icon name="hero-plus" class="size-4" />
          New workspace
        </.link>
      </div>

      <!-- User footer with dropdown -->
      <div class="p-2 border-t border-base-300">
        <div class="dropdown dropdown-top w-full">
          <div tabindex="0" role="button" class="flex items-center gap-2 p-2 rounded hover:bg-base-300 w-full">
            <div class="avatar placeholder">
              <div class="bg-neutral text-neutral-content rounded-full w-8">
                <span class="text-xs"><%= String.first(@current_user.display_name || @current_user.email) %></span>
              </div>
            </div>
            <span class="text-sm truncate flex-1"><%= @current_user.display_name || @current_user.email %></span>
            <.icon name="hero-ellipsis-vertical" class="size-4 opacity-50" />
          </div>
          <ul tabindex="0" class="dropdown-content menu bg-base-100 rounded-box w-56 shadow-lg border border-base-300 mb-2">
            <li>
              <.link navigate={~p"/settings/profile"}>
                <.icon name="hero-user" class="size-4" />
                Profile
              </.link>
            </li>
            <li>
              <.link navigate={~p"/settings/preferences"}>
                <.icon name="hero-cog-6-tooth" class="size-4" />
                Preferences
                <kbd class="kbd kbd-xs ml-auto">E</kbd>
              </.link>
            </li>
            <li>
              <button phx-click="toggle-theme" class="flex items-center gap-2">
                <.icon name="hero-moon" class="size-4 dark:hidden" />
                <.icon name="hero-sun" class="size-4 hidden dark:block" />
                Dark mode
                <kbd class="kbd kbd-xs ml-auto">D</kbd>
              </button>
            </li>
            <div class="divider my-1"></div>
            <li>
              <.link href={~p"/users/log-out"} method="delete">
                <.icon name="hero-arrow-right-on-rectangle" class="size-4" />
                Log out
              </.link>
            </li>
          </ul>
        </div>
      </div>
    </aside>
    """
  end
end
```

### 1.4 Layout principal con sidebar

```elixir
# lib/storyarn_web/components/layouts.ex (modificar)

def app(assigns) do
  ~H"""
  <div class="flex h-screen bg-base-100">
    <.sidebar
      current_user={@current_user}
      workspaces={@workspaces}
      current_workspace={assigns[:current_workspace]}
    />
    <main class="flex-1 overflow-y-auto">
      <.flash_group flash={@flash} />
      <%= @inner_content %>
    </main>
  </div>
  """
end
```

---

## Fase 2: Workspace Dashboard

### 2.1 Workspace Header Component

```elixir
# lib/storyarn_web/components/workspace_header.ex
defmodule StoryarnWeb.Components.WorkspaceHeader do
  use Phoenix.Component

  attr :workspace, :map, required: true
  attr :can_edit, :boolean, default: false

  def workspace_header(assigns) do
    ~H"""
    <header class="relative">
      <!-- Banner image -->
      <div class="h-48 bg-gradient-to-r from-base-300 to-base-200 overflow-hidden">
        <img
          :if={@workspace.banner_url}
          src={@workspace.banner_url}
          alt=""
          class="w-full h-full object-cover"
        />
      </div>

      <!-- Content overlay -->
      <div class="absolute bottom-0 left-0 right-0 p-6 bg-gradient-to-t from-base-100/90 to-transparent">
        <div class="flex items-end justify-between">
          <div>
            <h1 class="text-3xl font-bold"><%= @workspace.name %></h1>
            <p :if={@workspace.description} class="text-base-content/70 mt-1 max-w-2xl">
              <%= @workspace.description %>
            </p>
          </div>
          <.link :if={@can_edit} navigate={~p"/workspaces/#{@workspace.slug}/settings"} class="btn btn-ghost btn-sm">
            <.icon name="hero-cog-6-tooth" class="size-4" />
          </.link>
        </div>
      </div>
    </header>
    """
  end
end
```

### 2.2 Project Card Component

```elixir
# lib/storyarn_web/components/project_card.ex
defmodule StoryarnWeb.Components.ProjectCard do
  use Phoenix.Component

  attr :project, :map, required: true
  attr :class, :string, default: nil

  def project_card(assigns) do
    ~H"""
    <.link
      navigate={~p"/projects/#{@project.id}"}
      class={[
        "card bg-base-200 hover:bg-base-300 transition-colors cursor-pointer",
        @class
      ]}
    >
      <!-- Thumbnail/preview -->
      <figure class="h-32 bg-base-300">
        <img
          :if={@project.thumbnail_url}
          src={@project.thumbnail_url}
          alt=""
          class="w-full h-full object-cover"
        />
        <div :if={!@project.thumbnail_url} class="flex items-center justify-center h-full">
          <.icon name="hero-document-text" class="size-12 text-base-content/20" />
        </div>
      </figure>

      <div class="card-body p-4">
        <!-- Date badge -->
        <div class="text-xs text-base-content/50">
          <%= Calendar.strftime(@project.inserted_at, "%b %d, %Y") %>
        </div>

        <!-- Title -->
        <h3 class="card-title text-base"><%= @project.name %></h3>

        <!-- Description -->
        <p :if={@project.description} class="text-sm text-base-content/70 line-clamp-2">
          <%= @project.description %>
        </p>

        <!-- Footer: collaborators + timestamp -->
        <div class="flex items-center justify-between mt-2">
          <div class="avatar-group -space-x-2">
            <!-- TODO: Show project members avatars -->
          </div>
          <span class="text-xs text-base-content/50">
            <%= time_ago(@project.updated_at) %>
          </span>
        </div>
      </div>
    </.link>
    """
  end

  defp time_ago(datetime) do
    # Simple relative time formatting
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)
    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)} min ago"
      diff < 86400 -> "#{div(diff, 3600)} hours ago"
      true -> "#{div(diff, 86400)} days ago"
    end
  end
end
```

### 2.3 Workspace Dashboard LiveView

```elixir
# lib/storyarn_web/live/workspace_live/show.ex
defmodule StoryarnWeb.WorkspaceLive.Show do
  use StoryarnWeb, :live_view

  alias Storyarn.{Workspaces, Projects}

  def mount(%{"slug" => slug}, _session, socket) do
    workspace = Workspaces.get_workspace_by_slug!(slug)
    projects = Projects.list_projects_for_workspace(workspace)

    {:ok,
     socket
     |> assign(:workspace, workspace)
     |> assign(:current_workspace, workspace)
     |> assign(:projects, projects)
     |> assign(:page_title, workspace.name)}
  end

  def render(assigns) do
    ~H"""
    <div>
      <.workspace_header workspace={@workspace} can_edit={true} />

      <!-- Toolbar -->
      <div class="p-4 flex items-center justify-between border-b border-base-300">
        <div class="flex items-center gap-2">
          <!-- Search -->
          <div class="form-control">
            <input
              type="text"
              placeholder="Search projects..."
              class="input input-sm input-bordered w-64"
              phx-change="search"
              phx-debounce="300"
            />
          </div>
          <!-- Filters (placeholder for future) -->
        </div>

        <.link navigate={~p"/workspaces/#{@workspace.slug}/projects/new"} class="btn btn-primary btn-sm">
          <.icon name="hero-plus" class="size-4" />
          New Project
        </.link>
      </div>

      <!-- Projects grid -->
      <div class="p-4">
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
          <.project_card :for={project <- @projects} project={project} />
        </div>

        <div :if={@projects == []} class="text-center py-12 text-base-content/50">
          <.icon name="hero-folder-open" class="size-12 mx-auto mb-4" />
          <p>No projects yet</p>
          <p class="text-sm">Create your first project to get started</p>
        </div>
      </div>
    </div>
    """
  end
end
```

---

## Fase 2.5: Settings Page (Estilo Linear)

### Estructura de navegación

El settings tendrá su propio layout con sidebar de navegación categorizada.
Acceso vía Profile dropdown o `/settings`.

```
┌─────────────────────────────────────────────────────────┐
│ < Back to app                                           │
├──────────────────┬──────────────────────────────────────┤
│                  │                                      │
│  Settings Nav    │         Settings Content             │
│                  │                                      │
│  Account         │  ┌────────────────────────────────┐  │
│  - Profile       │  │                                │  │
│  - Preferences   │  │   Current settings panel       │  │
│  - Notifications │  │                                │  │
│  - Security      │  │                                │  │
│  - Connected     │  └────────────────────────────────┘  │
│                  │                                      │
│  Workspace       │                                      │
│  - General       │                                      │
│  - Members       │                                      │
│  - Billing       │                                      │
│                  │                                      │
└──────────────────┴──────────────────────────────────────┘
```

### Secciones del Settings (adaptadas a Storyarn)

```elixir
# Estructura de navegación
@settings_nav [
  %{
    section: "Account",
    items: [
      %{label: "Profile", path: "/settings/profile", icon: "hero-user"},
      %{label: "Preferences", path: "/settings/preferences", icon: "hero-cog-6-tooth"},
      %{label: "Notifications", path: "/settings/notifications", icon: "hero-bell"},
      %{label: "Security & access", path: "/settings/security", icon: "hero-shield-check"},
      %{label: "Connected accounts", path: "/settings/connected-accounts", icon: "hero-link"}
    ]
  },
  %{
    section: "Workspace",  # Solo si tiene permisos de admin en algún workspace
    items: [
      %{label: "General", path: "/settings/workspace", icon: "hero-building-office"},
      %{label: "Members", path: "/settings/workspace/members", icon: "hero-user-group"},
      %{label: "Billing", path: "/settings/workspace/billing", icon: "hero-credit-card"}  # Futuro
    ]
  },
  %{
    section: "Import / Export",  # Futuro
    items: [
      %{label: "Import", path: "/settings/import", icon: "hero-arrow-down-tray"},
      %{label: "Export", path: "/settings/export", icon: "hero-arrow-up-tray"}
    ]
  }
]
```

### Settings Layout Component

```elixir
# lib/storyarn_web/components/settings_layout.ex
defmodule StoryarnWeb.Components.SettingsLayout do
  use Phoenix.Component
  import StoryarnWeb.CoreComponents

  attr :current_path, :string, required: true
  attr :current_user, :map, required: true
  slot :inner_block, required: true

  def settings_layout(assigns) do
    ~H"""
    <div class="flex min-h-screen">
      <!-- Settings sidebar -->
      <aside class="w-64 border-r border-base-300 p-4">
        <!-- Back to app -->
        <.link navigate={~p"/workspaces"} class="flex items-center gap-2 text-sm text-base-content/70 hover:text-base-content mb-6">
          <.icon name="hero-chevron-left" class="size-4" />
          Back to app
        </.link>

        <!-- Navigation sections -->
        <nav class="space-y-6">
          <%= for section <- settings_sections(@current_user) do %>
            <div>
              <h3 class="text-xs font-semibold uppercase text-base-content/50 px-2 mb-2">
                <%= section.section %>
              </h3>
              <ul class="space-y-1">
                <%= for item <- section.items do %>
                  <li>
                    <.link
                      navigate={item.path}
                      class={[
                        "flex items-center gap-2 px-2 py-1.5 rounded text-sm",
                        @current_path == item.path && "bg-primary/10 text-primary",
                        @current_path != item.path && "hover:bg-base-200"
                      ]}
                    >
                      <.icon name={item.icon} class="size-4" />
                      <%= item.label %>
                    </.link>
                  </li>
                <% end %>
              </ul>
            </div>
          <% end %>
        </nav>
      </aside>

      <!-- Settings content -->
      <main class="flex-1 p-8 max-w-3xl">
        <%= render_slot(@inner_block) %>
      </main>
    </div>
    """
  end

  defp settings_sections(user) do
    # Retorna las secciones visibles según permisos del usuario
    # ...
  end
end
```

### Páginas de Settings

| Ruta | Página | Descripción |
|------|--------|-------------|
| `/settings/profile` | Profile | Display name, avatar, email |
| `/settings/preferences` | Preferences | Theme, language, notifications prefs |
| `/settings/notifications` | Notifications | Email preferences, in-app notifications |
| `/settings/security` | Security | Password change, 2FA (futuro) |
| `/settings/connected-accounts` | Connected Accounts | OAuth providers linked |
| `/settings/workspace` | Workspace General | Nombre, descripción, banner (admin only) |
| `/settings/workspace/members` | Workspace Members | Gestión de miembros (admin only) |

### Keyboard Shortcuts

Implementar shortcuts globales:
- `E` → Abrir Preferences
- `D` → Toggle dark mode
- `?` → Mostrar ayuda de shortcuts (futuro)

```javascript
// assets/js/hooks/keyboard_shortcuts.js
export const KeyboardShortcuts = {
  mounted() {
    this.handleKeydown = (e) => {
      // Ignorar si está en input/textarea
      if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') return;

      if (e.key === 'e' && !e.metaKey && !e.ctrlKey) {
        e.preventDefault();
        window.location.href = '/settings/preferences';
      }

      if (e.key === 'd' && !e.metaKey && !e.ctrlKey) {
        e.preventDefault();
        this.pushEvent('toggle-theme');
      }
    };

    document.addEventListener('keydown', this.handleKeydown);
  },

  destroyed() {
    document.removeEventListener('keydown', this.handleKeydown);
  }
}
```

---

## Fase 3: Tema y Estilos

### 3.1 Soporte para Light y Dark mode

Ambos modos deben estar soportados. El usuario puede elegir entre System/Light/Dark.

```css
/* assets/css/app.css */
@import "tailwindcss" source(none);
@source "../../lib/storyarn_web/**/*.{ex,heex}";
@source "../js/**/*.js";

@plugin "tailwindcss/heroicons";
@plugin "daisyui" {
  themes: light, dark;
}

/* Custom color scheme for both themes */
@layer base {
  [data-theme="light"] {
    --color-primary: #6366f1;      /* Indigo */
    --color-secondary: #8b5cf6;    /* Violet */
    --color-accent: #10b981;       /* Emerald for success */
  }

  [data-theme="dark"] {
    --color-primary: #818cf8;      /* Lighter indigo for dark mode */
    --color-secondary: #a78bfa;    /* Lighter violet */
    --color-accent: #34d399;       /* Lighter emerald */
  }
}

/* Sidebar specific styles */
@layer components {
  .sidebar-item {
    @apply flex items-center gap-2 px-3 py-2 rounded-lg transition-colors;
    @apply hover:bg-base-300;
  }

  .sidebar-item.active {
    @apply bg-primary/10 text-primary;
  }
}
```

### 3.2 Paleta de colores

**Light mode:**
- Fondo sidebar: `bg-base-200` (gris claro)
- Fondo contenido: `bg-base-100` (blanco)
- Cards: `bg-base-100` con borde sutil
- Texto: `text-base-content`

**Dark mode:**
- Fondo sidebar: `bg-base-200` (gris muy oscuro)
- Fondo contenido: `bg-base-100` (negro/gris oscuro)
- Cards: `bg-base-200`
- Texto: `text-base-content`

### 3.3 Theme persistence

El tema seleccionado se guarda en localStorage y se aplica via `data-theme` en `<html>`.
Ya existe implementación en el proyecto actual - mantenerla.

---

## Fase 4: Rutas y Navegación

### 4.1 Nuevas rutas

```elixir
# lib/storyarn_web/router.ex (modificar)

scope "/", StoryarnWeb do
  pipe_through [:browser, :require_authenticated_user]

  # Workspaces
  live "/workspaces", WorkspaceLive.Index, :index
  live "/workspaces/new", WorkspaceLive.New, :new
  live "/workspaces/:slug", WorkspaceLive.Show, :show
  live "/workspaces/:slug/settings", WorkspaceLive.Settings, :settings
  live "/workspaces/:slug/members", WorkspaceLive.Members, :members

  # Projects (ahora bajo workspace)
  live "/workspaces/:workspace_slug/projects/new", ProjectLive.New, :new

  # Project (acceso directo, workspace inferido)
  live "/projects/:id", ProjectLive.Show, :show
  live "/projects/:id/settings", ProjectLive.Settings, :settings
  # ... resto de rutas de proyecto
end
```

### 4.2 Redirect desde /projects a workspace default

Si el usuario accede a `/projects` sin workspace:
1. Redirigir al primer workspace del usuario
2. O mostrar página de "selecciona un workspace"

---

## Fase 5: Páginas a Crear/Refactorizar

### Páginas nuevas - Workspaces

| Página | Ruta | Descripción |
|--------|------|-------------|
| Workspace Index | `/workspaces` | Lista de workspaces (redirect al primero?) |
| Workspace Show | `/workspaces/:slug` | Dashboard con proyectos |
| Workspace New | `/workspaces/new` | Crear workspace |

### Páginas nuevas - Settings (estilo Linear)

| Página | Ruta | Descripción |
|--------|------|-------------|
| Profile | `/settings/profile` | Display name, avatar, email |
| Preferences | `/settings/preferences` | Theme, language |
| Notifications | `/settings/notifications` | Email prefs, in-app notifs |
| Security | `/settings/security` | Password, sessions |
| Connected Accounts | `/settings/connected-accounts` | OAuth providers |
| Workspace General | `/settings/workspace` | Nombre, banner, descripción (admin) |
| Workspace Members | `/settings/workspace/members` | Gestión miembros (admin) |

### Páginas a refactorizar

| Página actual | Cambios |
|---------------|---------|
| Project Dashboard | Mover a Workspace Show, cambiar layout |
| Project Show | Adaptar al nuevo layout con sidebar |
| Project Settings | Añadir sección de permisos específicos |
| User Settings | **Eliminar** - Reemplazado por Settings pages |

### Páginas sin cambios significativos

- Login/Register (usar layout `auth` sin sidebar)
- Entity/Template/Variable pages (solo adaptar al nuevo layout)

---

## Fase 6: Componentes UI Adicionales

### 6.1 Lista de componentes a crear

| Componente | Ubicación | Descripción |
|------------|-----------|-------------|
| `sidebar/1` | `sidebar.ex` | Sidebar principal con workspaces |
| `user_dropdown/1` | `sidebar.ex` | Dropdown del usuario (Profile, Preferences, Theme) |
| `workspace_header/1` | `workspace_header.ex` | Banner + título + descripción |
| `project_card/1` | `project_card.ex` | Card de proyecto en grid |
| `settings_layout/1` | `settings_layout.ex` | Layout para Settings con nav lateral |
| `settings_nav/1` | `settings_layout.ex` | Navegación categorizada del settings |
| `member_avatar/1` | `core_components.ex` | Avatar de usuario con fallback |
| `avatar_group/1` | `core_components.ex` | Grupo de avatares superpuestos |
| `empty_state/1` | `core_components.ex` | Estado vacío con icono y mensaje |
| `search_input/1` | `core_components.ex` | Input de búsqueda con icono |
| `kbd/1` | `core_components.ex` | Keyboard shortcut badge |

### 6.2 Iconos necesarios

Todos disponibles en Heroicons:
- `hero-plus` - Crear nuevo
- `hero-cog-6-tooth` - Settings/Preferences
- `hero-folder-open` - Empty state
- `hero-document-text` - Proyecto sin thumbnail
- `hero-user-group` - Miembros
- `hero-user` - Profile
- `hero-magnifying-glass` - Búsqueda
- `hero-chevron-left` - Back to app
- `hero-chevron-right` - Breadcrumb separator
- `hero-ellipsis-vertical` - Menu dropdown
- `hero-sun` - Light mode
- `hero-moon` - Dark mode
- `hero-bell` - Notifications
- `hero-shield-check` - Security
- `hero-link` - Connected accounts
- `hero-building-office` - Workspace
- `hero-credit-card` - Billing
- `hero-arrow-down-tray` - Import
- `hero-arrow-up-tray` - Export
- `hero-arrow-right-on-rectangle` - Log out

### 6.3 JavaScript Hooks

| Hook | Archivo | Descripción |
|------|---------|-------------|
| `KeyboardShortcuts` | `keyboard_shortcuts.js` | Shortcuts globales (E, D) |
| `ThemeToggle` | `theme_toggle.js` | Persistencia del tema |
| `SidebarCollapse` | `sidebar.js` | Colapsar sidebar en mobile |

---

## Checklist de Implementación

### Fase 0: Modelo de Datos ✅
- [x] Crear migración `workspaces`
- [x] Crear migración `workspace_memberships`
- [x] Crear migración para añadir `workspace_id` a `projects`
- [x] Crear schema `Workspace`
- [x] Crear schema `WorkspaceMembership`
- [x] Crear contexto `Workspaces`
- [x] Crear módulo `Authorization` con lógica de permisos
- [x] Actualizar contexto `Projects` para filtrar por workspace
- [x] Escribir tests para el modelo y permisos

### Fase 0.5: Onboarding ✅
- [x] Modificar `register_user/1` para crear workspace por defecto
- [x] Añadir traducciones para nombre de workspace default
- [x] Implementar `get_default_workspace/1`
- [x] Actualizar redirect post-login a workspace default
- [x] Actualizar `/` para redirect si autenticado
- [x] Crear/actualizar landing page para visitantes no autenticados

### Fase 1: Layout ✅
- [x] Crear componente `sidebar/1` (`lib/storyarn_web/components/sidebar.ex`)
- [x] Crear componente `user_dropdown/1` (incluido en sidebar.ex)
- [x] Modificar layout `app` para incluir sidebar
- [x] Crear layout `auth` sin sidebar
- [x] Crear layout `public` para páginas públicas
- [x] Actualizar `root.html.heex` (quitar nav superior, añadir keyboard shortcuts)
- [x] Pasar `workspaces` y `current_workspace` a todas las LiveViews
- [x] Implementar keyboard shortcuts globales (D: dark mode, E: settings)
- [x] Responsive sidebar con drawer en mobile

### Fase 2: Workspace Dashboard ✅
- [x] Crear componente `workspace_header/1` (inline en WorkspaceLive.Show)
- [x] Crear componente `project_card/1` (inline en WorkspaceLive.Show)
- [x] Crear `WorkspaceLive.Show`
- [x] Crear `WorkspaceLive.New`
- [x] Crear `WorkspaceLive.Settings`
- [x] Crear `WorkspaceLive.Index` (redirect to default)

### Fase 2.5: Settings (estilo Linear) ✅
- [x] Crear componente `settings_layout/1`
- [x] Crear `SettingsLive.Profile` (display name, email)
- [ ] Crear `SettingsLive.Preferences` (futuro: theme, language)
- [ ] Crear `SettingsLive.Notifications` (futuro: email preferences)
- [x] Crear `SettingsLive.Security` (password management)
- [x] Crear `SettingsLive.Connections` (OAuth: GitHub, Google, Discord)
- [ ] Crear `SettingsLive.Workspace` (futuro: general settings, admin only)
- [ ] Crear `SettingsLive.WorkspaceMembers` (futuro: members, admin only)
- [x] Implementar keyboard shortcuts (E, D) - ✅ Implementado en root.html.heex
- [x] Migrar funcionalidad de User Settings actual
- [x] Eliminar old UserLive.Settings (single-page)
- [x] Actualizar tests para multi-page structure

### Fase 3: Tema ✅
- [x] Configurar soporte light/dark mode (ya existía, mejorado)
- [x] Ajustar paleta de colores para ambos modos (daisyUI themes)
- [x] Crear estilos custom para sidebar
- [x] Theme toggle en user dropdown
- [x] Persistencia del tema en localStorage
- [ ] Verificar contraste y accesibilidad en ambos modos

### Fase 4: Rutas ✅
- [x] Añadir rutas de workspaces
- [x] Modificar rutas de projects (legacy routes mantenidas)
- [x] Implementar redirect desde `/` y `/workspaces`
- [x] Actualizar todos los `navigate` en el código

### Fase 5: Refactorizar páginas existentes ✅
- [x] Adaptar Project Dashboard (usa Layouts.app con sidebar)
- [x] Adaptar Project Show (usa Layouts.app con sidebar)
- [x] Adaptar Project Settings (usa Layouts.app con sidebar)
- [x] Adaptar User Settings (usa Layouts.app con sidebar)
- [x] Adaptar Entity/Template/Variable pages (usan Layouts.app con sidebar)
- [x] Adaptar Project Invitation (usa Layouts.app con sidebar)

### Fase 6: Componentes adicionales ✅
- [x] `member_avatar/1` - ✅ en sidebar.ex
- [x] `avatar_group/1` - ✅ en core_components.ex
- [x] `empty_state/1` - ✅ en core_components.ex
- [x] `search_input/1` - ✅ en core_components.ex
- [x] `kbd/1` - ✅ en core_components.ex
- [x] Keyboard shortcuts en JS (root.html.heex)
- [x] Theme toggle en JS (root.html.heex)
- [x] Sidebar responsive con drawer (daisyUI drawer)

### QA
- [ ] Test manual de navegación completa
- [x] Verificar responsive (mobile sidebar collapse) - implementado con daisyUI drawer
- [ ] Actualizar E2E tests
- [ ] Verificar i18n en nuevos componentes

---

## Notas Técnicas

### Pasar workspaces a todas las LiveViews

Opción 1: `on_mount` hook global
```elixir
def on_mount(:load_workspaces, _params, _session, socket) do
  if socket.assigns[:current_user] do
    workspaces = Workspaces.list_workspaces_for_user(socket.assigns.current_user)
    {:cont, assign(socket, :workspaces, workspaces)}
  else
    {:cont, socket}
  end
end
```

Opción 2: Componente de layout que hace query
```elixir
# El layout recibe current_user y hace el query internamente
def app(assigns) do
  workspaces = Workspaces.list_workspaces_for_user(assigns.current_user)
  assigns = assign(assigns, :workspaces, workspaces)
  # ...
end
```

### Sidebar responsive (mobile)

Para mobile, el sidebar debería:
1. Ocultarse por defecto
2. Mostrarse como drawer/overlay al hacer tap en hamburger menu
3. Usar daisyUI drawer component

```heex
<div class="drawer lg:drawer-open">
  <input id="sidebar-drawer" type="checkbox" class="drawer-toggle" />
  <div class="drawer-content">
    <!-- Page content -->
    <label for="sidebar-drawer" class="btn btn-square btn-ghost lg:hidden">
      <.icon name="hero-bars-3" class="size-6" />
    </label>
    <%= @inner_content %>
  </div>
  <div class="drawer-side">
    <label for="sidebar-drawer" class="drawer-overlay"></label>
    <.sidebar ... />
  </div>
</div>
```

---

## Orden de Ejecución Recomendado

1. **Fase 0** - Modelo de datos (Workspaces, Memberships, Permisos)
2. **Fase 0.5** - Onboarding (workspace default al registrar, redirects)
3. **Fase 1** - Layout básico con sidebar + user dropdown
4. **Fase 3** - Tema light/dark
5. **Fase 2** - Workspace dashboard (header + project cards)
6. **Fase 2.5** - Settings pages (estilo Linear)
7. **Fase 4** - Rutas y navegación
8. **Fase 5** - Refactorizar páginas existentes
9. **Fase 6** - Componentes adicionales y polish

---

*Este plan es independiente del IMPLEMENTATION_PLAN.md y se enfoca exclusivamente en la refactorización visual y el nuevo modelo de Workspaces.*
