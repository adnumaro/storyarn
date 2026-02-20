defmodule StoryarnWeb.FlowLive.Components.BuilderPanel do
  @moduledoc """
  Builder panel component for condition and instruction nodes.

  Renders as a floating panel below the toolbar, containing
  the condition builder or instruction builder depending on node type.
  """

  use StoryarnWeb, :html

  import StoryarnWeb.Components.ConditionBuilder
  import StoryarnWeb.Components.InstructionBuilder

  alias Storyarn.Flows.Condition

  attr :node, :map, required: true
  attr :form, :any, required: true
  attr :can_edit, :boolean, required: true
  attr :project_variables, :list, default: []

  def builder_content(assigns) do
    ~H"""
    <div class="flex items-center justify-between mb-3">
      <h3 class="font-semibold text-sm">{builder_title(@node.type)}</h3>
      <button type="button" phx-click="close_builder" class="btn btn-ghost btn-xs btn-square">
        <.icon name="x" class="size-3.5" />
      </button>
    </div>
    {render_builder(@node.type, assigns)}
    """
  end

  defp builder_title("condition"), do: dgettext("flows", "Condition Builder")
  defp builder_title("instruction"), do: dgettext("flows", "Instruction Builder")
  defp builder_title(_), do: ""

  defp render_builder("condition", assigns) do
    condition_data = assigns.node.data["condition"] || %{}
    switch_mode = assigns.node.data["switch_mode"] == true

    assigns =
      assigns
      |> assign(:condition_data, condition_data)
      |> assign(:switch_mode, switch_mode)

    ~H"""
    <.condition_builder
      id={"condition-builder-#{@node.id}"}
      condition={@condition_data}
      variables={@project_variables}
      can_edit={@can_edit}
      switch_mode={@switch_mode}
    />
    <p
      :if={!Condition.has_rules?(@condition_data) && !@switch_mode}
      class="text-xs text-base-content/50 mt-2"
    >
      {dgettext("flows", "Add rules to define when to route to True/False.")}
    </p>
    <p
      :if={!Condition.has_rules?(@condition_data) && @switch_mode}
      class="text-xs text-base-content/50 mt-2"
    >
      {dgettext("flows", "Add conditions. Each one creates a separate output.")}
    </p>
    """
  end

  defp render_builder("instruction", assigns) do
    assignments = assigns.node.data["assignments"] || []

    assigns = assign(assigns, :assignments, assignments)

    ~H"""
    <.instruction_builder
      id={"instruction-builder-#{@node.id}"}
      assignments={@assignments}
      variables={@project_variables}
      can_edit={@can_edit}
    />
    <p :if={@assignments == [] && @can_edit} class="text-xs text-base-content/50 mt-2">
      {dgettext("flows", "Add assignments to set variable values when this node executes.")}
    </p>
    """
  end

  defp render_builder(type, assigns) do
    require Logger
    Logger.warning("BuilderPanel: no builder defined for node type #{inspect(type)}")
    ~H""
  end
end
