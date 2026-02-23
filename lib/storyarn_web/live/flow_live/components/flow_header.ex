defmodule StoryarnWeb.FlowLive.Components.FlowHeader do
  @moduledoc false

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext
  use StoryarnWeb, :verified_routes

  import StoryarnWeb.Components.CoreComponents
  import StoryarnWeb.Components.SaveIndicator

  import StoryarnWeb.FlowLive.Components.NodeTypeHelpers,
    only: [node_type_label: 1, node_type_icon: 1]

  alias StoryarnWeb.FlowLive.Helpers.NavigationHistory

  @doc "Actions toolbar (play, debug, add node) — for top_bar_extra_right slot."
  attr :flow, :map, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :can_edit, :boolean, required: true
  attr :debug_panel_open, :boolean, default: false
  attr :node_types, :list, default: []

  def flow_actions(assigns) do
    ~H"""
    <div class="flex items-center gap-1 px-1.5 py-1 bg-base-200/95 backdrop-blur border border-base-300 rounded-xl shadow-lg">
      <.link
        navigate={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/flows/#{@flow.id}/play"}
        class="btn btn-ghost btn-sm gap-1.5"
      >
        <.icon name="play" class="size-4" />
        <span class="hidden xl:inline">{dgettext("flows", "Play")}</span>
      </.link>
      <button
        type="button"
        class={[
          "btn btn-sm gap-1.5",
          if(@debug_panel_open, do: "btn-accent", else: "btn-ghost")
        ]}
        phx-click={if(@debug_panel_open, do: "debug_stop", else: "debug_start")}
      >
        <.icon name="bug" class="size-4" />
        <span class="hidden xl:inline">
          {if @debug_panel_open,
            do: dgettext("flows", "Stop"),
            else: dgettext("flows", "Debug")}
        </span>
      </button>
      <div :if={@can_edit} class="dropdown dropdown-end">
        <button type="button" tabindex="0" class="btn btn-primary btn-sm gap-1.5">
          <.icon name="plus" class="size-4" />
          <span class="hidden xl:inline">{dgettext("flows", "Add Node")}</span>
        </button>
        <ul
          tabindex="0"
          class="dropdown-content menu menu-xs bg-base-100 rounded-box shadow-lg border border-base-300 w-44 z-50 mt-2"
        >
          <li :for={type <- @node_types}>
            <button type="button" phx-click="add_node" phx-value-type={type}>
              <.node_type_icon type={type} />
              {node_type_label(type)}
            </button>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  @doc "Flow info bar (nav history + title + scene map + save indicator) — overlays the canvas."
  attr :flow, :map, required: true
  attr :can_edit, :boolean, required: true
  attr :save_status, :atom, default: :idle
  attr :nav_history, :map, default: nil
  attr :scene_map_name, :string, default: nil
  attr :scene_map_inherited, :boolean, default: false
  attr :available_maps, :list, default: []

  def flow_info_bar(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <%!-- Nav history --%>
      <% back_entry = @nav_history && NavigationHistory.peek_back(@nav_history) %>
      <% forward_entry = @nav_history && NavigationHistory.peek_forward(@nav_history) %>
      <div
        :if={back_entry || forward_entry}
        class="flex items-center gap-0.5 bg-base-200/95 backdrop-blur rounded-xl shadow-lg border border-base-300 px-1"
      >
        <button
          :if={back_entry}
          type="button"
          class="btn btn-ghost btn-sm gap-1 text-base-content/60 max-w-[140px]"
          phx-click="nav_back"
          title={dgettext("flows", "Alt+Left")}
        >
          <.icon name="arrow-left" class="size-3.5 shrink-0" />
          <span class="truncate text-xs">{back_entry.flow_name}</span>
        </button>
        <button
          :if={forward_entry}
          type="button"
          class="btn btn-ghost btn-sm gap-1 text-base-content/60 max-w-[140px]"
          phx-click="nav_forward"
          title={dgettext("flows", "Alt+Right")}
        >
          <span class="truncate text-xs">{forward_entry.flow_name}</span>
          <.icon name="arrow-right" class="size-3.5 shrink-0" />
        </button>
      </div>

      <%!-- Flow title pill --%>
      <div class="hidden lg:flex items-center gap-2 bg-base-200/95 backdrop-blur rounded-xl shadow-lg border border-base-300 px-3 py-1.5">
        <div>
          <h1
            :if={@can_edit}
            id="flow-title"
            class="text-sm font-medium outline-none rounded px-1 -mx-1 empty:before:content-[attr(data-placeholder)] empty:before:text-base-content/30"
            contenteditable="true"
            phx-hook="EditableTitle"
            phx-update="ignore"
            data-placeholder={dgettext("flows", "Untitled")}
            data-name={@flow.name}
          >
            {@flow.name}
          </h1>
          <h1 :if={!@can_edit} class="text-sm font-medium">{@flow.name}</h1>
          <div :if={@can_edit} class="flex items-center gap-1 text-xs">
            <span class="text-base-content/50">#</span>
            <span
              id="flow-shortcut"
              class="text-base-content/50 outline-none hover:text-base-content empty:before:content-[attr(data-placeholder)] empty:before:text-base-content/30"
              contenteditable="true"
              phx-hook="EditableShortcut"
              phx-update="ignore"
              data-placeholder={dgettext("flows", "add-shortcut")}
              data-shortcut={@flow.shortcut || ""}
            >
              {@flow.shortcut}
            </span>
          </div>
          <div :if={!@can_edit && @flow.shortcut} class="text-xs text-base-content/50">
            #{@flow.shortcut}
          </div>
        </div>
        <span
          :if={@flow.is_main}
          class="badge badge-primary badge-xs"
          title={dgettext("flows", "Main flow")}
        >
          {dgettext("flows", "Main")}
        </span>
      </div>

      <%!-- Scene map indicator --%>
      <.scene_map_indicator
        :if={@can_edit || @scene_map_name}
        scene_map_name={@scene_map_name}
        scene_map_inherited={@scene_map_inherited}
        can_edit={@can_edit}
        available_maps={@available_maps}
      />

      <%!-- Save indicator --%>
      <.save_indicator :if={@can_edit} status={@save_status} />
    </div>
    """
  end

  attr :scene_map_name, :string, default: nil
  attr :scene_map_inherited, :boolean, default: false
  attr :can_edit, :boolean, required: true
  attr :available_maps, :list, default: []

  defp scene_map_indicator(assigns) do
    ~H"""
    <div class="hidden lg:block">
      <div class="dropdown dropdown-bottom dropdown-end">
        <button
          type="button"
          tabindex="0"
          class={[
            "flex items-center gap-1.5 bg-base-200/95 backdrop-blur rounded-xl shadow-lg border px-2.5 py-1.5 text-xs",
            if(@scene_map_name,
              do: "border-primary/30 text-base-content",
              else: "border-base-300 text-base-content/50"
            )
          ]}
          title={dgettext("flows", "Scene map backdrop")}
        >
          <.icon name="map" class="size-3.5" />
          <span :if={@scene_map_name} class="truncate max-w-[120px]">{@scene_map_name}</span>
          <span :if={!@scene_map_name}>{dgettext("flows", "No scene")}</span>
          <span
            :if={@scene_map_inherited}
            class="text-base-content/40 text-[10px]"
            title={dgettext("flows", "Inherited from parent flow")}
          >
            ({dgettext("flows", "inherited")})
          </span>
        </button>
        <ul
          :if={@can_edit}
          tabindex="0"
          class="dropdown-content menu menu-xs bg-base-100 rounded-box shadow-lg border border-base-300 w-56 z-50 mt-2 max-h-60 overflow-y-auto"
        >
          <li>
            <button
              type="button"
              phx-click="update_scene_map"
              phx-value-map_id=""
              class={[
                "flex items-center gap-2",
                if(!@scene_map_name, do: "active")
              ]}
            >
              <.icon name="x" class="size-3 opacity-60" />
              <span class="text-base-content/60">{dgettext("flows", "No scene (inherit)")}</span>
            </button>
          </li>
          <li :for={map <- @available_maps}>
            <button
              type="button"
              phx-click="update_scene_map"
              phx-value-map_id={map.id}
            >
              <.icon name="map" class="size-3 opacity-60" />
              <span class="truncate">{map.name}</span>
            </button>
          </li>
        </ul>
      </div>
    </div>
    """
  end
end
