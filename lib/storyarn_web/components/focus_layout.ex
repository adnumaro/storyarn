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
  use Gettext, backend: Storyarn.Gettext

  import StoryarnWeb.Components.CoreComponents
  import StoryarnWeb.Components.MemberComponents, only: [user_avatar: 1]
  import StoryarnWeb.Components.TreeComponents, only: [tree_link: 1]

  alias StoryarnWeb.Components.Sidebar.DraftList

  # ============================================================================
  # Tool definitions
  # ============================================================================

  @tools [
    %{key: :dashboard, icon: "layout-dashboard", section: "dashboard"},
    %{key: :sheets, icon: "file-text", section: "sheets"},
    %{key: :flows, icon: "git-branch", section: "flows"},
    %{key: :scenes, icon: "map", section: "scenes"},
    %{key: :screenplays, icon: "scroll-text", section: "screenplays"},
    %{key: :assets, icon: "image", section: "assets"},
    %{key: :localization, icon: "languages", section: "localization"}
  ]

  @tool_icons Map.new(@tools, fn t -> {t.key, t.icon} end)

  defp tool_icon(key), do: Map.get(@tool_icons, key, "layout-grid")

  defp tool_label(:dashboard), do: dgettext("projects", "Dashboard")
  defp tool_label(:sheets), do: dgettext("sheets", "Sheets")
  defp tool_label(:flows), do: dgettext("flows", "Flows")
  defp tool_label(:scenes), do: dgettext("scenes", "Scenes")
  defp tool_label(:screenplays), do: dgettext("screenplays", "Screenplays")
  defp tool_label(:assets), do: dgettext("assets", "Assets")
  defp tool_label(:localization), do: dgettext("localization", "Localization")
  defp tool_label(_), do: ""

  # ============================================================================
  # Left Toolbar (horizontal, top-left)
  # ============================================================================

  @doc """
  Renders the left floating horizontal toolbar (top-left pill).

  Contains: tree toggle, tool switcher.
  """
  attr :active_tool, :atom, required: true
  attr :has_tree, :boolean, default: true
  attr :tree_panel_open, :boolean, default: false
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :is_super_admin, :boolean, default: false
  attr :show_tool_switcher, :boolean, default: true

  def left_toolbar(assigns) do
    assigns = assign(assigns, :active_icon, tool_icon(assigns.active_tool))

    ~H"""
    <nav class="flex items-center gap-1 px-1 py-1 surface-panel">
      <%!-- Tree panel toggle --%>
      <button
        :if={@has_tree}
        type="button"
        phx-click="tree_panel_toggle"
        class={[
          "toolbar-btn btn-square tooltip tooltip-bottom tooltip-bottom-start",
          @tree_panel_open && "bg-base-300"
        ]}
        data-tip={if @tree_panel_open, do: gettext("Hide panel"), else: gettext("Show panel")}
      >
        <.icon name="panel-left" class="size-4" />
      </button>

      <div :if={@has_tree} class="w-px h-5 bg-base-300"></div>

      <%!-- Project name dropdown --%>
      <div class="dropdown dropdown-bottom">
        <button tabindex="0" class="toolbar-btn gap-1.5 font-medium max-w-52">
          <.icon name="folder" class="size-4 opacity-60 shrink-0" />
          <span class="hidden xl:inline truncate text-sm toolbar-collapsible">{@project.name}</span>
          <.icon name="chevron-down" class="size-3 opacity-50" />
        </button>
        <div
          tabindex="0"
          class="dropdown-content bg-base-200 border border-base-300 rounded-lg shadow-sm w-max max-w-72 z-[60] mt-3"
        >
          <div class="px-4 py-3">
            <p class="text-sm font-medium truncate">{@project.name}</p>
            <.link
              navigate={~p"/workspaces/#{@workspace.slug}"}
              class="text-xs text-base-content/50 truncate hover:text-base-content/70"
            >
              {@workspace.name}
            </.link>
          </div>
          <div class="border-t border-base-300"></div>
          <ul class="menu p-1 text-sm">
            <li>
              <.link navigate={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/settings"}>
                <.icon name="settings" class="size-5" />
                {gettext("Project settings")}
              </.link>
            </li>
            <li class="border-t border-base-300 mt-1 pt-1">
              <.link navigate={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/trash"}>
                <.icon name="trash-2" class="size-5" />
                {gettext("Trash")}
              </.link>
            </li>
          </ul>
        </div>
      </div>

      <%!-- Tool switcher: icon + label, opens dropdown to switch tools --%>
      <div :if={@show_tool_switcher} class="dropdown dropdown-bottom">
        <button
          type="button"
          tabindex="0"
          class="toolbar-btn gap-1.5"
        >
          <.icon name={@active_icon} class="size-4" />
          <span class="hidden xl:inline text-sm font-medium">{tool_label(@active_tool)}</span>
          <.icon name="chevron-down" class="size-3 opacity-50" />
        </button>
        <.tool_switcher_dropdown
          active_tool={@active_tool}
          workspace={@workspace}
          project={@project}
          is_super_admin={@is_super_admin}
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
    <nav class="flex items-center gap-1 px-1 py-1 surface-panel">
      <%!-- Online users --%>
      <div :if={@other_users != []} class="flex -space-x-1 mx-1.5">
        <div
          :for={user <- @other_users}
          class="tooltip tooltip-bottom"
          data-tip={user.display_name || user.email}
        >
          <.user_avatar
            user={%{display_name: user.display_name, email: user.email}}
            size="xs"
            class="ring-2 ring-base-200"
          />
        </div>
      </div>

      <%!-- User avatar --%>
      <div class="dropdown dropdown-end">
        <button tabindex="0" class="toolbar-btn btn-circle">
          <.user_avatar user={@current_scope.user} size="sm" />
        </button>
        <div
          tabindex="0"
          class="dropdown-content bg-base-200 border border-base-300 rounded-lg shadow-sm w-max max-w-72 z-[60] mt-3"
        >
          <%!-- User info (non-selectable) --%>
          <div class="px-4 py-3">
            <p class="text-sm font-medium truncate">
              {user_display_name(assigns)}
            </p>
            <p class="text-xs text-base-content/50 truncate">
              {user_email(assigns)}
            </p>
          </div>
          <div class="border-t border-base-300"></div>
          <%!-- Menu items --%>
          <ul class="menu p-1 text-sm">
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
  # Entity Title Pill (shared by flow and scene headers)
  # ============================================================================

  @doc """
  Renders the entity name + shortcut pill in the top toolbar.

  Both the name and shortcut can be made editable (for flows) or read-only (for scenes).
  Extra content (badges, popovers) can be placed via the `:extra` slot.
  Breadcrumbs or other prefix content can go in the `:before` slot.
  """
  attr :name, :string, required: true
  attr :shortcut, :string, default: nil
  attr :can_edit, :boolean, default: false
  attr :name_id, :string, default: nil
  attr :name_placeholder, :string, default: "Untitled"
  attr :name_data, :string, default: nil
  attr :shortcut_id, :string, default: nil
  attr :shortcut_placeholder, :string, default: "add-shortcut"

  slot :before
  slot :extra

  def entity_title_pill(assigns) do
    ~H"""
    <div class="hidden lg:flex items-center gap-2 surface-panel px-3">
      {render_slot(@before)}
      <div class="flex items-baseline gap-1.5">
        <%!-- Name --%>
        <h1
          :if={@can_edit && @name_id}
          id={@name_id}
          class="text-sm font-medium outline-none rounded px-1 -mx-1 empty:before:content-[attr(data-placeholder)] empty:before:text-base-content/30"
          contenteditable="true"
          phx-hook="EditableTitle"
          phx-update="ignore"
          data-placeholder={@name_placeholder}
          data-name={@name_data || @name}
        >
          {@name}
        </h1>
        <h1 :if={!(@can_edit && @name_id)} class="text-sm font-medium">{@name}</h1>

        <%!-- Shortcut: static badge --%>
        <span
          :if={@shortcut && !(@can_edit && @shortcut_id)}
          class="hidden xl:inline badge badge-ghost font-mono text-xs badge-xs"
        >
          #{@shortcut}
        </span>

        <%!-- Shortcut: editable badge (flow) --%>
        <span
          :if={@can_edit && @shortcut_id}
          class="hidden xl:inline badge badge-ghost font-mono text-xs badge-xs gap-0 px-1.5"
        >
          <span class="select-none">#</span><span
            id={@shortcut_id}
            class="outline-none"
            contenteditable="true"
            phx-hook="EditableShortcut"
            phx-update="ignore"
            data-placeholder={@shortcut_placeholder}
            data-shortcut={@shortcut || ""}
          >{@shortcut}</span>
        </span>
      </div>
      {render_slot(@extra)}
    </div>
    """
  end

  # ============================================================================
  # Tool Switcher Dropdown
  # ============================================================================

  attr :active_tool, :atom, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :is_super_admin, :boolean, default: false

  def tool_switcher_dropdown(assigns) do
    tools =
      if assigns.is_super_admin do
        @tools
      else
        Enum.reject(@tools, &(&1.key == :screenplays))
      end

    assigns = assign(assigns, :tools, tools)

    ~H"""
    <ul
      tabindex="0"
      class="dropdown-content menu bg-base-200 border border-base-300 rounded-lg shadow-sm w-52 z-[60] mt-3 text-sm"
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

  defp tool_path(ws, proj, "dashboard"), do: ~p"/workspaces/#{ws.slug}/projects/#{proj.slug}"
  defp tool_path(ws, proj, "sheets"), do: ~p"/workspaces/#{ws.slug}/projects/#{proj.slug}/sheets"
  defp tool_path(ws, proj, "flows"), do: ~p"/workspaces/#{ws.slug}/projects/#{proj.slug}/flows"
  defp tool_path(ws, proj, "scenes"), do: ~p"/workspaces/#{ws.slug}/projects/#{proj.slug}/scenes"

  defp tool_path(ws, proj, "screenplays"),
    do: ~p"/workspaces/#{ws.slug}/projects/#{proj.slug}/screenplays"

  defp tool_path(ws, proj, "assets"),
    do: ~p"/workspaces/#{ws.slug}/projects/#{proj.slug}/assets"

  defp tool_path(ws, proj, "localization"),
    do: ~p"/workspaces/#{ws.slug}/projects/#{proj.slug}/localization"

  # ============================================================================
  # Tree Panel
  # ============================================================================

  @doc """
  Renders the pinnable tree panel below the left toolbar on the left side.

  Shows tool name header, search slot, tree content slot, and pin/close footer.
  """
  attr :active_tool, :atom, required: true
  attr :on_dashboard, :boolean, default: false
  attr :tree_panel_open, :boolean, default: false
  attr :tree_panel_pinned, :boolean, default: true
  attr :show_pin, :boolean, default: true
  attr :can_edit, :boolean, default: false
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :my_drafts, :list, default: []
  attr :renaming_draft, :map, default: nil

  slot :tree_content, required: true

  def tree_panel(assigns) do
    ~H"""
    <div
      id="tree-panel"
      phx-hook="TreePanel"
      data-tool={to_string(@active_tool)}
      data-pinned={to_string(@tree_panel_pinned)}
      data-open={to_string(@tree_panel_open)}
      class={[
        "fixed left-3 top-[76px] bottom-3 z-[1010] w-64 flex flex-col surface-panel overflow-hidden",
        "max-md:transition-transform max-md:duration-200",
        if(@tree_panel_open,
          do: "max-md:translate-x-0",
          else: "max-md:-translate-x-[calc(100%+0.75rem)] md:opacity-0 md:pointer-events-none"
        )
      ]}
    >
      <%!-- Navigation header --%>
      <div class="px-2 pt-2 pb-2 border-b border-base-300 space-y-1">
        <.tree_link
          label={tool_label(@active_tool) <> " " <> gettext("dashboard")}
          href={tool_path(@workspace, @project, to_string(@active_tool))}
          icon="layout-dashboard"
          active={@on_dashboard}
        />
      </div>

      <%!-- Tree content (scrollable) --%>
      <div class="flex-1 overflow-y-auto p-2">
        {render_slot(@tree_content)}
        <DraftList.drafts_section
          :if={@my_drafts != []}
          my_drafts={@my_drafts}
          workspace={@workspace}
          project={@project}
          renaming_draft={@renaming_draft}
        />
      </div>

      <%!-- Footer: Pin / Close (hidden on mobile) --%>
      <div class="hidden md:flex items-center justify-end gap-1 px-2 py-1.5 border-t border-base-300">
        <button
          :if={@show_pin}
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
          :if={@show_pin}
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
