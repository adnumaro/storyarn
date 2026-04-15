defmodule StoryarnWeb.Components.ProjectShell do
  @moduledoc """
  Layout wrapper for all project-scoped pages (sheets, flows, scenes,
  screenplays, localization).

  Renders the persistent chrome:

  - Both `LeftToolbar` and `RightToolbar` Vue components inline as
    fixed top pills.
  - A per-tool **sidebar LV** (via `sidebar_module` + `sidebar_session`
    attrs) — e.g. `SheetsSidebarLive`, `LocalizationSidebarLive`.
  - `PresenceLive` — invisible sticky LV that tracks project-level
    presence and broadcasts `{:online_users, list}` on the shell topic.
    Page LVs subscribe and pass the list back in via `online_users`.

  Additionally exposes two slots, each rendered next to the respective
  toolbar in the same flex container (natural gap-2 spacing):

  - `:top_bar_extras_left` — between `LeftToolbar` and the tool
    switcher, if the tool needs extra chrome there.
  - `:top_bar_extras_right` — between `RightToolbar` and the screen
    edge (the slot is rendered FIRST so the user pill stays at the
    far right). Typical fill: a `live_render` of a tool-specific
    sticky LV (`LocalizationToolbarLive` etc.).

  Usage from a page LV's render:

      <ProjectShell.project_shell
        socket={@socket}
        project={@project}
        workspace={@workspace}
        current_scope={@current_scope}
        current_user={@current_user}
        urls={@urls}
        active_tool={:localization}
        is_super_admin={@is_super_admin}
        online_users={@online_users}
        sidebar_module={StoryarnWeb.LocalizationSidebarLive}
        sidebar_session={%{...}}
      >
        <:top_bar_extras_right :if={@can_edit && @target_languages != []}>
          {live_render(@socket, StoryarnWeb.LocalizationToolbarLive,
            id: "localization-toolbar-\#{@project.id}",
            sticky: true,
            session: %{...}
          )}
        </:top_bar_extras_right>

        <!-- main content -->
      </ProjectShell.project_shell>
  """

  use StoryarnWeb, :html

  attr :socket, :any, required: true
  attr :project, :map, required: true
  attr :workspace, :map, required: true
  attr :current_scope, :map, required: true
  attr :current_user, :map, required: true
  attr :urls, :map, required: true
  attr :active_tool, :atom, default: :sheets
  attr :is_super_admin, :boolean, default: false

  attr :online_users, :list,
    default: [],
    doc:
      "current presence list. Kept in sync by `PresenceLive` broadcasting `{:online_users, list}` on the shell topic."

  attr :sidebar_module, :atom,
    required: true,
    doc: "per-tool sidebar LiveView module (e.g. `SheetsSidebarLive`)"

  attr :sidebar_session, :map,
    default: %{},
    doc: "session map passed to the sidebar LV on mount"

  slot :top_bar_extras_left,
    doc: "page-provided content rendered next to LeftToolbar"

  slot :top_bar_extras_right,
    doc:
      "page-provided content rendered next to RightToolbar (typically a `live_render` of a tool-specific sticky LV)"

  slot :inner_block, required: true

  def project_shell(assigns) do
    ~H"""
    <div class="h-screen w-screen overflow-hidden relative bg-background">
      <%!-- Invisible sticky LV that owns project-level presence tracking. --%>
      {live_render(@socket, StoryarnWeb.PresenceLive,
        id: "presence-#{@project.id}",
        sticky: true,
        session: %{
          "project_id" => @project.id,
          "current_scope" => @current_scope
        }
      )}

      <%!-- Top-left chrome: LeftToolbar + optional tool-specific extras --%>
      <div class="fixed top-3 left-3 z-41 flex items-stretch gap-2">
        <div id="shell-left-toolbar-wrapper" phx-update="ignore">
          <.vue
            v-component="layout/LeftToolbar"
            v-socket={@socket}
            id="shell-left-toolbar"
            active-tool={to_string(@active_tool)}
            has-tree={true}
            tree-panel-open={true}
            project-name={@project.name}
            workspace-name={@workspace.name}
            show-tool-switcher={true}
            is-super-admin={@is_super_admin}
            urls={@urls}
          />
        </div>

        {render_slot(@top_bar_extras_left)}
      </div>

      <%!--
        Top-right chrome: optional tool-specific extras + RightToolbar.
        Slot rendered FIRST so the user pill stays at the screen edge.
        RightToolbar's wrapper uses `phx-update="ignore"` + a dynamic id
        keyed on `online_users_key` so Vue remounts when presence changes
        (avoids the LiveVue mid-mount race on diff updates).
      --%>
      <div class="fixed top-3 right-3 z-41 flex items-stretch gap-2">
        {render_slot(@top_bar_extras_right)}

        <div
          id={"shell-right-toolbar-wrapper-#{online_users_key(@online_users)}"}
          phx-update="ignore"
        >
          <.vue
            v-component="layout/RightToolbar"
            v-socket={@socket}
            id="shell-right-toolbar"
            current-user={@current_user}
            online-users={@online_users}
            urls={@urls}
          />
        </div>
      </div>

      {live_render(@socket, @sidebar_module,
        id: "sidebar-#{@project.id}",
        sticky: true,
        session: @sidebar_session
      )}

      <main
        id="main-content"
        class={[
          "h-full overflow-y-auto pt-[76px] pb-4 px-4",
          "transition-[padding-left] duration-200",
          "md:[body[data-tree-panel-open='1']_&]:pl-[320px]"
        ]}
      >
        {render_slot(@inner_block)}
      </main>
    </div>
    """
  end

  defp online_users_key(users) do
    users
    |> Enum.map(& &1.user_id)
    |> Enum.sort()
    |> Enum.join("-")
    |> case do
      "" -> "empty"
      key -> key
    end
  end
end
