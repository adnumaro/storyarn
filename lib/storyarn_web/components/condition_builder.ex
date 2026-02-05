defmodule StoryarnWeb.Components.ConditionBuilder do
  @moduledoc """
  Visual condition builder component for dialogue responses.

  Provides a UI to build compound conditions with AND/OR logic:
  - Toggle between ALL (AND) and ANY (OR) logic
  - Add/remove condition rules
  - Select page, variable, operator, and value for each rule
  - Type-aware operator and value inputs

  ## Usage

      <.condition_builder
        condition={@condition}
        variables={@project_variables}
        on_change="update_condition"
        target={@myself}
        can_edit={@can_edit}
      />

  The component emits events:
  - `update_condition` with %{action: :set_logic | :add_rule | :remove_rule | :update_rule, ...}
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents, only: [icon: 1]

  alias Storyarn.Flows.Condition

  # =============================================================================
  # Main Component
  # =============================================================================

  @doc """
  Renders the condition builder UI.
  """
  attr :id, :string, required: true
  attr :condition, :map, default: nil
  attr :variables, :list, default: []
  attr :on_change, :string, required: true
  attr :target, :any, default: nil
  attr :can_edit, :boolean, default: true
  attr :show_expression_toggle, :boolean, default: true
  attr :expression_mode, :boolean, default: false
  attr :raw_expression, :string, default: ""

  def condition_builder(assigns) do
    # Parse condition if it's a string
    parsed_condition =
      case assigns.condition do
        nil -> Condition.new()
        %{"logic" => _, "rules" => _} = cond -> cond
        :legacy -> Condition.new()
        _string -> Condition.new()
      end

    # Group variables by page for the dropdown
    pages_with_variables = group_variables_by_page(assigns.variables)

    assigns =
      assigns
      |> assign(:parsed_condition, parsed_condition)
      |> assign(:pages_with_variables, pages_with_variables)

    ~H"""
    <div id={@id} class="space-y-3">
      <%!-- Expression mode toggle --%>
      <div :if={@show_expression_toggle && @can_edit} class="flex items-center justify-end">
        <label class="flex items-center gap-2 cursor-pointer text-xs text-base-content/60">
          <input
            type="checkbox"
            class="toggle toggle-xs"
            checked={@expression_mode}
            phx-click={@on_change}
            phx-value-action="toggle_expression_mode"
            phx-target={@target}
          />
          <span>{gettext("Expression mode")}</span>
        </label>
      </div>

      <%!-- Expression mode: raw text input --%>
      <div :if={@expression_mode}>
        <input
          type="text"
          value={@raw_expression}
          phx-blur={@on_change}
          phx-value-action="set_expression"
          phx-target={@target}
          disabled={!@can_edit}
          placeholder={gettext("e.g., player.level > 5")}
          class="input input-sm input-bordered w-full font-mono text-xs"
        />
        <p class="text-xs text-base-content/50 mt-1">
          {gettext("Advanced: enter a raw condition expression.")}
        </p>
      </div>

      <%!-- Visual builder mode - wrapped in form for phx-change to work --%>
      <form :if={!@expression_mode} phx-change={@on_change} phx-target={@target} class="space-y-3">
        <%!-- Logic toggle --%>
        <div class="flex items-center gap-2 text-sm">
          <span class="text-base-content/70">{gettext("Match")}</span>
          <select
            class="select select-xs select-bordered"
            name="logic"
            disabled={!@can_edit || length(@parsed_condition["rules"]) < 2}
          >
            <option value="all" selected={@parsed_condition["logic"] == "all"}>
              {gettext("all")}
            </option>
            <option value="any" selected={@parsed_condition["logic"] == "any"}>
              {gettext("any")}
            </option>
          </select>
          <span class="text-base-content/70">{gettext("of the following:")}</span>
        </div>

        <%!-- Rules --%>
        <div class="space-y-2">
          <.condition_rule
            :for={rule <- @parsed_condition["rules"]}
            rule={rule}
            pages_with_variables={@pages_with_variables}
            variables={@variables}
            on_change={@on_change}
            target={@target}
            can_edit={@can_edit}
          />
        </div>

        <%!-- Add rule button --%>
        <button
          :if={@can_edit}
          type="button"
          phx-click={@on_change}
          phx-value-action="add_rule"
          phx-target={@target}
          class="btn btn-ghost btn-xs gap-1 border border-dashed border-base-300"
        >
          <.icon name="plus" class="size-3" />
          {gettext("Add condition")}
        </button>

        <%!-- Empty state --%>
        <p
          :if={@parsed_condition["rules"] == [] && !@can_edit}
          class="text-xs text-base-content/50 italic"
        >
          {gettext("No conditions set")}
        </p>
      </form>
    </div>
    """
  end

  # =============================================================================
  # Sub-components
  # =============================================================================

  attr :rule, :map, required: true
  attr :pages_with_variables, :list, default: []
  attr :variables, :list, default: []
  attr :on_change, :string, required: true
  attr :target, :any, default: nil
  attr :can_edit, :boolean, default: true

  defp condition_rule(assigns) do
    # Find the selected variable to get its type and options
    selected_var = find_variable(assigns.variables, assigns.rule["page"], assigns.rule["variable"])

    # Get operators for the variable type
    var_type = if selected_var, do: selected_var.block_type, else: "text"
    operators = Condition.operators_for_type(var_type)

    # Get options for select types
    select_options = if selected_var, do: selected_var[:options] || [], else: []

    # Check if value input is needed
    show_value = Condition.operator_requires_value?(assigns.rule["operator"])

    assigns =
      assigns
      |> assign(:selected_var, selected_var)
      |> assign(:var_type, var_type)
      |> assign(:operators, operators)
      |> assign(:select_options, select_options)
      |> assign(:show_value, show_value)

    ~H"""
    <div class="flex items-start gap-2 p-2 bg-base-200 rounded-lg">
      <div class="flex-1 grid grid-cols-2 gap-2">
        <%!-- Page selector --%>
        <select
          class="select select-xs select-bordered w-full"
          name={"rule_page_#{@rule["id"]}"}
          disabled={!@can_edit}
        >
          <option value="">{gettext("Select page...")}</option>
          <option
            :for={{page_shortcut, page_name, _vars} <- @pages_with_variables}
            value={page_shortcut}
            selected={@rule["page"] == page_shortcut}
          >
            {page_name} ({page_shortcut})
          </option>
        </select>

        <%!-- Variable selector --%>
        <select
          class="select select-xs select-bordered w-full"
          name={"rule_variable_#{@rule["id"]}"}
          disabled={!@can_edit || is_nil(@rule["page"]) || @rule["page"] == ""}
        >
          <option value="">{gettext("Select variable...")}</option>
          <%= for {page_shortcut, _page_name, vars} <- @pages_with_variables,
                  page_shortcut == @rule["page"],
                  var <- vars do %>
            <option value={var.variable_name} selected={@rule["variable"] == var.variable_name}>
              {var.variable_name} ({variable_type_label(var.block_type)})
            </option>
          <% end %>
        </select>

        <%!-- Operator selector --%>
        <select
          class="select select-xs select-bordered"
          name={"rule_operator_#{@rule["id"]}"}
          disabled={!@can_edit || is_nil(@rule["variable"]) || @rule["variable"] == ""}
        >
          <option
            :for={op <- @operators}
            value={op}
            selected={@rule["operator"] == op}
          >
            {Condition.operator_label(op)}
          </option>
        </select>

        <%!-- Value input (type-aware) --%>
        <.value_input
          :if={@show_value}
          rule={@rule}
          var_type={@var_type}
          select_options={@select_options}
          on_change={@on_change}
          target={@target}
          can_edit={@can_edit}
        />
        <div :if={!@show_value} class="h-6"></div>
      </div>

      <%!-- Remove button --%>
      <button
        :if={@can_edit}
        type="button"
        phx-click={@on_change}
        phx-value-action="remove_rule"
        phx-value-rule-id={@rule["id"]}
        phx-target={@target}
        class="btn btn-ghost btn-xs btn-square text-error flex-shrink-0"
        title={gettext("Remove condition")}
      >
        <.icon name="x" class="size-3" />
      </button>
    </div>
    """
  end

  attr :rule, :map, required: true
  attr :var_type, :string, required: true
  attr :select_options, :list, default: []
  attr :on_change, :string, required: true
  attr :target, :any, default: nil
  attr :can_edit, :boolean, default: true

  defp value_input(%{var_type: "select"} = assigns) do
    ~H"""
    <select
      class="select select-xs select-bordered w-full"
      name={"rule_value_#{@rule["id"]}"}
      disabled={!@can_edit}
    >
      <option value="">{gettext("Select value...")}</option>
      <option
        :for={opt <- @select_options}
        value={opt["key"]}
        selected={@rule["value"] == opt["key"]}
      >
        {opt["value"]}
      </option>
    </select>
    """
  end

  defp value_input(%{var_type: "multi_select"} = assigns) do
    ~H"""
    <select
      class="select select-xs select-bordered w-full"
      name={"rule_value_#{@rule["id"]}"}
      disabled={!@can_edit}
    >
      <option value="">{gettext("Select value...")}</option>
      <option
        :for={opt <- @select_options}
        value={opt["key"]}
        selected={@rule["value"] == opt["key"]}
      >
        {opt["value"]}
      </option>
    </select>
    """
  end

  defp value_input(%{var_type: "number"} = assigns) do
    ~H"""
    <input
      type="number"
      value={@rule["value"]}
      name={"rule_value_#{@rule["id"]}"}
      disabled={!@can_edit}
      placeholder="0"
      class="input input-xs input-bordered w-full"
    />
    """
  end

  defp value_input(%{var_type: "boolean"} = assigns) do
    ~H"""
    <select
      class="select select-xs select-bordered w-full"
      name={"rule_value_#{@rule["id"]}"}
      disabled={!@can_edit}
    >
      <option value="true" selected={@rule["value"] == "true" || @rule["value"] == true}>
        {gettext("true")}
      </option>
      <option value="false" selected={@rule["value"] == "false" || @rule["value"] == false}>
        {gettext("false")}
      </option>
    </select>
    """
  end

  defp value_input(%{var_type: "date"} = assigns) do
    ~H"""
    <input
      type="date"
      value={@rule["value"]}
      name={"rule_value_#{@rule["id"]}"}
      disabled={!@can_edit}
      class="input input-xs input-bordered w-full"
    />
    """
  end

  defp value_input(assigns) do
    # Default: text input
    ~H"""
    <input
      type="text"
      value={@rule["value"]}
      name={"rule_value_#{@rule["id"]}"}
      disabled={!@can_edit}
      placeholder={gettext("value")}
      class="input input-xs input-bordered w-full"
    />
    """
  end

  # =============================================================================
  # Helpers
  # =============================================================================

  @doc """
  Groups variables by page for the dropdown.
  Returns a list of {page_shortcut, page_name, [variables]}.
  """
  def group_variables_by_page(variables) do
    variables
    |> Enum.group_by(fn var -> {var.page_shortcut, var.page_name} end)
    |> Enum.map(fn {{shortcut, name}, vars} ->
      {shortcut, name, vars}
    end)
    |> Enum.sort_by(fn {_shortcut, name, _vars} -> name end)
  end

  @doc """
  Finds a variable by page shortcut and variable name.
  """
  def find_variable(variables, page_shortcut, variable_name)
      when is_binary(page_shortcut) and is_binary(variable_name) do
    Enum.find(variables, fn var ->
      var.page_shortcut == page_shortcut and var.variable_name == variable_name
    end)
  end

  def find_variable(_variables, _page_shortcut, _variable_name), do: nil

  defp variable_type_label("text"), do: "text"
  defp variable_type_label("rich_text"), do: "text"
  defp variable_type_label("number"), do: "num"
  defp variable_type_label("boolean"), do: "bool"
  defp variable_type_label("select"), do: "select"
  defp variable_type_label("multi_select"), do: "multi"
  defp variable_type_label("date"), do: "date"
  defp variable_type_label(type), do: type
end
