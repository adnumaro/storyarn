defmodule StoryarnWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use StoryarnWeb, :html
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.FocusLayout
  import StoryarnWeb.Components.MemberComponents, only: [user_avatar: 1]
  import StoryarnWeb.DocsLive.Components.DocsSidebar

  alias Phoenix.LiveView.JS

  # Note: StoryarnWeb.Components.Sidebar is no longer imported here.
  # The workspace sidebar is now rendered inline in the app layout.

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  attr :class, :string, default: "w-8 h-8"

  defp app_logo(assigns) do
    ~H"""
    <img src={~p"/images/logo-light-64.png"} alt="Storyarn" class={[@class, "dark:hidden"]} />
    <img src={~p"/images/logo-dark-64.png"} alt="Storyarn" class={[@class, "hidden dark:block"]} />
    """
  end

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
    <div
      id="app-layout"
      phx-hook="SettingsSidebar"
      class="h-screen w-screen overflow-hidden relative bg-base-100"
    >
      <%!-- Hidden checkbox for mobile sidebar toggle --%>
      <input id="app-sidebar-check" type="checkbox" class="peer hidden" />

      <%!-- Left floating toolbar (top-left) --%>
      <div class="fixed top-3 left-3 z-[1020] flex items-stretch gap-2">
        <nav class="flex items-center gap-1 px-1 py-1 surface-panel w-60">
          <%!-- Mobile sidebar toggle --%>
          <div class="contents md:hidden">
            <label for="app-sidebar-check" class="toolbar-btn btn-square cursor-pointer">
              <.icon name="panel-left" class="size-4" />
            </label>
            <div class="w-px h-5 bg-base-300"></div>
          </div>

          <%!-- User dropdown --%>
          <div
            :if={@current_scope && @current_scope.user}
            class="dropdown dropdown-bottom flex flex-1 min-w-0"
          >
            <button tabindex="0" class="toolbar-btn gap-1.5 font-medium flex-1 min-w-0">
              <.user_avatar user={@current_scope.user} size="xs" />
              <span class="text-sm truncate">
                {@current_scope.user.display_name || @current_scope.user.email}
              </span>
              <.icon name="chevron-down" class="size-3 opacity-50" />
            </button>
            <div
              tabindex="0"
              class="dropdown-content bg-base-200 border border-base-300 rounded-lg shadow-sm w-max max-w-72 z-[60] mt-3"
            >
              <div class="px-4 py-3">
                <p class="text-sm font-medium truncate">
                  {@current_scope.user.display_name || @current_scope.user.email}
                </p>
                <p
                  :if={@current_scope.user.display_name}
                  class="text-xs text-base-content/50 truncate"
                >
                  {@current_scope.user.email}
                </p>
              </div>
              <div class="border-t border-base-300"></div>
              <ul class="menu p-1 text-sm">
                <li>
                  <.link navigate={~p"/users/settings"}>
                    <.icon name="user" class="size-5" />
                    {gettext("Account settings")}
                  </.link>
                </li>
                <li>
                  <button
                    phx-click={JS.dispatch("phx:set-theme")}
                    data-phx-theme="toggle"
                    class="gap-2 justify-between"
                  >
                    <span class="flex items-center gap-2">
                      <.icon name="moon" class="size-5 dark:hidden" />
                      <.icon name="sun" class="size-5 hidden dark:block" />
                      {gettext("Dark mode")}
                    </span>
                  </button>
                </li>
                <div class="divider my-1"></div>
                <li>
                  <.link href={~p"/users/log-out"} method="delete">
                    <.icon name="log-out" class="size-5" />
                    {gettext("Log out")}
                  </.link>
                </li>
              </ul>
            </div>
          </div>
        </nav>
      </div>

      <%!-- Mobile overlay (closes sidebar on tap) --%>
      <label
        for="app-sidebar-check"
        class="fixed inset-0 bg-black/30 z-[1005] hidden peer-checked:block peer-checked:md:hidden cursor-pointer"
      />

      <%!-- Workspace sidebar (floating panel) --%>
      <div
        :if={@current_scope && @current_scope.user}
        class={[
          "fixed left-3 top-[76px] bottom-3 z-[1010] w-60 flex flex-col surface-panel overflow-hidden",
          "transition-transform duration-200",
          "-translate-x-[calc(100%+0.75rem)] peer-checked:translate-x-0 md:translate-x-0"
        ]}
      >
        <nav class="flex-1 overflow-y-auto p-2 space-y-5">
          <div>
            <h3 class="text-xs font-semibold uppercase text-base-content/50 px-2 mb-2">
              {gettext("Workspaces")}
            </h3>
            <ul class="space-y-0.5">
              <li :for={workspace <- @workspaces}>
                <.link
                  navigate={~p"/workspaces/#{workspace.slug}"}
                  class={[
                    "flex items-center gap-2 px-2 py-1.5 rounded-lg text-sm",
                    @current_workspace && @current_workspace.id == workspace.id &&
                      "bg-base-content/5 font-medium",
                    !(@current_workspace && @current_workspace.id == workspace.id) &&
                      "hover:bg-base-content/5"
                  ]}
                >
                  <span
                    class="w-2 h-2 rounded-full shrink-0"
                    style={"background: #{workspace.color || "#6366f1"}"}
                  />
                  <span class="truncate">{workspace.name}</span>
                </.link>
              </li>
            </ul>
          </div>
        </nav>

        <div class="p-2 border-t border-base-300">
          <.link
            navigate={~p"/workspaces/new"}
            class="flex items-center gap-2 px-2 py-1.5 rounded-lg text-sm hover:bg-base-content/5"
          >
            <.icon name="plus" class="size-4" />
            {gettext("New workspace")}
          </.link>
        </div>
      </div>

      <%!-- Main content area --%>
      <main class="h-full overflow-y-auto pt-[76px] pb-4 px-4 md:pl-[264px]">
        {render_slot(@inner_block)}
      </main>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  @doc """
  Renders the focus layout — full-screen content with floating toolbars and pinnable tree panel.

  ## Examples

      <Layouts.focus
        flash={@flash}
        current_scope={@current_scope}
        project={@project}
        workspace={@workspace}
        active_tool={:sheets}
        has_tree={true}
        tree_panel_open={@tree_panel_open}
        tree_panel_pinned={@tree_panel_pinned}
        can_edit={@can_edit}
        online_users={@online_users}
      >
        <:tree_content>
          <SheetTree.sheets_section sheets_tree={@sheets_tree} ... />
        </:tree_content>
        <:content_header>
          <h1>Sheet Title</h1>
        </:content_header>
        Content here
      </Layouts.focus>
  """
  attr :flash, :map, required: true

  attr :current_scope, :map,
    default: nil,
    doc: "the current scope"

  attr :project, :map, required: true, doc: "the current project"
  attr :workspace, :map, required: true, doc: "the workspace the project belongs to"

  attr :active_tool, :atom,
    default: :sheets,
    doc: "active tool (:sheets, :flows, :screenplays, :scenes, :assets, :localization)"

  attr :has_tree, :boolean, default: true, doc: "whether this page has a tree panel"
  attr :tree_panel_open, :boolean, default: false, doc: "whether the tree panel is open"
  attr :tree_panel_pinned, :boolean, default: false, doc: "whether the tree panel is pinned"
  attr :show_pin, :boolean, default: true, doc: "whether to show pin/close in tree panel footer"
  attr :can_edit, :boolean, default: false, doc: "whether the user can edit content"
  attr :online_users, :list, default: [], doc: "list of online user presence maps"

  attr :on_dashboard, :boolean,
    default: false,
    doc: "whether the current page is the tool dashboard"

  attr :show_tool_switcher, :boolean,
    default: true,
    doc: "whether to show the tool switcher dropdown"

  attr :canvas_mode, :boolean,
    default: false,
    doc: "when true, main area has no padding/scroll (canvas views)"

  slot :tree_content, doc: "tree panel content (tree component)"
  slot :top_bar_extra, doc: "extra content rendered next to the left toolbar (same row)"
  slot :top_bar_extra_right, doc: "extra content rendered next to the right toolbar (same row)"
  slot :content_header, doc: "optional header above main content"
  slot :inner_block, required: true

  def focus(assigns) do
    current_user_id =
      case assigns.current_scope do
        %{user: %{id: id}} -> id
        _ -> nil
      end

    is_super_admin =
      case assigns.current_scope do
        %{user: %{is_super_admin: true}} -> true
        _ -> false
      end

    project_theme_style =
      case assigns.project do
        %{settings: %{"theme" => %{"primary" => p, "accent" => a}}}
        when is_binary(p) and is_binary(a) ->
          alias Storyarn.Shared.ColorUtils

          primary = ColorUtils.hex_to_oklch(p)
          primary_dark = ColorUtils.darken_oklch(p)
          accent = ColorUtils.hex_to_oklch(a)
          accent_dark = ColorUtils.darken_oklch(a)

          Phoenix.HTML.raw("""
          <style>
            :root, [data-theme="light"], [data-theme="dark"] {
              --color-primary: #{primary};
              --color-accent: #{accent};
              --gradient-primary-from: #{primary};
              --gradient-primary-to: #{primary_dark};
              --gradient-accent-from: #{accent};
              --gradient-accent-to: #{accent_dark};
            }
          </style>
          """)

        _ ->
          nil
      end

    assigns =
      assigns
      |> assign(:current_user_id, current_user_id)
      |> assign(:is_super_admin, is_super_admin)
      |> assign(:project_theme_style, project_theme_style)

    ~H"""
    {if @project_theme_style, do: @project_theme_style}
    <div id="layout-wrapper" class="h-screen w-screen overflow-hidden relative bg-base-100">
      <%!-- Left floating toolbar row (top-left) --%>
      <div class="fixed top-3 left-3 z-[1020] flex items-stretch gap-2">
        <.left_toolbar
          active_tool={@active_tool}
          has_tree={@has_tree}
          tree_panel_open={@tree_panel_open}
          workspace={@workspace}
          project={@project}
          is_super_admin={@is_super_admin}
          show_tool_switcher={@show_tool_switcher}
        />
        {render_slot(@top_bar_extra)}
      </div>

      <%!-- Right floating toolbar row (top-right) --%>
      <div :if={@current_user_id} class="fixed top-3 right-3 z-[1020] flex items-stretch gap-2">
        {render_slot(@top_bar_extra_right)}
        <.right_toolbar
          workspace={@workspace}
          project={@project}
          online_users={@online_users}
          current_user_id={@current_user_id}
          current_scope={@current_scope}
        />
      </div>

      <%!-- Mobile overlay (closes tree panel on tap) --%>
      <div
        :if={@has_tree && @tree_content != [] && @tree_panel_open}
        class="fixed inset-0 bg-black/30 z-[1005] md:hidden cursor-pointer"
        phx-click="tree_panel_toggle"
      />

      <%!-- Tree panel (always in DOM for animation, slides in/out) --%>
      <.tree_panel
        :if={@has_tree && @tree_content != []}
        tree_panel_open={@tree_panel_open}
        active_tool={@active_tool}
        on_dashboard={@on_dashboard}
        tree_panel_pinned={@tree_panel_pinned}
        show_pin={@show_pin}
        can_edit={@can_edit}
        workspace={@workspace}
        project={@project}
      >
        <:tree_content>
          {render_slot(@tree_content)}
        </:tree_content>
      </.tree_panel>

      <%!-- Main content area --%>
      <main
        id="main-content"
        phx-hook={unless(@canvas_mode, do: "ScrollCollapse")}
        class={[
          "h-full",
          if(@canvas_mode,
            do: "overflow-hidden",
            else: [
              "overflow-y-auto pt-[76px] pb-4 px-4 transition-[padding-left] duration-200",
              @has_tree && @tree_panel_open && "md:pl-[264px]"
            ]
          )
        ]}
      >
        <div :if={@content_header != []} class="mb-4">
          {render_slot(@content_header)}
        </div>
        {render_slot(@inner_block)}
      </main>

      <.flash_group flash={@flash} />
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
            <.app_logo class="w-8 h-8" />
            <span class="text-xl brand-logotype">Storyarn</span>
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
            <.app_logo class="w-8 h-8" />
            <span class="text-xl brand-logotype">Storyarn</span>
          </.link>
        </div>
        <%!-- Desktop nav --%>
        <div class="flex-none hidden md:flex items-center gap-6">
          <div class="flex items-center gap-1">
            <.link navigate={~p"/docs"} class="btn btn-ghost btn-sm">
              {gettext("Docs")}
            </.link>
            <.link navigate={~p"/contact"} class="btn btn-ghost btn-sm">
              {gettext("Contact")}
            </.link>
          </div>
          <div class="flex items-center gap-1">
            <%= if @current_scope && @current_scope.user do %>
              <.link navigate={~p"/workspaces"} class="btn btn-ghost btn-sm">
                {gettext("Dashboard")}
              </.link>
            <% else %>
              <a href="#waitlist" class="btn btn-primary btn-sm">
                {gettext("Request access")}
              </a>
              <.link navigate={~p"/users/log-in"} class="btn btn-ghost btn-sm">
                {gettext("Log in")}
              </.link>
            <% end %>
          </div>
        </div>
        <%!-- Mobile hamburger --%>
        <div class="flex-none md:hidden">
          <button
            phx-click={JS.toggle(to: "#mobile-nav", in: "fade-in", out: "fade-out")}
            class="btn btn-ghost btn-square btn-sm"
            aria-label={gettext("Menu")}
          >
            <.icon name="menu" class="size-5" />
          </button>
        </div>
      </header>

      <%!-- Mobile nav overlay --%>
      <nav
        id="mobile-nav"
        class="hidden md:hidden fixed inset-0 z-50 bg-base-100"
        phx-click-away={JS.hide(to: "#mobile-nav", transition: "fade-out")}
      >
        <div class="flex items-center justify-between px-4 py-3">
          <.link navigate="/" class="flex items-center gap-2">
            <.app_logo class="w-8 h-8" />
            <span class="text-xl brand-logotype">Storyarn</span>
          </.link>
          <button
            phx-click={JS.hide(to: "#mobile-nav", transition: "fade-out")}
            class="btn btn-ghost btn-square btn-sm"
            aria-label={gettext("Close")}
          >
            <.icon name="x" class="size-5" />
          </button>
        </div>
        <div class="border-t border-base-300 px-4 py-6 space-y-1">
          <.link
            navigate={~p"/docs"}
            class="flex items-center gap-3 px-3 py-3 rounded-lg text-base font-medium hover:bg-base-200 transition-colors"
          >
            <.icon name="book-open" class="size-5 text-base-content/50" />
            {gettext("Docs")}
          </.link>
          <.link
            navigate={~p"/contact"}
            class="flex items-center gap-3 px-3 py-3 rounded-lg text-base font-medium hover:bg-base-200 transition-colors"
          >
            <.icon name="mail" class="size-5 text-base-content/50" />
            {gettext("Contact")}
          </.link>
        </div>
        <div class="border-t border-base-300 px-4 py-6 space-y-3">
          <%= if @current_scope && @current_scope.user do %>
            <.link navigate={~p"/workspaces"} class="btn btn-primary btn-block">
              {gettext("Dashboard")}
            </.link>
          <% else %>
            <a
              href="#waitlist"
              class="btn btn-primary btn-block"
              phx-click={JS.hide(to: "#mobile-nav", transition: "fade-out")}
            >
              {gettext("Request access")}
            </a>
            <.link navigate={~p"/users/log-in"} class="btn btn-ghost btn-block">
              {gettext("Log in")}
            </.link>
          <% end %>
        </div>
      </nav>

      <main class="flex-1">
        {render_slot(@inner_block)}
      </main>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  @doc """
  Renders a fullscreen settings layout with floating toolbars and sidebar.

  Visually consistent with `Layouts.focus` — floating surface-panel toolbars
  and sidebar, fullscreen background.

  Accepts optional `back_path`, `back_label`, and `sidebar_sections` to customize
  the sidebar. When not provided, defaults to account/workspace navigation.

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

  attr :managed_workspace_slugs, :any,
    default: MapSet.new(),
    doc: "MapSet of workspace slugs where user has WorkspaceMembership"

  attr :current_path, :string, required: true, doc: "current settings path for nav highlighting"

  attr :back_path, :string, default: nil, doc: "custom back link path (defaults to /workspaces)"

  attr :back_label, :string,
    default: nil,
    doc: "custom back link label (defaults to 'Back to app')"

  attr :sidebar_sections, :list,
    default: nil,
    doc: "custom sidebar sections list; when nil, uses default account/workspace nav"

  slot :title, required: true
  slot :subtitle
  slot :inner_block, required: true

  def settings(assigns) do
    assigns =
      assigns
      |> assign_new(:resolved_back_path, fn -> assigns.back_path || ~p"/workspaces" end)
      |> assign_new(:resolved_back_label, fn ->
        assigns.back_label || gettext("Back to app")
      end)
      |> assign_new(:resolved_sections, fn ->
        assigns.sidebar_sections ||
          settings_sections(assigns.workspaces, assigns.managed_workspace_slugs)
      end)

    ~H"""
    <div
      id="settings-layout"
      phx-hook="SettingsSidebar"
      class="h-screen w-screen overflow-hidden relative bg-base-100"
    >
      <%!-- Hidden checkbox for mobile sidebar toggle (must be first child for peer-*) --%>
      <input id="settings-sidebar-check" type="checkbox" class="peer hidden" />

      <%!-- Left floating toolbar (top-left) --%>
      <div class="fixed top-3 left-3 z-[1020] flex items-stretch gap-2">
        <nav class="flex items-center gap-1 px-1 py-1 surface-panel w-60">
          <%!-- Mobile sidebar toggle (hidden on desktop) --%>
          <div class="contents md:hidden">
            <label for="settings-sidebar-check" class="toolbar-btn btn-square cursor-pointer">
              <.icon name="panel-left" class="size-4" />
            </label>
            <div class="w-px h-5 bg-base-300"></div>
          </div>

          <.link navigate="/" class="toolbar-btn gap-1.5">
            <.app_logo class="w-5 h-5" />
            <span class="text-sm font-medium brand-logotype">Storyarn</span>
          </.link>
        </nav>
      </div>

      <%!-- Mobile overlay (closes sidebar on tap) --%>
      <label
        for="settings-sidebar-check"
        class="fixed inset-0 bg-black/30 z-[1005] hidden peer-checked:block peer-checked:md:hidden cursor-pointer"
      />

      <%!-- Settings sidebar (floating panel) --%>
      <div class={[
        "fixed left-3 top-[76px] bottom-3 z-[1010] w-60 flex flex-col surface-panel overflow-hidden",
        "transition-transform duration-200",
        "-translate-x-[calc(100%+0.75rem)] peer-checked:translate-x-0 md:translate-x-0"
      ]}>
        <div class="px-2 pt-2 pb-2 border-b border-base-300">
          <.link
            navigate={@resolved_back_path}
            class="flex items-center gap-2 px-2 py-1.5 rounded-lg text-sm text-base-content/70 hover:bg-base-content/5"
          >
            <.icon name="chevron-left" class="size-4" />
            {@resolved_back_label}
          </.link>
        </div>

        <nav class="flex-1 overflow-y-auto p-2 space-y-5">
          <div :for={section <- @resolved_sections}>
            <h3 class="text-xs font-semibold uppercase text-base-content/50 px-2 mb-2">
              {section.label}
            </h3>
            <ul class="space-y-0.5">
              <li :for={item <- section.items}>
                <.link
                  navigate={item.path}
                  class={[
                    "flex items-center gap-2 px-2 py-1.5 rounded-lg text-sm",
                    @current_path == item.path && "bg-base-content/5 font-medium",
                    @current_path != item.path && "hover:bg-base-content/5"
                  ]}
                >
                  <.icon name={item.icon} class="size-4" />
                  {item.label}
                </.link>
              </li>
            </ul>
          </div>
        </nav>
      </div>

      <%!-- Main content area --%>
      <main class="h-full overflow-y-auto pt-[76px] pb-4 px-4 md:pl-[264px]">
        <div class="max-w-3xl mx-auto">
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

      <.flash_group flash={@flash} />
    </div>
    """
  end

  defp settings_sections(workspaces, managed_workspace_slugs) do
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

    # Only show workspaces where user has actual WorkspaceMembership
    managed_workspaces =
      Enum.filter(workspaces, &MapSet.member?(managed_workspace_slugs, &1.slug))

    workspace_sections =
      Enum.map(managed_workspaces, fn workspace ->
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
  Renders the documentation layout with sidebar navigation.

  Fully independent — does not depend on any domain context.

  ## Examples

      <Layouts.docs
        flash={@flash}
        categories={@categories}
        guides={@guides}
        guide={@guide}
      >
        <div class="prose">{raw(@guide.body)}</div>
      </Layouts.docs>
  """
  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  attr :categories, :list, required: true
  attr :guides, :list, required: true
  attr :guide, :map, default: nil
  attr :expanded_categories, :any, default: nil
  attr :search_query, :string, default: ""
  attr :search_results, :list, default: nil
  attr :prev, :map, default: nil
  attr :next, :map, default: nil
  attr :sidebar_open, :boolean, default: false

  slot :inner_block, required: true

  def docs(assigns) do
    ~H"""
    <div class="h-screen flex flex-col overflow-hidden">
      <%!-- Header --%>
      <header class="navbar px-4 sm:px-6 lg:px-8 border-b border-base-300 bg-base-100 shrink-0">
        <div class="flex-none md:hidden">
          <button phx-click="toggle_sidebar" class="btn btn-square btn-ghost btn-sm">
            <.icon name="menu" class="size-5" />
          </button>
        </div>
        <div class="flex-1 flex items-center gap-1">
          <.link href={~p"/"} class="flex items-center gap-2">
            <.app_logo class="w-6 h-6" />
            <span class="text-lg brand-logotype">Storyarn</span>
          </.link>
          <.link
            navigate={~p"/docs"}
            class="text-xs font-medium text-base-content/50 hover:text-base-content transition-colors self-start mt-1"
          >
            {gettext("docs")}
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
          <% end %>
        </div>
      </header>

      <%!-- Main area --%>
      <div class="flex-1 flex overflow-hidden">
        <%!-- Mobile sidebar overlay --%>
        <div
          :if={@sidebar_open}
          class="fixed inset-0 bg-black/50 z-40 md:hidden"
          phx-click="toggle_sidebar"
        >
        </div>

        <%!-- Sidebar --%>
        <aside class={[
          "w-60 border-r border-base-300 bg-base-100 overflow-y-auto shrink-0",
          "fixed inset-y-0 left-0 z-50 pt-4 transition-transform lg:relative lg:translate-x-0 lg:z-auto lg:pt-6",
          if(@sidebar_open, do: "translate-x-0", else: "-translate-x-full")
        ]}>
          <.docs_sidebar
            categories={@categories}
            guides={@guides}
            guide={@guide}
            expanded_categories={@expanded_categories}
            search_query={@search_query}
            search_results={@search_results}
          />
        </aside>

        <%!-- Content --%>
        <main id="docs-main" class="flex-1 overflow-y-auto" phx-hook="DocsScrollSpy">
          <div class="max-w-4xl mx-auto px-4 sm:px-8 py-8 xl:mr-56">
            <%!-- Guide header --%>
            <div :if={@guide} class="mb-8">
              <p class="text-xs uppercase tracking-wider text-primary font-semibold mb-1">
                {@guide.category_label}
              </p>
              <h1 class="text-3xl font-bold">{@guide.title}</h1>
              <p :if={@guide.description} class="text-base-content/60 mt-2">
                {@guide.description}
              </p>
            </div>

            <%!-- Main content --%>
            {render_slot(@inner_block)}

            <%!-- Prev/Next navigation --%>
            <nav
              :if={@prev || @next}
              class="flex items-center justify-between mt-12 pt-8 border-t border-base-300"
            >
              <div>
                <.link
                  :if={@prev}
                  navigate={~p"/docs/#{@prev.category}/#{@prev.slug}"}
                  class="group flex flex-col items-start"
                >
                  <span class="text-xs text-base-content/40 group-hover:text-base-content/60">
                    <.icon name="arrow-left" class="size-3 inline" />
                    {gettext("Previous")}
                  </span>
                  <span class="text-sm font-medium text-primary">{@prev.title}</span>
                </.link>
              </div>
              <div>
                <.link
                  :if={@next}
                  navigate={~p"/docs/#{@next.category}/#{@next.slug}"}
                  class="group flex flex-col items-end"
                >
                  <span class="text-xs text-base-content/40 group-hover:text-base-content/60">
                    {gettext("Next")}
                    <.icon name="arrow-right" class="size-3 inline" />
                  </span>
                  <span class="text-sm font-medium text-primary">{@next.title}</span>
                </.link>
              </div>
            </nav>
          </div>

          <%!-- Table of contents (right rail) --%>
          <aside
            :if={@guide && @guide.toc != []}
            id="docs-toc"
            class="hidden xl:block fixed top-16 right-0 w-56 py-8 pr-4 pl-2 overflow-y-auto"
            style="max-height: calc(100vh - 4rem)"
          >
            <p class="text-xs font-semibold uppercase tracking-wider text-base-content/50 mb-3">
              {gettext("On this page")}
            </p>
            <nav class="border-l border-base-300">
              <a
                :for={entry <- @guide.toc}
                href={"##{entry.id}"}
                data-toc-id={entry.id}
                class={[
                  "docs-toc-link block text-sm leading-relaxed transition-colors hover:text-primary",
                  if(entry.level == 3, do: "pl-5", else: "pl-3"),
                  "text-base-content/50"
                ]}
              >
                {entry.text}
              </a>
            </nav>
          </aside>
        </main>
      </div>

      <.flash_group flash={@flash} />
    </div>
    """
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
