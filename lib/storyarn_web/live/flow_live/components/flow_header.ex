defmodule StoryarnWeb.FlowLive.Components.FlowHeader do
  @moduledoc false

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents
  import StoryarnWeb.Components.FocusLayout, only: [entity_title_pill: 1]
  import StoryarnWeb.Components.SaveIndicator

  import StoryarnWeb.FlowLive.Components.NodeTypeHelpers,
    only: [node_type_icon: 1]

  alias StoryarnWeb.FlowLive.Helpers.NavigationHistory

  @doc "Flow info bar (nav history + title + stats + scene map + save indicator) — overlays the canvas."
  attr :flow, :map, required: true
  attr :can_edit, :boolean, required: true
  attr :save_status, :atom, default: :idle
  attr :nav_history, :map, default: nil
  attr :scene_name, :string, default: nil
  attr :scene_inherited, :boolean, default: false
  attr :available_scenes, :list, default: []
  attr :flow_word_count, :integer, default: 0
  attr :flow_error_nodes, :list, default: []
  attr :flow_info_nodes, :list, default: []
  attr :is_draft, :boolean, default: false

  def flow_info_bar(assigns) do
    ~H"""
    <div class="flex items-stretch gap-2">
      <%!-- Nav history --%>
      <% back_entry = @nav_history && NavigationHistory.peek_back(@nav_history) %>
      <% forward_entry = @nav_history && NavigationHistory.peek_forward(@nav_history) %>
      <div
        :if={back_entry || forward_entry}
        class="flex items-center gap-0.5 surface-panel px-1"
      >
        <button
          :if={back_entry}
          type="button"
          class="toolbar-btn gap-1 text-base-content/60 max-w-[140px]"
          phx-click="nav_back"
          title={dgettext("flows", "Alt+Left")}
        >
          <.icon name="arrow-left" class="size-3.5 shrink-0" />
          <span class="truncate text-xs">{back_entry.flow_name}</span>
        </button>
        <button
          :if={forward_entry}
          type="button"
          class="toolbar-btn gap-1 text-base-content/60 max-w-[140px]"
          phx-click="nav_forward"
          title={dgettext("flows", "Alt+Right")}
        >
          <span class="truncate text-xs">{forward_entry.flow_name}</span>
          <.icon name="arrow-right" class="size-3.5 shrink-0" />
        </button>
      </div>

      <%!-- Flow title pill --%>
      <.entity_title_pill
        name={@flow.name}
        shortcut={@flow.shortcut}
        can_edit={@can_edit}
        name_id="flow-title"
        name_placeholder={dgettext("flows", "Untitled")}
        shortcut_id="flow-shortcut"
        shortcut_placeholder={dgettext("flows", "add-shortcut")}
      >
        <:extra>
          <span
            :if={@flow.is_main}
            class="badge badge-primary badge-xs"
            title={dgettext("flows", "Main flow")}
          >
            {dgettext("flows", "Main")}
          </span>
        </:extra>
      </.entity_title_pill>

      <%!-- Combined scene + stats pill --%>
      <.flow_stats_scene_panel
        flow_word_count={@flow_word_count}
        flow_error_nodes={@flow_error_nodes}
        flow_info_nodes={@flow_info_nodes}
        scene_name={@scene_name}
        scene_inherited={@scene_inherited}
        can_edit={@can_edit}
        available_scenes={@available_scenes}
      />

      <%!-- Create Draft button --%>
      <button
        :if={@can_edit && !@is_draft}
        type="button"
        phx-click="create_draft"
        class="toolbar-btn gap-1 text-base-content/60 tooltip tooltip-bottom tooltip-delay hidden lg:flex"
        data-tip={dgettext("drafts", "Create a private draft copy")}
      >
        <.icon name="git-branch" class="size-3.5" />
        <span class="text-xs">{dgettext("drafts", "Draft")}</span>
      </button>

      <%!-- Save indicator --%>
      <.save_indicator :if={@can_edit} status={@save_status} />
    </div>
    """
  end

  attr :flow_word_count, :integer, required: true
  attr :flow_error_nodes, :list, required: true
  attr :flow_info_nodes, :list, required: true
  attr :scene_name, :string, default: nil
  attr :scene_inherited, :boolean, default: false
  attr :can_edit, :boolean, required: true
  attr :available_scenes, :list, default: []

  defp flow_stats_scene_panel(assigns) do
    assigns =
      assigns
      |> assign(:error_count, length(assigns.flow_error_nodes))
      |> assign(:info_count, length(assigns.flow_info_nodes))
      |> assign(:show_scene, assigns.can_edit || assigns.scene_name != nil)

    ~H"""
    <div class="hidden lg:flex items-center gap-1 px-1 py-1 surface-panel text-xs">
      <%!-- Scene selector --%>
      <div :if={@show_scene} class="dropdown dropdown-bottom dropdown-end">
        <button
          type="button"
          tabindex="0"
          class={[
            "toolbar-btn gap-1.5 tooltip tooltip-bottom tooltip-delay",
            if(@scene_name, do: "text-base-content", else: "text-base-content/50")
          ]}
          data-tip={dgettext("flows", "Scene backdrop")}
        >
          <.icon name="map" class="size-3.5" />
          <span :if={@scene_name} class="truncate max-w-[120px]">{@scene_name}</span>
          <span :if={!@scene_name}>{dgettext("flows", "No scene")}</span>
          <span
            :if={@scene_inherited}
            class="tooltip tooltip-bottom text-base-content/40 text-[10px]"
            data-tip={dgettext("flows", "Inherited from parent flow")}
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
              phx-click="update_scene"
              phx-value-scene_id=""
              class={["flex items-center gap-2", if(!@scene_name, do: "active")]}
            >
              <.icon name="x" class="size-3 opacity-60" />
              <span class="text-base-content/60">{dgettext("flows", "No scene (inherit)")}</span>
            </button>
          </li>
          <li :for={map <- @available_scenes}>
            <button type="button" phx-click="update_scene" phx-value-scene_id={map.id}>
              <.icon name="map" class="size-3 opacity-60" />
              <span class="truncate">{map.name}</span>
            </button>
          </li>
        </ul>
      </div>

      <%!-- Divider --%>
      <div :if={@show_scene} class="w-px h-5 bg-base-content/10"></div>

      <%!-- Word count --%>
      <div
        class="toolbar-btn gap-1.5 text-base-content/60 tooltip tooltip-bottom"
        data-tip={
          dngettext(
            "flows",
            "%{count} word in this flow",
            "%{count} words in this flow",
            @flow_word_count,
            count: @flow_word_count
          )
        }
      >
        <.icon name="text" class="size-3.5" />
        <span>{@flow_word_count}</span>
      </div>

      <%!-- Flow health indicator: errors > info > healthy --%>
      <%= cond do %>
        <% @error_count > 0 -> %>
          <div class="dropdown dropdown-bottom">
            <button
              type="button"
              tabindex="0"
              class="toolbar-btn gap-0 !text-error"
            >
              <span class="flex items-center gap-1.5">
                <.icon name="triangle-alert" class="size-3.5" />
                <span>{@error_count}</span>
              </span>
              <span
                :if={@info_count > 0}
                class="flex items-center gap-1.5 ml-2 text-info"
              >
                <.icon name="info" class="size-3.5" />
                <span>{@info_count}</span>
              </span>
              <.icon name="chevron-down" class="size-3 opacity-50 ml-1" />
            </button>
            <ul
              tabindex="0"
              class="dropdown-content menu menu-xs bg-base-100 rounded-box shadow-lg border border-base-300 z-50 mt-2 max-h-60 overflow-y-auto w-max"
            >
              <li :if={@flow_info_nodes != []} class="menu-title text-[10px]">
                {dgettext("flows", "Errors")}
              </li>
              <li :for={node <- @flow_error_nodes}>
                <button
                  type="button"
                  phx-click="navigate_to_node"
                  phx-value-id={node.id}
                  class="flex items-center gap-2"
                >
                  <.node_type_icon type={node.type} />
                  <span class="truncate">{node.label}</span>
                </button>
              </li>
              <li :if={@flow_info_nodes != []} class="menu-title text-[10px] pt-2">
                {dgettext("flows", "Info")}
              </li>
              <li :for={node <- @flow_info_nodes}>
                <button
                  type="button"
                  phx-click="navigate_to_node"
                  phx-value-id={node.id}
                  class="flex flex-col items-start gap-0.5"
                >
                  <span class="flex items-center gap-2">
                    <.node_type_icon type={node.type} />
                    <span class="truncate">{node.label}</span>
                  </span>
                  <span class="text-[11px] text-base-content/40 pl-5">{node.reason}</span>
                </button>
              </li>
            </ul>
          </div>
        <% @info_count > 0 -> %>
          <div class="dropdown dropdown-bottom">
            <button
              type="button"
              tabindex="0"
              class="toolbar-btn gap-1.5 !text-info"
              title={
                dngettext(
                  "flows",
                  "%{count} node with info",
                  "%{count} nodes with info",
                  @info_count,
                  count: @info_count
                )
              }
            >
              <.icon name="info" class="size-3.5" />
              <span>{@info_count}</span>
              <.icon name="chevron-down" class="size-3 opacity-50" />
            </button>
            <ul
              tabindex="0"
              class="dropdown-content menu menu-xs bg-base-100 rounded-box shadow-lg border border-base-300 z-50 mt-2 max-h-60 overflow-y-auto w-max"
            >
              <li :for={node <- @flow_info_nodes}>
                <button
                  type="button"
                  phx-click="navigate_to_node"
                  phx-value-id={node.id}
                  class="flex flex-col items-start gap-0.5"
                >
                  <span class="flex items-center gap-2">
                    <.node_type_icon type={node.type} />
                    <span class="truncate">{node.label}</span>
                  </span>
                  <span class="text-[11px] text-base-content/40 pl-5">{node.reason}</span>
                </button>
              </li>
            </ul>
          </div>
        <% true -> %>
          <div
            class="toolbar-btn !text-success/60"
            title={dgettext("flows", "This flow looks great!")}
          >
            <.icon name="circle-check" class="size-3.5" />
          </div>
      <% end %>
    </div>
    """
  end
end
