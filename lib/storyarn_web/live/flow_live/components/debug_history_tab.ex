defmodule StoryarnWeb.FlowLive.Components.DebugHistoryTab do
  @moduledoc """
  History and Path tab sub-components for the debug panel.

  Renders the variable change history tab and the execution path tab.
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents

  alias Storyarn.Flows.Evaluator.Helpers, as: EvalHelpers
  alias StoryarnWeb.FlowLive.NodeTypeRegistry

  # ===========================================================================
  # History tab
  # ===========================================================================

  attr :history, :list, required: true

  def history_tab(assigns) do
    assigns = Phoenix.Component.assign(assigns, :history, Enum.reverse(assigns.history))

    ~H"""
    <div class="text-xs">
      <table :if={@history != []} class="table table-xs table-pin-rows">
        <thead>
          <tr class="text-base-content/50">
            <th class="font-medium w-16">{dgettext("flows", "Time")}</th>
            <th class="font-medium">{dgettext("flows", "Node")}</th>
            <th class="font-medium">{dgettext("flows", "Change")}</th>
            <th class="font-medium w-14">{dgettext("flows", "Source")}</th>
          </tr>
        </thead>
        <tbody class="font-mono">
          <tr :for={entry <- @history} class="hover:bg-base-200">
            <td class="text-base-content/30 tabular-nums">{format_ts(entry.ts)}</td>
            <td class="truncate max-w-32" title={entry.node_label}>
              {if entry.node_label != "", do: entry.node_label, else: dgettext("flows", "(user override)")}
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
        {dgettext("flows", "No variable changes yet")}
      </div>
    </div>
    """
  end

  # ===========================================================================
  # Path tab
  # ===========================================================================

  attr :execution_log, :list, default: []
  attr :execution_path, :list, required: true
  attr :console, :list, required: true
  attr :debug_nodes, :map, required: true
  attr :breakpoints, :any, default: MapSet.new()

  def path_tab(assigns) do
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
        {dgettext("flows", "No steps yet")}
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
            {if entry.direction == :enter,
              do: dgettext("flows", "Entering sub-flow"),
              else: dgettext("flows", "Returned to parent")}
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
            title={
              if MapSet.member?(@breakpoints, entry.node_id),
                do: dgettext("flows", "Remove breakpoint"),
                else: dgettext("flows", "Set breakpoint")
            }
          >
            <span class={[
              "block rounded-full",
              if(MapSet.member?(@breakpoints, entry.node_id),
                do: "w-2.5 h-2.5 bg-error",
                else: "w-2 h-2 border border-base-content/20 hover:border-error/50"
              )
            ]}>
            </span>
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

  # ===========================================================================
  # Private helpers
  # ===========================================================================

  defp history_source_class(:instruction), do: "badge-warning"
  defp history_source_class(:user_override), do: "badge-info"
  defp history_source_class(_), do: "badge-ghost"

  defp history_source_label(:instruction), do: dgettext("flows", "instr")
  defp history_source_label(:user_override), do: dgettext("flows", "user")
  defp history_source_label(_), do: ""

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

  defp format_ts(ms) when is_integer(ms) do
    s = div(ms, 1000)
    ms_part = rem(ms, 1000)
    "#{s}.#{String.pad_leading(to_string(ms_part), 3, "0")}s"
  end

  defp format_ts(_), do: "0.000s"

  defp format_value(value), do: EvalHelpers.format_value(value)
end
