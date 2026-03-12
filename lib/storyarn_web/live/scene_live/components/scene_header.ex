defmodule StoryarnWeb.SceneLive.Components.SceneHeader do
  @moduledoc """
  Header bar component for the scene editor.

  Displays breadcrumbs + scene name (floating below toolbars) and action buttons
  (export, settings, edit/view toggle) at the same level as layout toolbars.
  """

  use Phoenix.Component
  use StoryarnWeb, :verified_routes
  use Gettext, backend: StoryarnWeb.Gettext

  alias Phoenix.LiveView.JS

  import StoryarnWeb.Components.CoreComponents
  import StoryarnWeb.Components.FocusLayout, only: [entity_title_pill: 1]

  @doc "Actions toolbar (export, settings, edit/view toggle) — fixed top-right."
  attr :can_edit, :boolean, required: true
  attr :edit_mode, :boolean, required: true

  def map_actions(assigns) do
    ~H"""
    <div class="flex items-center gap-1 px-1.5 py-1 surface-panel">
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
          class="btn btn-ghost btn-sm gap-1.5"
          title={dgettext("scenes", "Export scene")}
        >
          <.icon name="upload" class="size-4" />
          <span class="hidden xl:inline">{dgettext("scenes", "Export")}</span>
        </button>
        <template data-role="popover-template">
          <ul class="menu menu-xs p-1">
            <li>
              <button
                type="button"
                data-event="export_scene"
                data-params={Jason.encode!(%{"format" => "png"})}
                class="text-sm"
              >
                <.icon name="image" class="size-4" />
                {dgettext("scenes", "Export as PNG")}
              </button>
            </li>
            <li>
              <button
                type="button"
                data-event="export_scene"
                data-params={Jason.encode!(%{"format" => "svg"})}
                class="text-sm"
              >
                <.icon name="file-code" class="size-4" />
                {dgettext("scenes", "Export as SVG")}
              </button>
            </li>
          </ul>
        </template>
      </div>

      <%!-- Scene settings button --%>
      <button
        :if={@can_edit && @edit_mode}
        type="button"
        phx-click={JS.dispatch("panel:toggle", to: "#scene-settings-panel")}
        data-panel-trigger="scene-settings-panel"
        class="btn btn-ghost btn-sm btn-square"
        title={dgettext("scenes", "Scene Settings")}
      >
        <.icon name="settings" class="size-4" />
      </button>

      <%!-- Edit/View mode switcher --%>
      <div :if={@can_edit} class="flex rounded-lg border border-base-300/50 overflow-hidden">
        <button
          type="button"
          phx-click="toggle_edit_mode"
          phx-value-mode="view"
          class={"btn btn-sm rounded-none border-0 gap-1 #{if !@edit_mode, do: "btn-primary", else: "btn-ghost"}"}
        >
          <.icon name="eye" class="size-4" />
          <span class="hidden xl:inline">{dgettext("scenes", "View")}</span>
        </button>
        <button
          type="button"
          phx-click="toggle_edit_mode"
          phx-value-mode="edit"
          class={"btn btn-sm rounded-none border-0 gap-1 #{if @edit_mode, do: "btn-primary", else: "btn-ghost"}"}
        >
          <.icon name="pencil" class="size-4" />
          <span class="hidden xl:inline">{dgettext("scenes", "Edit")}</span>
        </button>
      </div>
    </div>
    """
  end

  @doc "Scene info bar (breadcrumbs + title + shortcut + refs) — for top_bar_extra slot."
  attr :scene, :map, required: true
  attr :ancestors, :list, default: []
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :can_edit, :boolean, required: true
  attr :referencing_flows, :list, default: []

  def map_info_bar(assigns) do
    ~H"""
    <.entity_title_pill
      name={@scene.name}
      shortcut={@scene.shortcut}
      can_edit={@can_edit}
      name_id="map-title"
      name_placeholder={dgettext("scenes", "Untitled")}
      name_data={@scene.name}
    >
      <:before>
        <div :if={@ancestors != []} class="flex items-baseline gap-1">
          <span
            :for={{ancestor, idx} <- Enum.with_index(@ancestors)}
            class="flex items-baseline gap-1 text-xs text-base-content/50"
          >
            <span :if={idx > 0} class="opacity-50">/</span>
            <.link
              navigate={
                ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/scenes/#{ancestor.id}"
              }
              class="hover:text-base-content truncate max-w-[100px]"
            >
              {ancestor.name}
            </.link>
          </span>
          <span class="text-xs text-base-content/50 opacity-50">/</span>
        </div>
      </:before>
      <:extra>
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
              {dngettext(
                "maps",
                "Used in %{count} flow",
                "Used in %{count} flows",
                length(@referencing_flows),
                count: length(@referencing_flows)
              )}
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
      </:extra>
    </.entity_title_pill>
    """
  end
end
