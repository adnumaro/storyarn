defmodule StoryarnWeb.FlowLive.Components.DebugPanel do
  @moduledoc """
  Debug panel component for the flow editor.

  Renders a docked panel at the bottom of the canvas with:
  - Controls bar: Step, Step Back, Reset, Stop
  - Status indicator
  - Tabbed content area (Console, Variables)
  - Response choices when waiting for user input
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents

  alias Storyarn.Flows.Evaluator.Helpers, as: EvalHelpers
  alias StoryarnWeb.FlowLive.NodeTypeRegistry

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
    <div id="debug-panel" phx-hook="DebugPanelResize" class="bg-base-100 border-t border-base-300 flex flex-col" style="height: 280px;" data-debug-active>
      <%!-- Drag handle --%>
      <div
        data-resize-handle
        class="h-1 cursor-row-resize bg-transparent hover:bg-accent/30 transition-colors shrink-0"
      ></div>
      <%!-- Breadcrumb bar (sub-flow indicator) --%>
      <div
        :if={@debug_state.call_stack != []}
        class="flex items-center gap-1.5 px-3 py-1 bg-info/10 border-b border-info/20 text-xs text-info shrink-0"
      >
        <.icon name="layers" class="size-3 shrink-0" />
        <span :for={frame <- Enum.reverse(@debug_state.call_stack)} class="flex items-center gap-1">
          <span class="text-info/60">{frame[:flow_name] || gettext("Flow")}</span>
          <.icon name="chevron-right" class="size-2.5 text-info/40" />
        </span>
        <span class="font-medium">{@debug_current_flow_name || gettext("Current")}</span>
      </div>
      <%!-- Controls bar --%>
      <div class="flex items-center gap-2 px-3 py-1.5 border-b border-base-300 shrink-0">
        <div class="flex items-center gap-0.5">
          <button
            :if={!@debug_auto_playing}
            type="button"
            class="btn btn-ghost btn-xs btn-square"
            phx-click="debug_play"
            title={gettext("Auto-play")}
            disabled={@debug_state.status == :finished}
          >
            <.icon name="fast-forward" class="size-3.5" />
          </button>
          <button
            :if={@debug_auto_playing}
            type="button"
            class="btn btn-accent btn-xs btn-square"
            phx-click="debug_pause"
            title={gettext("Pause")}
          >
            <.icon name="pause" class="size-3.5" />
          </button>
          <div class="divider divider-horizontal mx-0.5 h-4"></div>
          <button
            type="button"
            class="btn btn-ghost btn-xs btn-square"
            phx-click="debug_step"
            title={gettext("Step")}
            disabled={@debug_state.status in [:finished] or @debug_auto_playing}
          >
            <.icon name="play" class="size-3.5" />
          </button>
          <button
            type="button"
            class="btn btn-ghost btn-xs btn-square"
            phx-click="debug_step_back"
            title={gettext("Step Back")}
            disabled={@debug_state.snapshots == [] or @debug_auto_playing}
          >
            <.icon name="undo-2" class="size-3.5" />
          </button>
          <button
            type="button"
            class="btn btn-ghost btn-xs btn-square"
            phx-click="debug_reset"
            title={gettext("Reset")}
            disabled={@debug_auto_playing}
          >
            <.icon name="rotate-ccw" class="size-3.5" />
          </button>
          <div class="divider divider-horizontal mx-0.5 h-4"></div>
          <button
            type="button"
            class="btn btn-ghost btn-xs btn-square text-error"
            phx-click="debug_stop"
            title={gettext("Stop")}
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
            {gettext("Step %{count}", count: @debug_state.step_count)}
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
            title={gettext("%{ms}ms per step", ms: @debug_speed)}
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
            {gettext("Console")}
          </button>
          <button
            type="button"
            role="tab"
            class={"tab #{if @debug_active_tab == "variables", do: "tab-active"}"}
            phx-click="debug_tab_change"
            phx-value-tab="variables"
          >
            {gettext("Variables")}
          </button>
          <button
            type="button"
            role="tab"
            class={"tab #{if @debug_active_tab == "history", do: "tab-active"}"}
            phx-click="debug_tab_change"
            phx-value-tab="history"
          >
            {gettext("History")}
          </button>
          <button
            type="button"
            role="tab"
            class={"tab #{if @debug_active_tab == "path", do: "tab-active"}"}
            phx-click="debug_tab_change"
            phx-value-tab="path"
          >
            {gettext("Path")}
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
      <span class="text-xs text-base-content/30">{gettext("Start:")}</span>
      <select
        name="node_id"
        class="select select-xs select-ghost text-xs h-6 min-h-0 pl-1 pr-5 font-normal"
        disabled={@disabled}
        title={gettext("Change start node (resets session)")}
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
  # Console tab
  # ===========================================================================

  attr :console, :list, required: true
  attr :pending_choices, :map, default: nil
  attr :status, :atom, required: true

  defp console_tab(assigns) do
    assigns = Phoenix.Component.assign(assigns, :console, Enum.reverse(assigns.console))

    ~H"""
    <div class="font-mono text-xs">
      <div
        :for={entry <- @console}
        class={["flex items-start gap-2 px-3 py-0.5 hover:bg-base-200", level_bg(entry.level)]}
      >
        <span class="text-base-content/30 shrink-0 w-14 text-right tabular-nums select-none">
          {format_ts(entry.ts)}
        </span>
        <span class={["shrink-0 mt-0.5", level_color(entry.level)]}>
          <.level_icon level={entry.level} />
        </span>
        <span
          :if={entry.node_label != ""}
          class="text-primary/60 shrink-0 max-w-28 truncate"
          title={entry.node_label}
        >
          {entry.node_label}
        </span>
        <span class="flex-1 break-all">
          {entry.message}
          <div :if={entry.rule_details && entry.rule_details != []} class="mt-0.5">
            <div :for={rule <- entry.rule_details} class="text-[10px] text-base-content/40">
              {rule.variable_ref} {rule.operator} {rule.expected_value}
              → {if rule.passed, do: "pass", else: "fail"} (actual: {format_value(rule.actual_value)})
            </div>
          </div>
        </span>
      </div>

      <%!-- Response choices --%>
      <.response_choices
        :if={@status == :waiting_input and not is_nil(@pending_choices)}
        choices={@pending_choices}
      />
    </div>
    """
  end

  # ===========================================================================
  # Variables tab
  # ===========================================================================

  attr :variables, :map, required: true
  attr :editing_var, :string, default: nil
  attr :var_filter, :string, default: ""
  attr :var_changed_only, :boolean, default: false

  defp variables_tab(assigns) do
    all_vars = assigns.variables
    filter = String.downcase(assigns.var_filter)
    changed_only = assigns.var_changed_only

    filtered =
      all_vars
      |> Enum.filter(fn {key, var} ->
        matches_filter = filter == "" or String.contains?(String.downcase(key), filter)
        matches_changed = !changed_only or var.value != var.initial_value
        matches_filter and matches_changed
      end)
      |> Enum.sort_by(fn {key, _} -> key end)

    assigns =
      assigns
      |> Phoenix.Component.assign(:sorted_vars, filtered)
      |> Phoenix.Component.assign(:total_count, map_size(all_vars))
      |> Phoenix.Component.assign(:filtered_count, length(filtered))

    ~H"""
    <div class="text-xs">
      <%!-- Filter bar --%>
      <div class="flex items-center gap-2 px-3 py-1.5 border-b border-base-300 bg-base-200/30">
        <div class="relative flex-1 max-w-48">
          <.icon name="search" class="size-3 absolute left-2 top-1/2 -translate-y-1/2 text-base-content/30" />
          <input
            type="text"
            name="filter"
            value={@var_filter}
            placeholder={gettext("Filter variables...")}
            phx-change="debug_var_filter"
            phx-debounce="150"
            class="input input-xs input-bordered w-full pl-7"
          />
        </div>
        <button
          type="button"
          class={[
            "btn btn-xs gap-1",
            if(@var_changed_only, do: "btn-accent", else: "btn-ghost")
          ]}
          phx-click="debug_var_toggle_changed"
          title={gettext("Show only changed variables")}
        >
          <.icon name="diff" class="size-3" />
          {gettext("Changed")}
        </button>
        <span class="text-xs text-base-content/30 tabular-nums ml-auto">
          {gettext("%{shown} of %{total}", shown: @filtered_count, total: @total_count)}
        </span>
      </div>

      <table class="table table-xs table-pin-rows">
        <thead>
          <tr class="text-base-content/50">
            <th class="font-medium">{gettext("Variable")}</th>
            <th class="font-medium w-16">{gettext("Type")}</th>
            <th class="font-medium w-20 text-right">{gettext("Initial")}</th>
            <th class="font-medium w-20 text-right">{gettext("Previous")}</th>
            <th class="font-medium w-24 text-right">{gettext("Current")}</th>
          </tr>
        </thead>
        <tbody class="font-mono">
          <tr :for={{key, var} <- @sorted_vars} class="hover:bg-base-200">
            <td class="truncate max-w-48" title={key}>
              <span class="text-base-content/40">{var.sheet_shortcut}.</span>{var.variable_name}
            </td>
            <td>
              <span class="badge badge-xs badge-ghost font-sans">{var.block_type}</span>
            </td>
            <td class="text-right text-base-content/50 tabular-nums">
              {format_value(var.initial_value)}
            </td>
            <td class="text-right text-base-content/50 tabular-nums">
              {format_value(var.previous_value)}
            </td>
            <td class={["text-right tabular-nums", var_current_class(var)]}>
              <%= if @editing_var == key do %>
                <.var_edit_input key={key} var={var} />
              <% else %>
                <div
                  class="cursor-pointer hover:bg-base-300 rounded px-1 -mx-1"
                  phx-click="debug_edit_variable"
                  phx-value-key={key}
                  title={gettext("Click to edit")}
                >
                  <span :if={var.value != var.initial_value} class={var_source_color(var.source)}>
                    ◆
                  </span>
                  <span class={if var.value != var.initial_value, do: "font-bold"}>
                    {format_value(var.value)}
                  </span>
                </div>
              <% end %>
            </td>
          </tr>
        </tbody>
      </table>

      <div
        :if={@sorted_vars == [] and @total_count == 0}
        class="flex items-center justify-center h-24 text-base-content/30"
      >
        {gettext("No variables in this project")}
      </div>
      <div
        :if={@sorted_vars == [] and @total_count > 0}
        class="flex items-center justify-center h-24 text-base-content/30"
      >
        {gettext("No matching variables")}
      </div>
    </div>
    """
  end

  attr :key, :string, required: true
  attr :var, :map, required: true

  defp var_edit_input(%{var: %{block_type: "boolean"}} = assigns) do
    ~H"""
    <select
      name="value"
      class="select select-xs select-bordered w-full text-right text-info"
      phx-change="debug_set_variable"
      phx-value-key={@key}
      autofocus
      phx-key="Escape"
      phx-keydown="debug_cancel_edit"
    >
      <option value="true" selected={@var.value == true}>true</option>
      <option value="false" selected={@var.value != true}>false</option>
    </select>
    """
  end

  defp var_edit_input(%{var: %{block_type: "number"}} = assigns) do
    ~H"""
    <form phx-submit="debug_set_variable" phx-value-key={@key} class="flex">
      <input
        type="number"
        name="value"
        value={@var.value}
        step="any"
        class="input input-xs input-bordered w-full text-right text-info tabular-nums"
        autofocus
        phx-blur="debug_set_variable"
        phx-value-key={@key}
        phx-key="Escape"
        phx-keydown="debug_cancel_edit"
      />
    </form>
    """
  end

  defp var_edit_input(assigns) do
    ~H"""
    <form phx-submit="debug_set_variable" phx-value-key={@key} class="flex">
      <input
        type="text"
        name="value"
        value={@var.value}
        class="input input-xs input-bordered w-full text-right text-info"
        autofocus
        phx-blur="debug_set_variable"
        phx-value-key={@key}
        phx-key="Escape"
        phx-keydown="debug_cancel_edit"
      />
    </form>
    """
  end

  # ===========================================================================
  # History tab
  # ===========================================================================

  attr :history, :list, required: true

  defp history_tab(assigns) do
    assigns = Phoenix.Component.assign(assigns, :history, Enum.reverse(assigns.history))

    ~H"""
    <div class="text-xs">
      <table :if={@history != []} class="table table-xs table-pin-rows">
        <thead>
          <tr class="text-base-content/50">
            <th class="font-medium w-16">{gettext("Time")}</th>
            <th class="font-medium">{gettext("Node")}</th>
            <th class="font-medium">{gettext("Change")}</th>
            <th class="font-medium w-14">{gettext("Source")}</th>
          </tr>
        </thead>
        <tbody class="font-mono">
          <tr :for={entry <- @history} class="hover:bg-base-200">
            <td class="text-base-content/30 tabular-nums">{format_ts(entry.ts)}</td>
            <td class="truncate max-w-32" title={entry.node_label}>
              {if entry.node_label != "", do: entry.node_label, else: gettext("(user override)")}
            </td>
            <td class="truncate max-w-64">
              <span class="text-base-content/40">{entry.variable_ref}:</span>
              <span>{format_value(entry.old_value)}</span>
              <span class="text-base-content/30">→</span>
              <span class="font-bold">{format_value(entry.new_value)}</span>
            </td>
            <td>
              <span class={["badge badge-xs", history_source_class(entry.source)]}>
                {history_source_label(entry.source)}
              </span>
            </td>
          </tr>
        </tbody>
      </table>

      <div :if={@history == []} class="flex items-center justify-center h-24 text-base-content/30">
        {gettext("No variable changes yet")}
      </div>
    </div>
    """
  end

  defp history_source_class(:instruction), do: "badge-warning"
  defp history_source_class(:user_override), do: "badge-info"
  defp history_source_class(_), do: "badge-ghost"

  defp history_source_label(:instruction), do: gettext("instr")
  defp history_source_label(:user_override), do: gettext("user")
  defp history_source_label(_), do: ""

  # ===========================================================================
  # Path tab
  # ===========================================================================

  attr :execution_log, :list, default: []
  attr :execution_path, :list, required: true
  attr :console, :list, required: true
  attr :debug_nodes, :map, required: true
  attr :breakpoints, :any, default: MapSet.new()

  defp path_tab(assigns) do
    log =
      if assigns.execution_log != [] do
        Enum.reverse(assigns.execution_log)
      else
        Enum.reverse(assigns.execution_path)
        |> Enum.map(fn node_id -> %{node_id: node_id, depth: 0} end)
      end

    console = Enum.reverse(assigns.console)
    entries = build_path_entries(log, assigns.debug_nodes, console)
    assigns = Phoenix.Component.assign(assigns, :entries, entries)

    ~H"""
    <div class="text-xs">
      <div :if={@entries == []} class="flex items-center justify-center h-24 text-base-content/30">
        {gettext("No steps yet")}
      </div>
      <div :for={entry <- @entries} class="contents">
        <%!-- Flow separator --%>
        <div
          :if={entry[:separator]}
          class="flex items-center gap-2 px-3 py-0.5 text-info/50 select-none"
        >
          <div class="flex-1 border-t border-info/20"></div>
          <.icon
            name={if entry.direction == :enter, do: "arrow-down-right", else: "arrow-up-left"}
            class="size-3"
          />
          <span class="text-[10px]">
            {if entry.direction == :enter, do: gettext("Entering sub-flow"), else: gettext("Returned to parent")}
          </span>
          <div class="flex-1 border-t border-info/20"></div>
        </div>
        <%!-- Normal path entry --%>
        <div
          :if={!entry[:separator]}
          class={[
            "flex items-center gap-2 py-1 pr-3",
            if(entry.is_current, do: "text-primary font-bold bg-primary/5", else: "hover:bg-base-200")
          ]}
          style={"padding-left: #{12 + entry.depth * 16}px"}
        >
          <button
            type="button"
            class="shrink-0 flex items-center justify-center w-3 h-3"
            phx-click="debug_toggle_breakpoint"
            phx-value-node_id={entry.node_id}
            title={if MapSet.member?(@breakpoints, entry.node_id), do: gettext("Remove breakpoint"), else: gettext("Set breakpoint")}
          >
            <span class={[
              "block rounded-full",
              if(MapSet.member?(@breakpoints, entry.node_id),
                do: "w-2.5 h-2.5 bg-error",
                else: "w-2 h-2 border border-base-content/20 hover:border-error/50"
              )
            ]}></span>
          </button>
          <span class="text-base-content/30 w-5 text-right tabular-nums shrink-0 select-none">
            {entry.step}
          </span>
          <.icon name={path_icon(entry.type)} class="size-3 shrink-0 opacity-60" />
          <span :if={entry.label} class="truncate max-w-32">
            {entry.label}
          </span>
          <span class="text-base-content/30 shrink-0">→</span>
          <span class="truncate flex-1 text-base-content/50 font-normal">
            {entry.outcome || ""}
          </span>
        </div>
      </div>
    </div>
    """
  end

  @doc false
  def build_path_entries(execution_log, nodes, console) do
    node_entries = Enum.filter(console, fn e -> e.node_id != nil end)
    log_length = length(execution_log)

    {entries, _remaining, _prev_depth} =
      execution_log
      |> Enum.with_index(1)
      |> Enum.reduce({[], node_entries, 0}, fn {log_entry, step}, {acc, remaining, prev_depth} ->
        node_id = log_entry.node_id
        depth = log_entry.depth

        # Insert separator when depth changes
        separators =
          cond do
            depth > prev_depth ->
              [%{separator: true, direction: :enter, depth: depth}]

            depth < prev_depth ->
              [%{separator: true, direction: :return, depth: depth}]

            true ->
              []
          end

        node = Map.get(nodes, node_id)
        {outcome, rest} = pop_first_match(remaining, node_id)

        entry = %{
          step: step,
          node_id: node_id,
          type: (node && node.type) || "unknown",
          label: path_node_label(node),
          outcome: outcome,
          is_current: step == log_length,
          depth: depth
        }

        {acc ++ separators ++ [entry], rest, depth}
      end)

    entries
  end

  defp pop_first_match([], _node_id), do: {nil, []}

  defp pop_first_match([entry | rest], node_id) do
    if entry.node_id == node_id do
      {entry.message, rest}
    else
      {found, remaining} = pop_first_match(rest, node_id)
      {found, [entry | remaining]}
    end
  end

  defp path_node_label(nil), do: nil

  defp path_node_label(node) do
    data = node.data || %{}
    text = data["text"]
    if is_binary(text) and text != "", do: EvalHelpers.strip_html(text, 30)
  end

  defp path_icon(type), do: NodeTypeRegistry.icon_name(type)

  # ===========================================================================
  # Response choices
  # ===========================================================================

  attr :choices, :map, required: true

  defp response_choices(assigns) do
    ~H"""
    <div class="px-3 py-2 border-t border-base-300 bg-base-200/50">
      <p class="text-xs text-base-content/50 mb-1.5">{gettext("Choose a response:")}</p>
      <div class="flex flex-wrap gap-1.5">
        <button
          :for={resp <- @choices.responses}
          type="button"
          class={[
            "btn btn-xs",
            if(resp.valid, do: "btn-primary btn-outline", else: "btn-ghost opacity-40 line-through")
          ]}
          phx-click="debug_choose_response"
          phx-value-id={resp.id}
          disabled={!resp.valid}
          title={if(!resp.valid, do: gettext("Condition not met"))}
        >
          {clean_response_text(resp.text)}
        </button>
      </div>
    </div>
    """
  end

  # ===========================================================================
  # Level icon component
  # ===========================================================================

  attr :level, :atom, required: true

  defp level_icon(%{level: :info} = assigns) do
    ~H"""
    <.icon name="info" class="size-3" />
    """
  end

  defp level_icon(%{level: :warning} = assigns) do
    ~H"""
    <.icon name="triangle-alert" class="size-3" />
    """
  end

  defp level_icon(%{level: :error} = assigns) do
    ~H"""
    <.icon name="circle-x" class="size-3" />
    """
  end

  defp level_icon(assigns) do
    ~H"""
    <.icon name="info" class="size-3" />
    """
  end

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp status_badge_class(:paused), do: "badge-info"
  defp status_badge_class(:waiting_input), do: "badge-warning"
  defp status_badge_class(:finished), do: "badge-neutral"
  defp status_badge_class(_), do: "badge-info"

  defp status_label(:paused), do: gettext("Paused")
  defp status_label(:waiting_input), do: gettext("Waiting")
  defp status_label(:finished), do: gettext("Finished")
  defp status_label(_), do: ""

  defp level_bg(:warning), do: "bg-warning/5"
  defp level_bg(:error), do: "bg-error/5"
  defp level_bg(_), do: ""

  defp level_color(:info), do: "text-info"
  defp level_color(:warning), do: "text-warning"
  defp level_color(:error), do: "text-error"
  defp level_color(_), do: "text-base-content/40"

  defp format_speed(ms) when ms >= 1000, do: "#{Float.round(ms / 1000, 1)}s"
  defp format_speed(ms), do: "#{ms}ms"

  defp format_ts(ms) when is_integer(ms) do
    s = div(ms, 1000)
    ms_part = rem(ms, 1000)
    "#{s}.#{String.pad_leading(to_string(ms_part), 3, "0")}s"
  end

  defp format_ts(_), do: "0.000s"

  # -- Variable helpers --

  defp var_current_class(var) do
    if var.value != var.initial_value, do: var_source_color(var.source), else: "text-base-content/50"
  end

  defp var_source_color(:instruction), do: "text-warning"
  defp var_source_color(:user_override), do: "text-info"
  defp var_source_color(_), do: "text-base-content/50"

  defp format_value(value), do: EvalHelpers.format_value(value)

  defp clean_response_text(text) when is_binary(text) do
    EvalHelpers.strip_html(text, 40) || gettext("(empty)")
  end

  defp clean_response_text(_), do: gettext("(empty)")
end
