defmodule StoryarnWeb.FlowLive.Nodes.Instruction.ConfigSidebar do
  @moduledoc """
  Sidebar panel for instruction nodes.

  Renders: description field + instruction builder (JS hook).
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.InstructionBuilder

  attr :node, :map, required: true
  attr :form, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :all_pages, :list, default: []
  attr :flow_hubs, :list, default: []
  attr :audio_assets, :list, default: []
  attr :panel_sections, :map, default: %{}
  attr :project_variables, :list, default: []
  attr :referencing_jumps, :list, default: []

  def config_sidebar(assigns) do
    assignments = assigns.node.data["assignments"] || []
    description = assigns.node.data["description"] || ""

    assigns =
      assigns
      |> assign(:assignments, assignments)
      |> assign(:description, description)

    ~H"""
    <div class="space-y-4">
      <%!-- Description field --%>
      <div class="form-control">
        <label class="label">
          <span class="label-text text-xs">{gettext("Description")}</span>
        </label>
        <input
          type="text"
          value={@description}
          placeholder={gettext("e.g., Reward player for quest completion")}
          class="input input-sm input-bordered w-full text-xs"
          disabled={!@can_edit}
          phx-blur="update_node_field"
          phx-value-field="description"
        />
      </div>

      <%!-- Assignments builder --%>
      <div class="space-y-2">
        <label class="label">
          <span class="label-text text-xs">{gettext("Assignments")}</span>
        </label>
        <.instruction_builder
          id={"instruction-builder-#{@node.id}"}
          assignments={@assignments}
          variables={@project_variables}
          can_edit={@can_edit}
        />
        <p :if={@assignments == [] && @can_edit} class="text-xs text-base-content/50">
          {gettext("Add assignments to set variable values when this node executes.")}
        </p>
      </div>
    </div>
    """
  end

  def wrap_in_form?, do: false
end
