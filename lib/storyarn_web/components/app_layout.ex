defmodule StoryarnWeb.Components.AppLayout do
  @moduledoc """
  App layout — LiveVue + shadcn-vue.

  The primary application layout used by all authenticated project pages.
  The HEEx acts as orchestrator — each toolbar/panel is a Vue component
  receiving only the props it needs.
  """

  use StoryarnWeb, :html
  use Gettext, backend: Storyarn.Gettext

  # ============================================================================
  # Tool path helpers (reused from v1, needed to build URL maps)
  # ============================================================================

  @tools [
    %{key: :dashboard, section: "dashboard"},
    %{key: :sheets, section: "sheets"},
    %{key: :flows, section: "flows"},
    %{key: :scenes, section: "scenes"},
    %{key: :assets, section: "assets"},
    %{key: :localization, section: "localization"}
  ]

  defp tool_path(ws, proj, "dashboard"), do: ~p"/workspaces/#{ws.slug}/projects/#{proj.slug}"
  defp tool_path(ws, proj, "sheets"), do: ~p"/workspaces/#{ws.slug}/projects/#{proj.slug}/sheets"
  defp tool_path(ws, proj, "flows"), do: ~p"/workspaces/#{ws.slug}/projects/#{proj.slug}/flows"
  defp tool_path(ws, proj, "scenes"), do: ~p"/workspaces/#{ws.slug}/projects/#{proj.slug}/scenes"

  defp tool_path(ws, proj, "assets"), do: ~p"/workspaces/#{ws.slug}/projects/#{proj.slug}/assets"

  defp tool_path(ws, proj, "localization"), do: ~p"/workspaces/#{ws.slug}/projects/#{proj.slug}/localization"

  @doc """
  Builds the URL map that Vue components need for navigation.

  Since Vue can't use `~p` sigils, we pre-build all URLs server-side.
  """
  def build_urls(workspace, project) do
    tool_urls =
      Map.new(@tools, fn t ->
        {Atom.to_string(t.key), tool_path(workspace, project, t.section)}
      end)

    %{
      workspace: ~p"/workspaces/#{workspace.slug}",
      projectSettings: ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/settings",
      trash: ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/trash",
      accountSettings: ~p"/users/settings",
      workspaces: ~p"/workspaces",
      logout: ~p"/users/log-out",
      tools: tool_urls
    }
  end

  # ============================================================================
  # App Layout
  # ============================================================================

  @doc """
  Renders the app layout — full-screen content with Vue floating toolbars
  and pinnable tree panel.

  Used as `Layouts.app` for all authenticated project pages.
  """
  attr :flash, :map, required: true

  attr :current_scope, :map,
    default: nil,
    doc: "the current scope"

  attr :project, :map, default: nil, doc: "the current project (nil for workspace-level pages)"
  attr :workspace, :map, default: nil, doc: "the workspace the project belongs to"

  attr :active_tool, :atom,
    default: :sheets,
    doc: "active tool (:sheets, :flows, :screenplays, :scenes, :assets, :localization)"

  attr :has_tree, :boolean, default: true, doc: "whether this page has a main sidebar"
  attr :main_sidebar_open, :boolean, default: false, doc: "whether the main sidebar is open"
  attr :main_sidebar_pinned, :boolean, default: false, doc: "whether the main sidebar is pinned"
  attr :show_pin, :boolean, default: true, doc: "whether to show pin/close in main sidebar footer"
  attr :can_edit, :boolean, default: false, doc: "whether the user can edit content"
  attr :online_users, :list, default: [], doc: "list of online user presence maps"

  attr :restoration_banner, :map,
    default: nil,
    doc: "when set, shows a restoration-in-progress banner"

  attr :on_dashboard, :boolean,
    default: false,
    doc: "whether the current page is the tool dashboard"

  attr :show_tool_switcher, :boolean,
    default: true,
    doc: "whether to show the tool switcher dropdown"

  attr :canvas_mode, :boolean,
    default: false,
    doc: "when true, main area has no padding/scroll (canvas views)"

  attr :socket, :any, required: true, doc: "the LiveView socket (needed for LiveVue)"

  attr :sidebar_props, :map,
    default: %{},
    doc: "props passed to the tool-specific component inside MainSidebar"

  slot :tree_content, doc: "main sidebar content (tree component)"
  slot :top_bar_extra, doc: "extra content rendered next to the left toolbar (same row)"
  slot :top_bar_extra_right, doc: "extra content rendered next to the right toolbar (same row)"
  slot :content_header, doc: "optional header above main content"
  slot :inner_block, required: true

  def app(assigns) do
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

    current_user =
      case assigns.current_scope do
        %{user: user} ->
          %{
            id: user.id,
            email: user.email,
            displayName: user.display_name,
            isSuperAdmin: is_super_admin
          }

        _ ->
          %{id: nil, email: "", displayName: "", isSuperAdmin: false}
      end

    urls =
      if assigns.workspace && assigns.project,
        do: build_urls(assigns.workspace, assigns.project),
        else: %{}

    # Dashboard URL for main sidebar header
    dashboard_url =
      if assigns.workspace && assigns.project,
        do: tool_path(assigns.workspace, assigns.project, to_string(assigns.active_tool))

    assigns =
      assigns
      |> assign(:current_user_id, current_user_id)
      |> assign(:is_super_admin, is_super_admin)
      |> assign(:current_user, current_user)
      |> assign(:urls, urls)
      |> assign(:dashboard_url, dashboard_url)

    ~H"""
    <div id="layout-wrapper" class="h-screen w-screen overflow-hidden relative bg-background">
      <%!-- Restoration Banner --%>
      <div
        :if={@restoration_banner}
        class="fixed top-0 left-0 right-0 z-42 flex justify-center pointer-events-none"
      >
        <div class="bg-destructive text-destructive-foreground px-4 py-2 rounded-b-lg shadow-lg flex items-center gap-2 text-sm pointer-events-auto">
          <.icon name="loader" class="size-4 animate-spin" />
          <span>
            {dgettext(
              "projects",
              "Project is being restored by %{user}. Editing is temporarily disabled.",
              user: @restoration_banner.user_email
            )}
          </span>
        </div>
      </div>

      <%!-- Left floating toolbar row (top-left) --%>
      <div class="fixed top-3 left-3 z-41 flex items-stretch gap-2">
        <.vue
          v-component="layout/LeftToolbar"
          v-socket={@socket}
          id="left-toolbar"
          active-tool={to_string(@active_tool)}
          has-tree={@has_tree}
          main-sidebar-open={@main_sidebar_open}
          project-name={@project && @project.name}
          workspace-name={@workspace && @workspace.name}
          show-tool-switcher={@show_tool_switcher}
          is-super-admin={@is_super_admin}
          urls={@urls}
        />
        {render_slot(@top_bar_extra)}
      </div>

      <%!-- Right floating toolbar row (top-right) --%>
      <div :if={@current_user_id} class="fixed top-3 right-3 z-41 flex items-stretch gap-2">
        {render_slot(@top_bar_extra_right)}
        <.vue
          v-component="layout/RightToolbar"
          v-socket={@socket}
          id="right-toolbar"
          current-user={@current_user}
          online-users={@online_users}
          urls={@urls}
        />
      </div>

      <%!-- Mobile overlay (closes main sidebar on tap) --%>
      <div
        :if={@has_tree && @tree_content != [] && @main_sidebar_open}
        class="fixed inset-0 bg-black/30 z-30 md:hidden cursor-pointer"
        phx-click="main_sidebar_toggle"
      />

      <%!-- Main sidebar --%>
      <.vue
        :if={@has_tree}
        v-component="layout/MainSidebar"
        v-socket={@socket}
        id="main-sidebar"
        main-sidebar-open={@main_sidebar_open}
        main-sidebar-pinned={@main_sidebar_pinned}
        show-pin={@show_pin}
        active-tool={to_string(@active_tool)}
        dashboard-url={@dashboard_url}
        on-dashboard={@on_dashboard}
        sidebar-props={@sidebar_props}
      />

      <%!-- Main content area --%>
      <main
        id="main-content"
        class={[
          "h-full",
          if(@canvas_mode,
            do: "overflow-hidden",
            else: [
              "overflow-y-auto pt-[76px] pb-4 px-4 transition-[padding-left] duration-200",
              @has_tree && @main_sidebar_open && "md:pl-[320px]"
            ]
          )
        ]}
      >
        <div :if={@content_header != []} class="mb-4">
          {render_slot(@content_header)}
        </div>
        {render_slot(@inner_block)}
      </main>

      <div id="flash-group" aria-live="polite">
        <.flash kind={:info} flash={@flash} />
        <.flash kind={:error} flash={@flash} />

        <.flash
          id="client-error"
          kind={:error}
          title={gettext("We can't find the internet")}
          phx-disconnected={
            show(".phx-client-error #client-error") |> Phoenix.LiveView.JS.remove_attribute("hidden")
          }
          phx-connected={hide("#client-error") |> Phoenix.LiveView.JS.set_attribute({"hidden", ""})}
          hidden
        >
          {gettext("Attempting to reconnect")}
          <.icon name="refresh-cw" class="ml-1 size-3 motion-safe:animate-spin" />
        </.flash>

        <.flash
          id="server-error"
          kind={:error}
          title={gettext("Something went wrong!")}
          phx-disconnected={
            show(".phx-server-error #server-error") |> Phoenix.LiveView.JS.remove_attribute("hidden")
          }
          phx-connected={hide("#server-error") |> Phoenix.LiveView.JS.set_attribute({"hidden", ""})}
          hidden
        >
          {gettext("Attempting to reconnect")}
          <.icon name="refresh-cw" class="ml-1 size-3 motion-safe:animate-spin" />
        </.flash>
      </div>
    </div>
    """
  end
end
