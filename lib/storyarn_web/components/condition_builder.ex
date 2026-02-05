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
  attr :wrap_in_form, :boolean, default: false
  attr :context, :map, default: %{}
  attr :switch_mode, :boolean, default: false

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
    <%= if @wrap_in_form do %>
      <form
        id={@id}
        phx-change={@on_change}
        phx-target={@target}
        onsubmit="return false"
        class="space-y-3"
      >
        <.context_hidden_inputs context={@context} />
        <.condition_builder_content
          parsed_condition={@parsed_condition}
          pages_with_variables={@pages_with_variables}
          variables={@variables}
          on_change={@on_change}
          target={@target}
          can_edit={@can_edit}
          show_expression_toggle={@show_expression_toggle}
          expression_mode={@expression_mode}
          raw_expression={@raw_expression}
          context={@context}
          switch_mode={@switch_mode}
        />
      </form>
    <% else %>
      <div id={@id} class="space-y-3">
        <.context_hidden_inputs context={@context} />
        <.condition_builder_content
          parsed_condition={@parsed_condition}
          pages_with_variables={@pages_with_variables}
          variables={@variables}
          on_change={@on_change}
          target={@target}
          can_edit={@can_edit}
          show_expression_toggle={@show_expression_toggle}
          expression_mode={@expression_mode}
          raw_expression={@raw_expression}
          context={@context}
          switch_mode={@switch_mode}
        />
      </div>
    <% end %>
    """
  end

  # Renders hidden inputs for context data (e.g., response_id, node_id)
  attr :context, :map, default: %{}

  defp context_hidden_inputs(assigns) do
    ~H"""
    <input :for={{key, value} <- @context} type="hidden" name={key} value={value} />
    """
  end

  # Inner component to avoid duplication
  attr :parsed_condition, :map, required: true
  attr :pages_with_variables, :list, default: []
  attr :variables, :list, default: []
  attr :on_change, :string, required: true
  attr :target, :any, default: nil
  attr :can_edit, :boolean, default: true
  attr :show_expression_toggle, :boolean, default: true
  attr :expression_mode, :boolean, default: false
  attr :raw_expression, :string, default: ""
  attr :context, :map, default: %{}
  attr :switch_mode, :boolean, default: false

  defp condition_builder_content(assigns) do
    ~H"""
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
        name="raw_expression"
        value={@raw_expression}
        disabled={!@can_edit}
        placeholder={gettext("e.g., player.level > 5")}
        class="input input-sm input-bordered w-full font-mono text-xs"
      />
      <input type="hidden" name="action" value="set_expression" />
      <p class="text-xs text-base-content/50 mt-1">
        {gettext("Advanced: enter a raw condition expression.")}
      </p>
    </div>

    <%!-- Visual builder mode --%>
    <div :if={!@expression_mode} class="space-y-3">
      <%!-- Logic toggle (only show when 2+ rules AND not in switch mode) --%>
      <div
        :if={length(@parsed_condition["rules"]) >= 2 && !@switch_mode}
        class="flex items-center gap-2 text-xs"
      >
        <span class="text-base-content/60">{gettext("Match")}</span>
        <div class="join">
          <button
            type="button"
            class={["join-item btn btn-xs", @parsed_condition["logic"] == "all" && "btn-active"]}
            phx-click={@on_change}
            phx-value-logic="all"
            {context_phx_values(@context)}
            phx-target={@target}
            disabled={!@can_edit}
          >
            {gettext("all")}
          </button>
          <button
            type="button"
            class={["join-item btn btn-xs", @parsed_condition["logic"] == "any" && "btn-active"]}
            phx-click={@on_change}
            phx-value-logic="any"
            {context_phx_values(@context)}
            phx-target={@target}
            disabled={!@can_edit}
          >
            {gettext("any")}
          </button>
        </div>
        <span class="text-base-content/60">{gettext("of the rules")}</span>
      </div>

      <%!-- Switch mode info --%>
      <p :if={@switch_mode && @parsed_condition["rules"] != []} class="text-xs text-base-content/60">
        {gettext("Each condition creates an output. First match wins.")}
      </p>

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
          context={@context}
          switch_mode={@switch_mode}
        />
      </div>

      <%!-- Add rule button --%>
      <button
        :if={@can_edit}
        type="button"
        phx-click={@on_change}
        phx-value-action="add_rule"
        phx-value-switch-mode={to_string(@switch_mode)}
        {context_phx_values(@context)}
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
  attr :context, :map, default: %{}
  attr :switch_mode, :boolean, default: false

  defp condition_rule(assigns) do
    # Find the selected variable to get its type and options
    selected_var =
      find_variable(assigns.variables, assigns.rule["page"], assigns.rule["variable"])

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
    <div class="flex items-start gap-2 p-3 bg-base-200 rounded-lg">
      <input type="hidden" name="rule_id" value={@rule["id"]} />
      <div class="flex-1 space-y-2">
        <%!-- Row 0: Output label (switch mode only) --%>
        <div :if={@switch_mode} class="flex items-center gap-2">
          <span class="text-xs text-base-content/60">→</span>
          <input
            type="text"
            name={"rule_label_#{@rule["id"]}"}
            value={@rule["label"] || ""}
            disabled={!@can_edit}
            placeholder={gettext("Output label...")}
            class="input input-sm input-bordered flex-1 text-xs font-medium"
          />
        </div>
        <%!-- Row 1: Page + Variable --%>
        <div class="grid grid-cols-2 gap-2">
          <select
            class="select select-sm select-bordered w-full text-xs"
            name={"rule_page_#{@rule["id"]}"}
            disabled={!@can_edit}
          >
            <option value="">{gettext("Page...")}</option>
            <option
              :for={{page_shortcut, page_name, _vars} <- @pages_with_variables}
              value={page_shortcut}
              selected={@rule["page"] == page_shortcut}
            >
              {page_name}
            </option>
          </select>
          <select
            class="select select-sm select-bordered w-full text-xs"
            name={"rule_variable_#{@rule["id"]}"}
            disabled={!@can_edit || is_nil(@rule["page"]) || @rule["page"] == ""}
          >
            <option value="">{gettext("Variable...")}</option>
            <%= for {page_shortcut, _page_name, vars} <- @pages_with_variables,
                    page_shortcut == @rule["page"],
                    var <- vars do %>
              <option value={var.variable_name} selected={@rule["variable"] == var.variable_name}>
                {var.variable_name}
              </option>
            <% end %>
          </select>
        </div>
        <%!-- Row 2: Operator + Value --%>
        <div class="grid grid-cols-2 gap-2">
          <select
            class="select select-sm select-bordered w-full text-xs"
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
          <.value_input
            :if={@show_value}
            rule={@rule}
            var_type={@var_type}
            select_options={@select_options}
            on_change={@on_change}
            target={@target}
            can_edit={@can_edit}
          />
          <div :if={!@show_value}></div>
        </div>
      </div>

      <%!-- Remove button --%>
      <button
        :if={@can_edit}
        type="button"
        phx-click={@on_change}
        phx-value-action="remove_rule"
        phx-value-rule-id={@rule["id"]}
        {context_phx_values(@context)}
        phx-target={@target}
        class="btn btn-ghost btn-xs btn-square text-error flex-shrink-0 mt-1"
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
      class="select select-sm select-bordered w-full text-xs"
      name={"rule_value_#{@rule["id"]}"}
      disabled={!@can_edit}
    >
      <option value="">{gettext("Value...")}</option>
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
      class="select select-sm select-bordered w-full text-xs"
      name={"rule_value_#{@rule["id"]}"}
      disabled={!@can_edit}
    >
      <option value="">{gettext("Value...")}</option>
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
      class="input input-sm input-bordered w-full text-xs"
    />
    """
  end

  defp value_input(%{var_type: "boolean"} = assigns) do
    ~H"""
    <select
      class="select select-sm select-bordered w-full text-xs"
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
      class="input input-sm input-bordered w-full text-xs"
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
      class="input input-sm input-bordered w-full text-xs"
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

  # Converts context map to phx-value-* attributes for use in HEEx templates
  defp context_phx_values(context) when is_map(context) do
    context
    |> Enum.map(fn {key, value} ->
      # Convert key like "response-id" to "phx-value-response-id"
      {String.to_atom("phx-value-#{key}"), value}
    end)
  end

  defp context_phx_values(_), do: []
end
