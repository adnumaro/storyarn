defmodule StoryarnWeb.FlowLive.Components.PropertiesPanels do
  @moduledoc """
  Properties panel components for the flow editor.
  Provides shared frame, delegates content to per-type sidebar modules.
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents
  import StoryarnWeb.FlowLive.Components.NodeTypeHelpers

  alias StoryarnWeb.FlowLive.NodeTypeRegistry

  attr :node, :map, required: true
  attr :form, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :all_sheets, :list, default: []
  attr :flow_hubs, :list, default: []
  attr :audio_assets, :list, default: []
  attr :panel_sections, :map, default: %{}
  attr :project_variables, :list, default: []
  attr :referencing_jumps, :list, default: []
  attr :available_flows, :list, default: []
  attr :subflow_exits, :list, default: []

  def node_properties_panel(assigns) do
    ~H"""
    <aside class="w-80 bg-base-100 border-l border-base-300 flex flex-col overflow-hidden">
      <div class="p-4 border-b border-base-300 flex items-center justify-between">
        <h2 class="font-medium flex items-center gap-2">
          <.node_type_icon type={@node.type} />
          {node_type_label(@node.type)}
        </h2>
        <button type="button" class="btn btn-ghost btn-xs btn-square" phx-click="deselect_node">
          <.icon name="x" class="size-4" />
        </button>
      </div>

      <div class="flex-1 overflow-y-auto p-4">
        <.node_sidebar_content
          node={@node}
          form={@form}
          can_edit={@can_edit}
          all_sheets={@all_sheets}
          flow_hubs={@flow_hubs}
          audio_assets={@audio_assets}
          panel_sections={@panel_sections}
          project_variables={@project_variables}
          referencing_jumps={@referencing_jumps}
          available_flows={@available_flows}
          subflow_exits={@subflow_exits}
        />
      </div>

      <div class="p-4 border-t border-base-300 space-y-2">
        <button
          :if={@node.type == "dialogue"}
          type="button"
          class="btn btn-primary btn-sm w-full"
          phx-click="open_screenplay"
        >
          <.icon name="maximize-2" class="size-4 mr-2" />
          {gettext("Open Screenplay")}
        </button>
        <button
          :if={@node.type == "dialogue"}
          type="button"
          class="btn btn-ghost btn-sm w-full"
          phx-click="start_preview"
          phx-value-id={@node.id}
        >
          <.icon name="play" class="size-4 mr-2" />
          {gettext("Preview from here")}
        </button>
        <button
          :if={@can_edit && @node.type != "entry"}
          type="button"
          class="btn btn-error btn-outline btn-sm w-full"
          phx-click="delete_node"
          phx-value-id={@node.id}
          data-confirm={gettext("Are you sure you want to delete this node?")}
        >
          <.icon name="trash-2" class="size-4 mr-2" />
          {gettext("Delete Node")}
        </button>
        <p :if={@node.type == "entry"} class="text-xs text-base-content/60 text-center">
          {gettext("Entry nodes cannot be deleted.")}
        </p>
      </div>
    </aside>
    """
  end

  attr :node, :map, required: true
  attr :form, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :all_sheets, :list, default: []
  attr :flow_hubs, :list, default: []
  attr :audio_assets, :list, default: []
  attr :panel_sections, :map, default: %{}
  attr :project_variables, :list, default: []
  attr :referencing_jumps, :list, default: []
  attr :available_flows, :list, default: []
  attr :subflow_exits, :list, default: []

  defp node_sidebar_content(assigns) do
    sidebar_mod = NodeTypeRegistry.sidebar_module(assigns.node.type)
    assigns = assign(assigns, :sidebar_mod, sidebar_mod)

    ~H"""
    {if @sidebar_mod, do: @sidebar_mod.config_sidebar(assigns), else: default_sidebar(assigns)}
    """
  end

  defp default_sidebar(assigns) do
    ~H"""
    <p class="text-sm text-base-content/60">
      {gettext("No properties for this node type.")}
    </p>
    """
  end
end
