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

  # ===========================================================================
  # Main panel
  # ===========================================================================

  attr :debug_state, :map, required: true
  attr :debug_active_tab, :string, default: "console"

  def debug_panel(assigns) do
    ~H"""
    <div class="bg-base-100 border-t border-base-300 flex flex-col" style="height: 280px;">
      <%!-- Controls bar --%>
      <div class="flex items-center gap-2 px-3 py-1.5 border-b border-base-300 shrink-0">
        <div class="flex items-center gap-0.5">
          <button
            type="button"
            class="btn btn-ghost btn-xs btn-square"
            phx-click="debug_step"
            title={gettext("Step")}
            disabled={@debug_state.status in [:finished]}
          >
            <.icon name="play" class="size-3.5" />
          </button>
          <button
            type="button"
            class="btn btn-ghost btn-xs btn-square"
            phx-click="debug_step_back"
            title={gettext("Step Back")}
            disabled={@debug_state.snapshots == []}
          >
            <.icon name="undo-2" class="size-3.5" />
          </button>
          <button
            type="button"
            class="btn btn-ghost btn-xs btn-square"
            phx-click="debug_reset"
            title={gettext("Reset")}
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
        />
      </div>
    </div>
    """
  end

  # ===========================================================================
  # Console tab
  # ===========================================================================

  attr :console, :list, required: true
  attr :pending_choices, :map, default: nil
  attr :status, :atom, required: true

  defp console_tab(assigns) do
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
        <span class="flex-1 break-all">{entry.message}</span>
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

  defp variables_tab(assigns) do
    sorted =
      assigns.variables
      |> Enum.sort_by(fn {key, _} -> key end)

    assigns = Phoenix.Component.assign(assigns, :sorted_vars, sorted)

    ~H"""
    <div class="text-xs">
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
              <span :if={var.value != var.initial_value} class={var_source_color(var.source)}>
                ◆
              </span>
              <span class={if var.value != var.initial_value, do: "font-bold"}>
                {format_value(var.value)}
              </span>
            </td>
          </tr>
        </tbody>
      </table>

      <div :if={@sorted_vars == []} class="flex items-center justify-center h-24 text-base-content/30">
        {gettext("No variables in this project")}
      </div>
    </div>
    """
  end

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

  defp format_value(nil), do: "nil"
  defp format_value(true), do: "true"
  defp format_value(false), do: "false"
  defp format_value(val) when is_list(val), do: Enum.join(val, ", ")
  defp format_value(val) when is_binary(val) and byte_size(val) > 30, do: String.slice(val, 0, 30) <> "..."
  defp format_value(val) when is_binary(val), do: val
  defp format_value(val), do: to_string(val)

  defp clean_response_text(text) when is_binary(text) do
    text
    |> String.replace(~r/<[^>]*>/, "")
    |> String.trim()
    |> String.slice(0, 40)
    |> case do
      "" -> gettext("(empty)")
      clean -> clean
    end
  end

  defp clean_response_text(_), do: gettext("(empty)")
end
