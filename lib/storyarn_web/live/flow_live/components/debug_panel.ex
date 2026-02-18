defmodule StoryarnWeb.FlowLive.Components.DebugPanel do
  @moduledoc """
  Debug panel component for the flow editor.

  Renders a docked panel at the bottom of the canvas with:
  - Controls bar: Step, Step Back, Reset, Stop
  - Status indicator
  - Tabbed content area (Console, Variables, History, Path)
  - Response choices when waiting for user input
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents
  import StoryarnWeb.FlowLive.Components.DebugConsoleTab
  import StoryarnWeb.FlowLive.Components.DebugVariablesTab
  import StoryarnWeb.FlowLive.Components.DebugHistoryTab

  alias Storyarn.Flows.Evaluator.Helpers, as: EvalHelpers
  alias StoryarnWeb.FlowLive.Components.DebugHistoryTab

  # Delegate public function that tests call directly
  defdelegate build_path_entries(execution_log, nodes, console),
    to: DebugHistoryTab

  # ===========================================================================
  # Main panel
  # ===========================================================================

  attr :debug_state, :map, required: true
  attr :debug_active_tab, :string, default: "console"
  attr :debug_nodes, :map, default: %{}
  attr :debug_auto_playing, :boolean, default: false
  attr :debug_speed, :integer, default: 800
  attr :debug_editing_var, :string, default: nil
  attr :debug_var_filter, :string, default: ""
  attr :debug_var_changed_only, :boolean, default: false
  attr :debug_current_flow_name, :string, default: nil

  def debug_panel(assigns) do
    ~H"""
    <div
      id="debug-panel"
      phx-hook="DebugPanelResize"
      class="bg-base-100 border-t border-base-300 flex flex-col"
      style="height: 280px;"
      data-debug-active
    >
      <%!-- Drag handle --%>
      <div
        data-resize-handle
        class="h-1 cursor-row-resize bg-transparent hover:bg-accent/30 transition-colors shrink-0"
      >
      </div>
      <%!-- Breadcrumb bar (sub-flow indicator) --%>
      <div
        :if={@debug_state.call_stack != []}
        class="flex items-center gap-1.5 px-3 py-1 bg-info/10 border-b border-info/20 text-xs text-info shrink-0"
      >
        <.icon name="layers" class="size-3 shrink-0" />
        <span :for={frame <- Enum.reverse(@debug_state.call_stack)} class="flex items-center gap-1">
          <span class="text-info/60">{frame[:flow_name] || dgettext("flows", "Flow")}</span>
          <.icon name="chevron-right" class="size-2.5 text-info/40" />
        </span>
        <span class="font-medium">{@debug_current_flow_name || dgettext("flows", "Current")}</span>
      </div>
      <%!-- Controls bar --%>
      <div class="flex items-center gap-2 px-3 py-1.5 border-b border-base-300 shrink-0">
        <div class="flex items-center gap-0.5">
          <button
            :if={!@debug_auto_playing}
            type="button"
            class="btn btn-ghost btn-xs btn-square"
            phx-click="debug_play"
            title={dgettext("flows", "Auto-play")}
            disabled={@debug_state.status == :finished}
          >
            <.icon name="fast-forward" class="size-3.5" />
          </button>
          <button
            :if={@debug_auto_playing}
            type="button"
            class="btn btn-accent btn-xs btn-square"
            phx-click="debug_pause"
            title={dgettext("flows", "Pause")}
          >
            <.icon name="pause" class="size-3.5" />
          </button>
          <div class="divider divider-horizontal mx-0.5 h-4"></div>
          <button
            type="button"
            class="btn btn-ghost btn-xs btn-square"
            phx-click="debug_step"
            title={dgettext("flows", "Step")}
            disabled={@debug_state.status in [:finished] or @debug_auto_playing}
          >
            <.icon name="play" class="size-3.5" />
          </button>
          <button
            type="button"
            class="btn btn-ghost btn-xs btn-square"
            phx-click="debug_step_back"
            title={dgettext("flows", "Step Back")}
            disabled={@debug_state.snapshots == [] or @debug_auto_playing}
          >
            <.icon name="undo-2" class="size-3.5" />
          </button>
          <button
            type="button"
            class="btn btn-ghost btn-xs btn-square"
            phx-click="debug_reset"
            title={dgettext("flows", "Reset")}
            disabled={@debug_auto_playing}
          >
            <.icon name="rotate-ccw" class="size-3.5" />
          </button>
          <div class="divider divider-horizontal mx-0.5 h-4"></div>
          <button
            type="button"
            class="btn btn-ghost btn-xs btn-square text-error"
            phx-click="debug_stop"
            title={dgettext("flows", "Stop")}
          >
            <.icon name="square" class="size-3.5" />
          </button>
        </div>

        <%!-- Status --%>
        <div class="flex-1 flex items-center gap-2">
          <span class={["badge badge-xs", status_badge_class(@debug_state.status)]}>
            {status_label(@debug_state.status)}
          </span>
          <span class="text-xs text-base-content/40 tabular-nums">
            {dgettext("flows", "Step %{count}", count: @debug_state.step_count)}
          </span>
          <.start_node_select
            start_node_id={@debug_state.start_node_id}
            debug_nodes={@debug_nodes}
            disabled={@debug_auto_playing}
          />
        </div>

        <%!-- Speed slider --%>
        <div class="flex items-center gap-1.5">
          <.icon name="gauge" class="size-3 text-base-content/30" />
          <input
            type="range"
            min="200"
            max="3000"
            step="100"
            value={@debug_speed}
            phx-change="debug_set_speed"
            name="speed"
            class="range range-xs w-16"
            title={dgettext("flows", "%{ms}ms per step", ms: @debug_speed)}
          />
          <span class="text-xs text-base-content/30 tabular-nums w-10">
            {format_speed(@debug_speed)}
          </span>
        </div>

        <%!-- Tabs --%>
        <div role="tablist" class="tabs tabs-boxed tabs-xs bg-base-200">
          <button
            type="button"
            role="tab"
            class={"tab #{if @debug_active_tab == "console", do: "tab-active"}"}
            phx-click="debug_tab_change"
            phx-value-tab="console"
          >
            {dgettext("flows", "Console")}
          </button>
          <button
            type="button"
            role="tab"
            class={"tab #{if @debug_active_tab == "variables", do: "tab-active"}"}
            phx-click="debug_tab_change"
            phx-value-tab="variables"
          >
            {dgettext("flows", "Variables")}
          </button>
          <button
            type="button"
            role="tab"
            class={"tab #{if @debug_active_tab == "history", do: "tab-active"}"}
            phx-click="debug_tab_change"
            phx-value-tab="history"
          >
            {dgettext("flows", "History")}
          </button>
          <button
            type="button"
            role="tab"
            class={"tab #{if @debug_active_tab == "path", do: "tab-active"}"}
            phx-click="debug_tab_change"
            phx-value-tab="path"
          >
            {dgettext("flows", "Path")}
          </button>
        </div>
      </div>

      <%!-- Tab content --%>
      <div class="flex-1 overflow-y-auto" id="debug-tab-content">
        <.console_tab
          :if={@debug_active_tab == "console"}
          console={@debug_state.console}
          pending_choices={@debug_state.pending_choices}
          status={@debug_state.status}
        />
        <.variables_tab
          :if={@debug_active_tab == "variables"}
          variables={@debug_state.variables}
          editing_var={@debug_editing_var}
          var_filter={@debug_var_filter}
          var_changed_only={@debug_var_changed_only}
        />
        <.history_tab
          :if={@debug_active_tab == "history"}
          history={@debug_state.history}
        />
        <.path_tab
          :if={@debug_active_tab == "path"}
          execution_log={@debug_state.execution_log}
          execution_path={@debug_state.execution_path}
          console={@debug_state.console}
          debug_nodes={@debug_nodes}
          breakpoints={@debug_state.breakpoints}
        />
      </div>
    </div>
    """
  end

  # ===========================================================================
  # Start node select
  # ===========================================================================

  attr :start_node_id, :integer, required: true
  attr :debug_nodes, :map, required: true
  attr :disabled, :boolean, default: false

  defp start_node_select(assigns) do
    nodes =
      assigns.debug_nodes
      |> Enum.map(fn {id, node} -> {id, node} end)
      |> Enum.sort_by(fn {_id, node} -> if node.type == "entry", do: 0, else: 1 end)

    assigns = Phoenix.Component.assign(assigns, :nodes, nodes)

    ~H"""
    <form phx-change="debug_change_start_node" class="flex items-center gap-1">
      <span class="text-xs text-base-content/30">{dgettext("flows", "Start:")}</span>
      <select
        name="node_id"
        class="select select-xs select-ghost text-xs h-6 min-h-0 pl-1 pr-5 font-normal"
        disabled={@disabled}
        title={dgettext("flows", "Change start node (resets session)")}
      >
        <option
          :for={{id, node} <- @nodes}
          value={id}
          selected={id == @start_node_id}
        >
          {start_node_label(node, id)}
        </option>
      </select>
    </form>
    """
  end

  defp start_node_label(node, id) do
    type_label = String.capitalize(node.type)
    data = node.data || %{}
    name = EvalHelpers.strip_html(data["text"], 20)

    if name do
      "#{type_label}: #{name}"
    else
      "#{type_label} ##{id}"
    end
  end

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp status_badge_class(:paused), do: "badge-info"
  defp status_badge_class(:waiting_input), do: "badge-warning"
  defp status_badge_class(:finished), do: "badge-neutral"
  defp status_badge_class(_), do: "badge-info"

  defp status_label(:paused), do: dgettext("flows", "Paused")
  defp status_label(:waiting_input), do: dgettext("flows", "Waiting")
  defp status_label(:finished), do: dgettext("flows", "Finished")
  defp status_label(_), do: ""

  defp format_speed(ms) when ms >= 1000, do: "#{Float.round(ms / 1000, 1)}s"
  defp format_speed(ms), do: "#{ms}ms"
end
