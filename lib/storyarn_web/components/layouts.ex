defmodule StoryarnWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use StoryarnWeb, :html
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.ProjectSidebar
  import StoryarnWeb.Components.Sidebar

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders the main app layout with sidebar.

  This layout is used for authenticated sheets that show workspace navigation.

  ## Examples

      <Layouts.app flash={@flash} current_scope={@current_scope} workspaces={@workspaces}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :workspaces, :list, default: [], doc: "list of workspaces for the sidebar"
  attr :current_workspace, :map, default: nil, doc: "the currently selected workspace"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="drawer lg:drawer-open">
      <input id="sidebar-drawer" type="checkbox" class="drawer-toggle" />

      <div class="drawer-content flex flex-col min-h-screen">
        <%!-- Mobile header with hamburger --%>
        <header class="navbar bg-base-100 border-b border-base-300 lg:hidden">
          <div class="flex-none">
            <label for="sidebar-drawer" class="btn btn-square btn-ghost">
              <.icon name="menu" class="size-6" />
            </label>
          </div>
          <div class="flex-1">
            <.link navigate="/" class="flex items-center gap-2">
              <img src={~p"/images/logo.svg"} alt="Storyarn" class="w-6 h-6" />
              <span class="font-bold">Storyarn</span>
            </.link>
          </div>
          <div class="flex-none">
            <.theme_toggle />
          </div>
        </header>

        <%!-- Main content area --%>
        <main class="flex-1 overflow-y-auto bg-base-100">
          {render_slot(@inner_block)}
        </main>

        <.flash_group flash={@flash} />
      </div>

      <%!-- Sidebar drawer --%>
      <div class="drawer-side z-40">
        <label for="sidebar-drawer" aria-label="close sidebar" class="drawer-overlay"></label>
        <.sidebar
          :if={@current_scope && @current_scope.user}
          current_user={@current_scope.user}
          workspaces={@workspaces}
          current_workspace={@current_workspace}
        />
      </div>
    </div>
    """
  end

  @doc """
  Renders a project layout with sheets tree sidebar.

  This layout is used for project-specific sheets that show the sheet navigation tree.

  ## Examples

      <Layouts.project
        flash={@flash}
        current_scope={@current_scope}
        project={@project}
        workspace={@workspace}
        sheets_tree={@sheets_tree}
        current_path={@current_path}
      >
        <h1>Content</h1>
      </Layouts.project>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :project, :map, required: true, doc: "the current project"
  attr :workspace, :map, required: true, doc: "the workspace the project belongs to"

  attr :sheets_tree, :list,
    default: [],
    doc: "sheets with preloaded children for the tree"

  attr :flows_tree, :list, default: [], doc: "flows with preloaded children for the tree"

  attr :screenplays_tree, :list,
    default: [],
    doc: "screenplays with preloaded children for the tree"

  attr :active_tool, :atom, default: :sheets, doc: "active tool (:sheets, :flows, or :screenplays)"

  attr :current_path, :string, default: "", doc: "current path for navigation highlighting"

  attr :selected_sheet_id, :string,
    default: nil,
    doc: "currently selected sheet ID for tree highlighting"

  attr :selected_flow_id, :string,
    default: nil,
    doc: "currently selected flow ID for sidebar highlighting"

  attr :selected_screenplay_id, :string,
    default: nil,
    doc: "currently selected screenplay ID for sidebar highlighting"

  attr :can_edit, :boolean, default: false, doc: "whether the user can edit sheets"

  slot :inner_block, required: true

  def project(assigns) do
    ~H"""
    <div class="drawer lg:drawer-open">
      <input id="project-sidebar-drawer" type="checkbox" class="drawer-toggle" />

      <div class="drawer-content flex flex-col min-h-screen">
        <%!-- Mobile header with hamburger --%>
        <header class="navbar bg-base-100 border-b border-base-300 lg:hidden">
          <div class="flex-none">
            <label for="project-sidebar-drawer" class="btn btn-square btn-ghost">
              <.icon name="menu" class="size-6" />
            </label>
          </div>
          <div class="flex-1">
            <.link
              navigate={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}"}
              class="flex items-center gap-2"
            >
              <.icon name="folder" class="size-5" />
              <span class="font-bold truncate">{@project.name}</span>
            </.link>
          </div>
          <div class="flex-none">
            <.theme_toggle />
          </div>
        </header>

        <%!-- Main content area --%>
        <main class="flex-1 overflow-y-auto bg-base-100 py-6 lg:py-8 px-12 lg:px-8">
          {render_slot(@inner_block)}
        </main>

        <.flash_group flash={@flash} />
      </div>

      <%!-- Sidebar drawer --%>
      <div class="drawer-side z-40">
        <label for="project-sidebar-drawer" aria-label="close sidebar" class="drawer-overlay"></label>
        <.project_sidebar
          project={@project}
          workspace={@workspace}
          sheets_tree={@sheets_tree}
          flows_tree={@flows_tree}
          screenplays_tree={@screenplays_tree}
          active_tool={@active_tool}
          current_path={@current_path}
          selected_sheet_id={@selected_sheet_id}
          selected_flow_id={@selected_flow_id}
          selected_screenplay_id={@selected_screenplay_id}
          can_edit={@can_edit}
        />
      </div>
    </div>
    """
  end

  @doc """
  Renders a centered layout without sidebar for auth sheets.

  ## Examples

      <Layouts.auth flash={@flash}>
        <h1>Login</h1>
      </Layouts.auth>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def auth(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col">
      <header class="navbar px-4 sm:px-6 lg:px-8">
        <div class="flex-1">
          <.link navigate="/" class="flex items-center gap-2">
            <img src={~p"/images/logo.svg"} alt="Storyarn" class="w-8 h-8" />
            <span class="text-lg font-bold">Storyarn</span>
          </.link>
        </div>
        <div class="flex-none">
          <.theme_toggle />
        </div>
      </header>

      <main class="flex-1 flex items-center justify-center px-4 py-12 sm:px-6 lg:px-8">
        <div class="w-full max-w-md space-y-6">
          {render_slot(@inner_block)}
        </div>
      </main>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  @doc """
  Renders a simple centered layout for public sheets.

  ## Examples

      <Layouts.public flash={@flash}>
        <h1>Welcome</h1>
      </Layouts.public>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def public(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col">
      <header class="navbar px-4 sm:px-6 lg:px-8">
        <div class="flex-1">
          <.link navigate="/" class="flex items-center gap-2">
            <img src={~p"/images/logo.svg"} alt="Storyarn" class="w-8 h-8" />
            <span class="text-lg font-bold">Storyarn</span>
          </.link>
        </div>
        <div class="flex-none flex items-center gap-2">
          <.theme_toggle />
          <%= if @current_scope && @current_scope.user do %>
            <.link navigate={~p"/workspaces"} class="btn btn-ghost btn-sm">
              {gettext("Dashboard")}
            </.link>
          <% else %>
            <.link navigate={~p"/users/log-in"} class="btn btn-ghost btn-sm">
              {gettext("Log in")}
            </.link>
            <.link navigate={~p"/users/register"} class="btn btn-primary btn-sm">
              {gettext("Sign up")}
            </.link>
          <% end %>
        </div>
      </header>

      <main class="flex-1">
        {render_slot(@inner_block)}
      </main>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  @doc """
  Renders a standalone settings layout without the workspace sidebar.

  This layout has its own navigation sidebar for settings sheets only.

  ## Examples

      <Layouts.settings
        flash={@flash}
        current_scope={@current_scope}
        workspaces={@workspaces}
        current_path={@current_path}
      >
        <:title>Profile</:title>
        <:subtitle>Manage your profile</:subtitle>
        <p>Content here</p>
      </Layouts.settings>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :current_scope, :map, required: true, doc: "the current scope"
  attr :workspaces, :list, default: [], doc: "list of workspaces for settings nav"
  attr :current_path, :string, required: true, doc: "current settings path for nav highlighting"

  slot :title, required: true
  slot :subtitle
  slot :inner_block, required: true

  def settings(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col">
      <%!-- Header --%>
      <header class="navbar px-4 sm:px-6 lg:px-8 border-b border-base-300">
        <div class="flex-1">
          <.link navigate="/" class="flex items-center gap-2">
            <img src={~p"/images/logo.svg"} alt="Storyarn" class="w-8 h-8" />
            <span class="text-lg font-bold">Storyarn</span>
          </.link>
        </div>
        <div class="flex-none">
          <.theme_toggle />
        </div>
      </header>

      <%!-- Main content with settings nav --%>
      <div class="flex-1 flex">
        <%!-- Settings navigation sidebar --%>
        <aside class="w-64 border-r border-base-300 p-4 hidden lg:block overflow-y-auto">
          <.link
            navigate={~p"/workspaces"}
            class="flex items-center gap-2 text-sm text-base-content/70 hover:text-base-content mb-6"
          >
            <.icon name="chevron-left" class="size-4" />
            {gettext("Back to app")}
          </.link>

          <nav class="space-y-6">
            <div :for={section <- settings_sections(@workspaces)}>
              <h3 class="text-xs font-semibold uppercase text-base-content/50 px-2 mb-2">
                {section.label}
              </h3>
              <ul class="space-y-1">
                <li :for={item <- section.items}>
                  <.link
                    navigate={item.path}
                    class={[
                      "flex items-center gap-2 px-2 py-1.5 rounded text-sm",
                      @current_path == item.path && "bg-primary/10 text-primary",
                      @current_path != item.path && "hover:bg-base-200"
                    ]}
                  >
                    <.icon name={item.icon} class="size-4" />
                    {item.label}
                  </.link>
                </li>
              </ul>
            </div>
          </nav>
        </aside>

        <%!-- Settings content --%>
        <main class="flex-1 p-8 overflow-y-auto">
          <div class="max-w-3xl mx-auto">
            <%!-- Mobile back link --%>
            <.link
              navigate={~p"/workspaces"}
              class="flex items-center gap-2 text-sm text-base-content/70 hover:text-base-content mb-6 lg:hidden"
            >
              <.icon name="chevron-left" class="size-4" />
              {gettext("Back to app")}
            </.link>

            <.header>
              {render_slot(@title)}
              <:subtitle :if={@subtitle != []}>
                {render_slot(@subtitle)}
              </:subtitle>
            </.header>

            <div class="mt-8">
              {render_slot(@inner_block)}
            </div>
          </div>
        </main>
      </div>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  defp settings_sections(workspaces) do
    account_section = %{
      label: gettext("Account"),
      items: [
        %{label: gettext("Profile"), path: ~p"/users/settings", icon: "user"},
        %{
          label: gettext("Security"),
          path: ~p"/users/settings/security",
          icon: "shield-check"
        },
        %{
          label: gettext("Connected accounts"),
          path: ~p"/users/settings/connections",
          icon: "link"
        }
      ]
    }

    workspace_sections =
      Enum.map(workspaces, fn workspace ->
        %{
          label: workspace.name,
          items: [
            %{
              label: gettext("General"),
              path: ~p"/users/settings/workspaces/#{workspace.slug}/general",
              icon: "settings"
            },
            %{
              label: gettext("Members"),
              path: ~p"/users/settings/workspaces/#{workspace.slug}/members",
              icon: "users"
            }
          ]
        }
      end)

    [account_section | workspace_sections]
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="refresh-cw" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="refresh-cw" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
