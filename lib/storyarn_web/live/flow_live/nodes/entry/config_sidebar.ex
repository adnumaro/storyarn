defmodule StoryarnWeb.FlowLive.Nodes.Entry.ConfigSidebar do
  @moduledoc """
  Sidebar panel for entry nodes.
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents

  attr :node, :map, required: true
  attr :form, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :all_sheets, :list, default: []
  attr :flow_hubs, :list, default: []
  attr :project, :map, required: true
  attr :current_user, :map, required: true
  attr :panel_sections, :map, default: %{}
  attr :project_variables, :list, default: []
  attr :referencing_jumps, :list, default: []
  attr :referencing_flows, :list, default: []

  def config_sidebar(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="text-center py-4">
        <.icon name="play" class="size-8 text-success mx-auto mb-2" />
        <p class="text-sm text-base-content/60">
          {dgettext("flows", "This is the entry point of the flow.")}
        </p>
        <p class="text-xs text-base-content/50 mt-2">
          {dgettext("flows", "Connect this node to the first node in your flow.")}
        </p>
      </div>

      <div :if={@referencing_flows != []}>
        <h3 class="text-xs font-semibold text-base-content/60 uppercase tracking-wide mb-2">
          {dgettext("flows", "Referenced By")}
          <span class="text-base-content/40 ml-1">({length(@referencing_flows)})</span>
        </h3>
        <div class="space-y-1">
          <button
            :for={ref <- @referencing_flows}
            type="button"
            class="btn btn-ghost btn-xs w-full justify-start gap-2 font-normal"
            phx-click="navigate_to_referencing_flow"
            phx-value-flow-id={ref.flow_id}
          >
            <.icon
              name={if ref.node_type == "subflow", do: "box", else: "square"}
              class="size-3 opacity-60"
            />
            <span class="truncate">{ref.flow_name}</span>
          </button>
        </div>
      </div>
    </div>
    """
  end

  def wrap_in_form?, do: true
end
