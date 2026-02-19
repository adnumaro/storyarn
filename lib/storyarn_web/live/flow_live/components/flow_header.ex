defmodule StoryarnWeb.FlowLive.Components.FlowHeader do
  @moduledoc false

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext
  use StoryarnWeb, :verified_routes

  import StoryarnWeb.Components.CoreComponents
  import StoryarnWeb.Components.CollaborationComponents
  import StoryarnWeb.Components.SaveIndicator
  import StoryarnWeb.FlowLive.Components.NodeTypeHelpers, only: [node_type_label: 1, node_type_icon: 1]

  attr :flow, :map, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :from_flow, :map, default: nil
  attr :can_edit, :boolean, required: true
  attr :debug_panel_open, :boolean, default: false
  attr :save_status, :atom, default: :idle
  attr :online_users, :list, default: []
  attr :current_user_id, :string, required: true
  attr :node_types, :list, default: []

  def flow_header(assigns) do
    ~H"""
    <header class="navbar bg-base-100 border-b border-base-300 px-4 shrink-0">
      <div class="flex-none flex items-center gap-1">
        <.link
          navigate={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/flows"}
          class="btn btn-ghost btn-sm gap-2"
        >
          <.icon name="chevron-left" class="size-4" />
          {dgettext("flows", "Flows")}
        </.link>
        <.link
          :if={@from_flow}
          navigate={
            ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/flows/#{@from_flow.id}"
          }
          class="btn btn-ghost btn-sm gap-1 text-base-content/60"
        >
          <.icon name="corner-up-left" class="size-3" />
          {@from_flow.name}
        </.link>
      </div>
      <div class="flex-1 flex items-center gap-3 ml-4">
        <div>
          <h1
            :if={@can_edit}
            id="flow-title"
            class="text-lg font-medium outline-none rounded px-1 -mx-1 empty:before:content-[attr(data-placeholder)] empty:before:text-base-content/30"
            contenteditable="true"
            phx-hook="EditableTitle"
            phx-update="ignore"
            data-placeholder={dgettext("flows", "Untitled")}
            data-name={@flow.name}
          >
            {@flow.name}
          </h1>
          <h1 :if={!@can_edit} class="text-lg font-medium">{@flow.name}</h1>
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
          class="badge badge-primary badge-sm"
          title={dgettext("flows", "Main flow")}
        >
          {dgettext("flows", "Main")}
        </span>
      </div>
      <div class="flex-none flex items-center gap-4">
        <.online_users users={@online_users} current_user_id={@current_user_id} />
        <.save_indicator :if={@can_edit} status={@save_status} />
        <.link
          navigate={
            ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/flows/#{@flow.id}/play"
          }
          class="btn btn-ghost btn-sm gap-2"
        >
          <.icon name="play" class="size-4" />
          {dgettext("flows", "Play")}
        </.link>
        <button
          type="button"
          class={[
            "btn btn-sm gap-2",
            if(@debug_panel_open, do: "btn-accent", else: "btn-ghost")
          ]}
          phx-click={if(@debug_panel_open, do: "debug_stop", else: "debug_start")}
        >
          <.icon name="bug" class="size-4" />
          {if @debug_panel_open,
            do: dgettext("flows", "Stop Debug"),
            else: dgettext("flows", "Debug")}
        </button>
        <div :if={@can_edit} class="dropdown dropdown-end">
          <button type="button" tabindex="0" class="btn btn-primary btn-sm gap-2">
            <.icon name="plus" class="size-4" />
            {dgettext("flows", "Add Node")}
          </button>
          <ul
            tabindex="0"
            class="dropdown-content menu menu-sm bg-base-100 rounded-box shadow-lg border border-base-300 w-48 z-50 mt-2"
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
    </header>
    """
  end
end
