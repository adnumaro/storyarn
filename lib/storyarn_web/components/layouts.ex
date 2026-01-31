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

  This layout is used for authenticated pages that show workspace navigation.

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
              <.icon name="hero-bars-3" class="size-6" />
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
  Renders a project layout with pages tree sidebar.

  This layout is used for project-specific pages that show the page navigation tree.

  ## Examples

      <Layouts.project
        flash={@flash}
        current_scope={@current_scope}
        project={@project}
        workspace={@workspace}
        pages_tree={@pages_tree}
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

  attr :pages_tree, :list,
    default: [],
    doc: "pages with preloaded children for the tree"

  attr :current_path, :string, default: "", doc: "current path for navigation highlighting"

  attr :selected_page_id, :string,
    default: nil,
    doc: "currently selected page ID for tree highlighting"

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
              <.icon name="hero-bars-3" class="size-6" />
            </label>
          </div>
          <div class="flex-1">
            <.link
              navigate={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}"}
              class="flex items-center gap-2"
            >
              <.icon name="hero-folder" class="size-5" />
              <span class="font-bold truncate">{@project.name}</span>
            </.link>
          </div>
          <div class="flex-none">
            <.theme_toggle />
          </div>
        </header>

        <%!-- Main content area --%>
        <main class="flex-1 overflow-y-auto bg-base-100 p-6 lg:p-8">
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
          pages_tree={@pages_tree}
          current_path={@current_path}
          selected_page_id={@selected_page_id}
        />
      </div>
    </div>
    """
  end

  @doc """
  Renders a centered layout without sidebar for auth pages.

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
  Renders a simple centered layout for public pages.

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

  This layout has its own navigation sidebar for settings pages only.

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
            <.icon name="hero-chevron-left" class="size-4" />
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
              <.icon name="hero-chevron-left" class="size-4" />
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
        %{label: gettext("Profile"), path: ~p"/users/settings", icon: "hero-user"},
        %{
          label: gettext("Security"),
          path: ~p"/users/settings/security",
          icon: "hero-shield-check"
        },
        %{
          label: gettext("Connected accounts"),
          path: ~p"/users/settings/connections",
          icon: "hero-link"
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
              icon: "hero-cog-6-tooth"
            },
            %{
              label: gettext("Members"),
              path: ~p"/users/settings/workspaces/#{workspace.slug}/members",
              icon: "hero-user-group"
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
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
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
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
