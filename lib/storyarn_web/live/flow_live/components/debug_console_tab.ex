defmodule StoryarnWeb.FlowLive.Components.DebugConsoleTab do
  @moduledoc """
  Console tab sub-component for the debug panel.

  Renders the console log with level icons and response choices.
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents

  alias Storyarn.Flows.Evaluator.Helpers, as: EvalHelpers

  # ===========================================================================
  # Console tab
  # ===========================================================================

  attr :console, :list, required: true
  attr :pending_choices, :map, default: nil
  attr :status, :atom, required: true

  def console_tab(assigns) do
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
              {rule.variable_ref} {rule.operator} {rule.expected_value} → {if rule.passed,
                do: "pass",
                else: "fail"} (actual: {format_value(rule.actual_value)})
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
  # Level icon component
  # ===========================================================================

  attr :level, :atom, required: true

  def level_icon(%{level: :info} = assigns) do
    ~H"""
    <.icon name="info" class="size-3" />
    """
  end

  def level_icon(%{level: :warning} = assigns) do
    ~H"""
    <.icon name="triangle-alert" class="size-3" />
    """
  end

  def level_icon(%{level: :error} = assigns) do
    ~H"""
    <.icon name="circle-x" class="size-3" />
    """
  end

  def level_icon(assigns) do
    ~H"""
    <.icon name="info" class="size-3" />
    """
  end

  # ===========================================================================
  # Response choices
  # ===========================================================================

  attr :choices, :map, required: true

  defp response_choices(assigns) do
    ~H"""
    <div class="px-3 py-2 border-t border-base-300 bg-base-200/50">
      <p class="text-xs text-base-content/50 mb-1.5">{dgettext("flows", "Choose a response:")}</p>
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
          title={if(!resp.valid, do: dgettext("flows", "Condition not met"))}
        >
          {clean_response_text(resp.text)}
        </button>
      </div>
    </div>
    """
  end

  # ===========================================================================
  # Private helpers
  # ===========================================================================

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

  defp format_value(value), do: EvalHelpers.format_value(value)

  defp clean_response_text(text) when is_binary(text) do
    EvalHelpers.strip_html(text, 40) || dgettext("flows", "(empty)")
  end

  defp clean_response_text(_), do: dgettext("flows", "(empty)")
end
