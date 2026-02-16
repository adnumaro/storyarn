defmodule StoryarnWeb.FlowLive.Nodes.Subflow.ConfigSidebar do
  @moduledoc """
  Sidebar panel for subflow nodes.
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
  attr :available_flows, :list, default: []
  attr :subflow_exits, :list, default: []

  def config_sidebar(assigns) do
    flow_options =
      [{"", gettext("Select a flow...")}] ++
        Enum.map(assigns.available_flows, fn flow ->
          display =
            if flow.shortcut && flow.shortcut != "" do
              "#{flow.name} (##{flow.shortcut})"
            else
              flow.name
            end

          {display, to_string(flow.id)}
        end)

    current_ref = assigns.node.data["referenced_flow_id"]
    current_ref_str = if current_ref, do: to_string(current_ref), else: ""

    assigns =
      assigns
      |> assign(:flow_options, flow_options)
      |> assign(:current_ref_str, current_ref_str)

    ~H"""
    <div class="space-y-4">
      <div>
        <label class="label text-sm font-medium">{gettext("Referenced Flow")}</label>
        <form phx-change="update_subflow_reference">
          <select
            class="select select-bordered select-sm w-full"
            name="referenced_flow_id"
            disabled={!@can_edit}
          >
            <option
              :for={{display, value} <- @flow_options}
              value={value}
              selected={value == @current_ref_str}
            >
              {display}
            </option>
          </select>
        </form>
        <p class="text-xs text-base-content/60 mt-1">
          {gettext("Select a flow to reference. Double-click the node to navigate to it.")}
        </p>
      </div>

      <div :if={@node.data["stale_reference"]} class="alert alert-error text-sm">
        <.icon name="alert-triangle" class="size-4" />
        <span>{gettext("Referenced flow has been deleted.")}</span>
      </div>

      <div :if={@current_ref_str != "" && !@node.data["stale_reference"]}>
        <h3 class="text-xs font-semibold text-base-content/60 uppercase tracking-wide mb-2">
          {gettext("Exit Nodes")}
          <span class="text-base-content/40 ml-1">({length(@subflow_exits)})</span>
        </h3>
        <p :if={@subflow_exits == []} class="text-xs text-base-content/40 italic">
          {gettext("No Exit nodes in the referenced flow.")}
        </p>
        <div :if={@subflow_exits != []} class="space-y-1">
          <div
            :for={exit_node <- @subflow_exits}
            class="flex items-center gap-2 text-xs px-2 py-1 rounded bg-base-200"
          >
            <span
              class="w-2 h-2 rounded-full shrink-0"
              style={"background-color: #{exit_node[:outcome_color] || "#22c55e"}"}
            />
            <span class="opacity-60">
              {exit_mode_icon(exit_node[:exit_mode] || "terminal")}
            </span>
            <span class="truncate">{exit_node.label || gettext("Unnamed exit")}</span>
          </div>
        </div>
      </div>

      <button
        :if={@current_ref_str != "" && !@node.data["stale_reference"]}
        type="button"
        class="btn btn-ghost btn-sm w-full"
        phx-click="navigate_to_subflow"
        phx-value-flow-id={@current_ref_str}
      >
        <.icon name="external-link" class="size-4 mr-2" />
        {gettext("Open Subflow")}
      </button>

      <div :if={length(@flow_options) <= 1} class="alert alert-warning text-sm">
        <.icon name="alert-triangle" class="size-4" />
        <span>{gettext("No other flows in this project. Create another flow first.")}</span>
      </div>
    </div>
    """
  end

  defp exit_mode_icon("caller_return"), do: "\u21A9"
  defp exit_mode_icon("flow_reference"), do: "\u2192"
  defp exit_mode_icon(_), do: "\u25A0"
end
