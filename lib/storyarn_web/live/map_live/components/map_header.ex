defmodule StoryarnWeb.MapLive.Components.MapHeader do
  @moduledoc """
  Header bar component for the map editor.

  Displays the back link, map name (editable), shortcut badge, export dropdown,
  and edit/view mode toggle.
  """

  use Phoenix.Component
  use StoryarnWeb, :verified_routes
  use Gettext, backend: StoryarnWeb.Gettext

  alias Phoenix.LiveView.JS

  import StoryarnWeb.Components.CoreComponents

  attr :map, :map, required: true
  attr :ancestors, :list, default: []
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :can_edit, :boolean, required: true
  attr :edit_mode, :boolean, required: true
  attr :referencing_flows, :list, default: []

  def map_header(assigns) do
    ~H"""
    <header class="navbar bg-base-100 border-b border-base-300 px-4 shrink-0">
      <div class="flex-none flex items-center gap-1">
        <.link
          navigate={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/maps"}
          class="btn btn-ghost btn-sm gap-2"
        >
          <.icon name="chevron-left" class="size-4" />
          {dgettext("maps", "Maps")}
        </.link>
      </div>
      <div class="flex-1 flex items-center gap-3 ml-4">
        <div class="flex items-baseline gap-1">
          <span
            :for={{ancestor, idx} <- Enum.with_index(@ancestors)}
            class="flex items-baseline gap-1 text-sm text-base-content/50"
          >
            <span :if={idx > 0} class="opacity-50">/</span>
            <.link
              navigate={
                ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/maps/#{ancestor.id}"
              }
              class="hover:text-base-content truncate max-w-[120px]"
            >
              {ancestor.name}
            </.link>
          </span>
          <span :if={@ancestors != []} class="text-sm text-base-content/50 opacity-50">/</span>
          <h1
            :if={@can_edit}
            id="map-title"
            class="text-lg font-medium outline-none rounded px-1 -mx-1 empty:before:content-[attr(data-placeholder)] empty:before:text-base-content/30"
            contenteditable="true"
            phx-hook="EditableTitle"
            phx-update="ignore"
            data-placeholder={dgettext("maps", "Untitled")}
            data-name={@map.name}
          >
            {@map.name}
          </h1>
          <h1 :if={!@can_edit} class="text-lg font-medium">
            {@map.name}
          </h1>
        </div>
        <span :if={@map.shortcut} class="badge badge-ghost font-mono text-xs">
          #{@map.shortcut}
        </span>
        <div
          :if={@referencing_flows != []}
          phx-hook="ToolbarPopover"
          id="popover-referencing-flows"
          data-width="14rem"
          data-placement="bottom-start"
        >
          <button data-role="trigger" type="button" class="btn btn-xs btn-ghost gap-1 font-normal">
            <.icon name="git-branch" class="size-3.5 opacity-60" />
            <span class="text-xs">
              {dngettext("maps", "Used in %{count} flow", "Used in %{count} flows",
                length(@referencing_flows), count: length(@referencing_flows))}
            </span>
          </button>
          <template data-role="popover-template">
            <ul class="menu menu-xs p-1">
              <li :for={ref <- @referencing_flows}>
                <button
                  type="button"
                  data-event="navigate_to_referencing_flow"
                  data-params={Jason.encode!(%{"flow-id" => ref.flow_id})}
                  class="flex items-center gap-2"
                >
                  <.icon name="git-branch" class="size-3.5 opacity-60" />
                  <span class="truncate">{ref.flow_name}</span>
                </button>
              </li>
            </ul>
          </template>
        </div>
      </div>
      <div class="flex-none flex items-center gap-1">
        <%!-- Export dropdown --%>
        <div
          phx-hook="ToolbarPopover"
          id="popover-export-map"
          data-width="11rem"
          data-placement="bottom-end"
        >
          <button
            data-role="trigger"
            type="button"
            class="btn btn-ghost btn-sm gap-2"
            title={dgettext("maps", "Export map")}
          >
            <.icon name="upload" class="size-4" />
            {dgettext("maps", "Export")}
          </button>
          <template data-role="popover-template">
            <ul class="menu menu-sm p-1">
              <li>
                <button
                  type="button"
                  data-event="export_map"
                  data-params={Jason.encode!(%{"format" => "png"})}
                  class="text-sm"
                >
                  <.icon name="image" class="size-4" />
                  {dgettext("maps", "Export as PNG")}
                </button>
              </li>
              <li>
                <button
                  type="button"
                  data-event="export_map"
                  data-params={Jason.encode!(%{"format" => "svg"})}
                  class="text-sm"
                >
                  <.icon name="file-code" class="size-4" />
                  {dgettext("maps", "Export as SVG")}
                </button>
              </li>
            </ul>
          </template>
        </div>

        <%!-- Map settings gear button --%>
        <button
          :if={@can_edit && @edit_mode}
          type="button"
          class="btn btn-ghost btn-sm btn-square"
          title={dgettext("maps", "Map Settings")}
          phx-click={JS.toggle_class("hidden", to: "#map-settings-floating")}
        >
          <.icon name="settings" class="size-4" />
        </button>

        <%!-- Edit/View mode switcher --%>
        <div :if={@can_edit} class="flex rounded-lg border border-base-300 overflow-hidden">
          <button
            type="button"
            phx-click="toggle_edit_mode"
            phx-value-mode="view"
            class={"btn btn-sm rounded-none border-0 gap-1.5 #{if !@edit_mode, do: "btn-primary", else: "btn-ghost"}"}
          >
            <.icon name="eye" class="size-4" />
            {dgettext("maps", "View")}
          </button>
          <button
            type="button"
            phx-click="toggle_edit_mode"
            phx-value-mode="edit"
            class={"btn btn-sm rounded-none border-0 gap-1.5 #{if @edit_mode, do: "btn-primary", else: "btn-ghost"}"}
          >
            <.icon name="pencil" class="size-4" />
            {dgettext("maps", "Edit")}
          </button>
        </div>
      </div>
    </header>
    """
  end
end
