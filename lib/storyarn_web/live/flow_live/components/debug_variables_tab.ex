defmodule StoryarnWeb.FlowLive.Components.DebugVariablesTab do
  @moduledoc """
  Variables tab sub-component for the debug panel.

  Renders the variables table with filtering, change tracking, and inline editing.
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents

  alias Storyarn.Flows.Evaluator.Helpers, as: EvalHelpers

  # ===========================================================================
  # Variables tab
  # ===========================================================================

  attr :variables, :map, required: true
  attr :editing_var, :string, default: nil
  attr :var_filter, :string, default: ""
  attr :var_changed_only, :boolean, default: false

  def variables_tab(assigns) do
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
          <.icon
            name="search"
            class="size-3 absolute left-2 top-1/2 -translate-y-1/2 text-base-content/30"
          />
          <input
            type="text"
            name="filter"
            value={@var_filter}
            placeholder={dgettext("flows", "Filter variables...")}
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
          title={dgettext("flows", "Show only changed variables")}
        >
          <.icon name="diff" class="size-3" />
          {dgettext("flows", "Changed")}
        </button>
        <span class="text-xs text-base-content/30 tabular-nums ml-auto">
          {dgettext("flows", "%{shown} of %{total}", shown: @filtered_count, total: @total_count)}
        </span>
      </div>

      <table class="table table-xs table-pin-rows">
        <thead>
          <tr class="text-base-content/50">
            <th class="font-medium">{dgettext("flows", "Variable")}</th>
            <th class="font-medium w-16">{dgettext("flows", "Type")}</th>
            <th class="font-medium w-20 text-right">{dgettext("flows", "Initial")}</th>
            <th class="font-medium w-20 text-right">{dgettext("flows", "Previous")}</th>
            <th class="font-medium w-24 text-right">{dgettext("flows", "Current")}</th>
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
                  title={dgettext("flows", "Click to edit")}
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
        {dgettext("flows", "No variables in this project")}
      </div>
      <div
        :if={@sorted_vars == [] and @total_count > 0}
        class="flex items-center justify-center h-24 text-base-content/30"
      >
        {dgettext("flows", "No matching variables")}
      </div>
    </div>
    """
  end

  # ===========================================================================
  # Var edit input (3 clauses)
  # ===========================================================================

  attr :key, :string, required: true
  attr :var, :map, required: true

  def var_edit_input(%{var: %{block_type: "boolean"}} = assigns) do
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

  def var_edit_input(%{var: %{block_type: "number"}} = assigns) do
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

  def var_edit_input(assigns) do
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
  # Private helpers
  # ===========================================================================

  defp var_current_class(var) do
    if var.value != var.initial_value,
      do: var_source_color(var.source),
      else: "text-base-content/50"
  end

  defp var_source_color(:instruction), do: "text-warning"
  defp var_source_color(:user_override), do: "text-info"
  defp var_source_color(_), do: "text-base-content/50"

  defp format_value(value), do: EvalHelpers.format_value(value)
end
