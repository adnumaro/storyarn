defmodule StoryarnWeb.Components.FocusLayout do
  @moduledoc """
  Focus layout sub-components for the FigJam-inspired full-screen layout.

  Components:
  - `left_toolbar/1` — Floating horizontal pill (top-left): back, tree toggle, project name, tool switcher, trash
  - `right_toolbar/1` — Floating horizontal pill (top-right): presence dots, settings gear, user avatar
  - `tree_panel/1` — ~240px pinnable panel below the left toolbar
  - `tool_switcher_dropdown/1` — Dropdown with all 6 project tools
  """

  use Phoenix.Component
  use StoryarnWeb, :verified_routes
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents

  # ============================================================================
  # Tool definitions
  # ============================================================================

  @tools [
    %{key: :sheets, icon: "file-text", section: "sheets"},
    %{key: :flows, icon: "git-branch", section: "flows"},
    %{key: :scenes, icon: "map", section: "scenes"},
    %{key: :screenplays, icon: "scroll-text", section: "screenplays"},
    %{key: :assets, icon: "image", section: "assets"},
    %{key: :localization, icon: "languages", section: "localization"},
    %{key: :export_import, icon: "package", section: "export-import"}
  ]

  @tool_icons Map.new(@tools, fn t -> {t.key, t.icon} end)

  defp tool_icon(key), do: Map.get(@tool_icons, key, "layout-grid")

  defp tool_label(:sheets), do: dgettext("sheets", "Sheets")
  defp tool_label(:flows), do: dgettext("flows", "Flows")
  defp tool_label(:scenes), do: dgettext("scenes", "Scenes")
  defp tool_label(:screenplays), do: dgettext("screenplays", "Screenplays")
  defp tool_label(:assets), do: dgettext("assets", "Assets")
  defp tool_label(:localization), do: dgettext("localization", "Localization")
  defp tool_label(:export_import), do: gettext("Export & Import")
  defp tool_label(_), do: ""

  # ============================================================================
  # Left Toolbar (horizontal, top-left)
  # ============================================================================

  @doc """
  Renders the left floating horizontal toolbar (top-left pill).

  Contains: back to workspace, tree toggle, project name, tool switcher, trash.
  """
  attr :active_tool, :atom, required: true
  attr :has_tree, :boolean, default: true
  attr :tree_panel_open, :boolean, default: false
  attr :workspace, :map, required: true
  attr :project, :map, required: true

  def left_toolbar(assigns) do
    assigns = assign(assigns, :active_icon, tool_icon(assigns.active_tool))

    ~H"""
    <nav class="flex items-center gap-1 px-2 py-1.5 surface-panel">
      <%!-- Back to workspace --%>
      <.link
        navigate={~p"/workspaces/#{@workspace.slug}"}
        class="btn btn-ghost btn-md btn-square tooltip tooltip-bottom"
        data-tip={gettext("Back to Workspace")}
      >
        <.icon name="chevron-left" class="size-6" />
      </.link>

      <%!-- Tree panel toggle --%>
      <button
        :if={@has_tree}
        type="button"
        phx-click="tree_panel_toggle"
        class={[
          "btn btn-ghost btn-md btn-square tooltip tooltip-bottom",
          @tree_panel_open && "bg-base-300"
        ]}
        data-tip={if @tree_panel_open, do: gettext("Hide panel"), else: gettext("Show panel")}
      >
        <.icon name="panel-left" class="size-6" />
      </button>

      <div class="w-px h-7 bg-base-300"></div>

      <%!-- Tool switcher: icon + label, opens dropdown to switch tools --%>
      <div class="dropdown dropdown-bottom">
        <button
          type="button"
          tabindex="0"
          class="btn btn-ghost btn-md gap-2"
        >
          <.icon name={@active_icon} class="size-5" />
          <span class="hidden xl:inline text-base font-medium">{tool_label(@active_tool)}</span>
          <.icon name="chevron-down" class="size-3.5 opacity-50" />
        </button>
        <.tool_switcher_dropdown
          active_tool={@active_tool}
          workspace={@workspace}
          project={@project}
        />
      </div>
    </nav>
    """
  end

  # ============================================================================
  # Right Toolbar (horizontal, top-right)
  # ============================================================================

  @doc """
  Renders the right floating horizontal toolbar (top-right pill).

  Contains: presence dots, settings gear, user avatar.
  """
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :online_users, :list, default: []
  attr :current_user_id, :integer, required: true
  attr :current_scope, :map, default: nil

  def right_toolbar(assigns) do
    other_users =
      Enum.reject(assigns.online_users, &(&1.user_id == assigns.current_user_id))

    assigns = assign(assigns, :other_users, Enum.take(other_users, 5))

    ~H"""
    <nav class="flex items-center gap-1 px-2 py-1.5 surface-panel">
      <%!-- Project name dropdown --%>
      <div class="dropdown dropdown-end">
        <button tabindex="0" class="btn btn-ghost btn-md gap-2 font-medium max-w-52">
          <.icon name="folder" class="size-5 opacity-60 shrink-0" />
          <span class="hidden xl:inline truncate text-base toolbar-collapsible">{@project.name}</span>
        </button>
        <div
          tabindex="0"
          class="dropdown-content bg-base-200 border border-base-300 rounded-lg shadow-sm w-max max-w-72 z-[60] mt-3"
        >
          <%!-- Project info (non-selectable) --%>
          <div class="px-4 py-3">
            <p class="text-base font-medium truncate">{@project.name}</p>
            <p class="text-sm text-base-content/50 truncate">{@workspace.name}</p>
          </div>
          <div class="border-t border-base-300"></div>
          <%!-- Menu items --%>
          <ul class="menu p-1 text-base">
            <li>
              <.link navigate={
                ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/export-import"
              }>
                <.icon name="package" class="size-5" />
                {gettext("Export & Import")}
              </.link>
            </li>
            <li>
              <.link navigate={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/settings"}>
                <.icon name="settings" class="size-5" />
                {gettext("Project settings")}
              </.link>
            </li>
          </ul>
        </div>
      </div>

      <%!-- Presence dots --%>
      <div :if={@other_users != []} class="flex -space-x-1.5 mx-1.5">
        <div
          :for={user <- @other_users}
          class="size-3.5 rounded-full ring-2 ring-base-200 tooltip tooltip-bottom"
          style={"background-color: #{user.color};"}
          data-tip={user.display_name || user.email}
        >
        </div>
      </div>

      <%!-- User avatar --%>
      <div class="dropdown dropdown-end">
        <button tabindex="0" class="btn btn-ghost btn-md btn-circle">
          <div class="avatar placeholder">
            <div class="bg-neutral text-neutral-content rounded-full size-8 content-center">
              <span class="text-sm">{user_initials(assigns)}</span>
            </div>
          </div>
        </button>
        <div
          tabindex="0"
          class="dropdown-content bg-base-200 border border-base-300 rounded-lg shadow-sm w-max max-w-72 z-[60] mt-3"
        >
          <%!-- User info (non-selectable) --%>
          <div class="px-4 py-3">
            <p class="text-base font-medium truncate">
              {user_display_name(assigns)}
            </p>
            <p class="text-sm text-base-content/50 truncate">
              {user_email(assigns)}
            </p>
          </div>
          <div class="border-t border-base-300"></div>
          <%!-- Menu items --%>
          <ul class="menu p-1 text-base">
            <li>
              <.link navigate={~p"/users/settings"}>
                <.icon name="user" class="size-5" />
                {gettext("Account settings")}
              </.link>
            </li>
            <li>
              <.link navigate={~p"/workspaces"}>
                <.icon name="layout-dashboard" class="size-5" />
                {gettext("All workspaces")}
              </.link>
            </li>
          </ul>
        </div>
      </div>
    </nav>
    """
  end

  # ============================================================================
  # Tool Switcher Dropdown
  # ============================================================================

  attr :active_tool, :atom, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true

  def tool_switcher_dropdown(assigns) do
    assigns = assign(assigns, :tools, @tools)

    ~H"""
    <ul
      tabindex="0"
      class="dropdown-content menu bg-base-200 border border-base-300 rounded-lg shadow-sm w-52 z-[60] mt-3 text-base"
    >
      <li :for={tool <- @tools} :if={tool.key != @active_tool}>
        <.link navigate={tool_path(@workspace, @project, tool.section)}>
          <.icon name={tool.icon} class="size-5" />
          {tool_label(tool.key)}
        </.link>
      </li>
    </ul>
    """
  end

  defp tool_path(ws, proj, "sheets"), do: ~p"/workspaces/#{ws.slug}/projects/#{proj.slug}/sheets"
  defp tool_path(ws, proj, "flows"), do: ~p"/workspaces/#{ws.slug}/projects/#{proj.slug}/flows"
  defp tool_path(ws, proj, "scenes"), do: ~p"/workspaces/#{ws.slug}/projects/#{proj.slug}/scenes"

  defp tool_path(ws, proj, "screenplays"),
    do: ~p"/workspaces/#{ws.slug}/projects/#{proj.slug}/screenplays"

  defp tool_path(ws, proj, "assets"),
    do: ~p"/workspaces/#{ws.slug}/projects/#{proj.slug}/assets"

  defp tool_path(ws, proj, "localization"),
    do: ~p"/workspaces/#{ws.slug}/projects/#{proj.slug}/localization"

  defp tool_path(ws, proj, "export-import"),
    do: ~p"/workspaces/#{ws.slug}/projects/#{proj.slug}/export-import"

  # ============================================================================
  # Tree Panel
  # ============================================================================

  @doc """
  Renders the pinnable tree panel below the left toolbar on the left side.

  Shows tool name header, search slot, tree content slot, and pin/close footer.
  """
  attr :active_tool, :atom, required: true
  attr :tree_panel_open, :boolean, default: false
  attr :tree_panel_pinned, :boolean, default: true
  attr :can_edit, :boolean, default: false
  attr :workspace, :map, required: true
  attr :project, :map, required: true

  slot :tree_content, required: true

  def tree_panel(assigns) do
    ~H"""
    <div
      id="tree-panel"
      phx-hook="TreePanel"
      data-pinned={to_string(@tree_panel_pinned)}
      class={[
        "fixed left-3 top-[76px] bottom-3 z-[1010] w-60 flex flex-col surface-panel overflow-hidden",
        "transition-[transform,opacity] duration-200 ease-in-out",
        if(@tree_panel_open,
          do: "translate-x-0 opacity-100",
          else: "-translate-x-[calc(100%+12px)] opacity-0 pointer-events-none"
        )
      ]}
    >
      <%!-- Tree content (scrollable) --%>
      <div class="flex-1 overflow-y-auto p-2">
        {render_slot(@tree_content)}
      </div>

      <%!-- Footer: Trash / Pin / Close --%>
      <div class="flex items-center gap-1 px-2 py-1.5 border-t border-base-300">
        <.link
          navigate={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/trash"}
          class="btn btn-ghost btn-xs gap-1"
          title={gettext("Trash")}
        >
          <.icon name="trash-2" class="size-3" />
          <span class="text-xs">{gettext("Trash")}</span>
        </.link>

        <div class="flex-1"></div>

        <button
          type="button"
          phx-click="tree_panel_pin"
          class={[
            "btn btn-ghost btn-xs gap-1",
            @tree_panel_pinned && "text-primary"
          ]}
          title={if @tree_panel_pinned, do: gettext("Unpin panel"), else: gettext("Pin panel")}
        >
          <.icon name="pin" class="size-3" />
          <span class="text-xs">
            {if @tree_panel_pinned, do: gettext("Pinned"), else: gettext("Pin")}
          </span>
        </button>
        <button
          type="button"
          phx-click="tree_panel_toggle"
          class="btn btn-ghost btn-xs btn-square"
          title={gettext("Close panel")}
        >
          <.icon name="x" class="size-3" />
        </button>
      </div>
    </div>
    """
  end

  defp user_initials(%{current_scope: %{user: %{email: email}}}) when is_binary(email) do
    email
    |> String.split("@")
    |> List.first()
    |> String.slice(0, 2)
    |> String.upcase()
  end

  defp user_initials(_), do: "?"

  defp user_display_name(%{current_scope: %{user: %{display_name: name}}})
       when is_binary(name) and name != "",
       do: name

  defp user_display_name(%{current_scope: %{user: %{email: email}}}) when is_binary(email) do
    email |> String.split("@") |> List.first()
  end

  defp user_display_name(_), do: ""

  defp user_email(%{current_scope: %{user: %{email: email}}}) when is_binary(email), do: email
  defp user_email(_), do: ""
end
