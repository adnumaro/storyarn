defmodule StoryarnWeb.Components.ExpressionEditor do
  @moduledoc """
  Tabbed expression editor: Builder | Code.

  Wraps the visual builder (condition or instruction) and the CodeMirror
  code editor in a tabbed interface. Switching tabs converts data
  bidirectionally — the structured data is always the source of truth.
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.ConditionBuilder
  import StoryarnWeb.Components.InstructionBuilder

  alias Storyarn.Flows

  attr :id, :string, required: true
  attr :mode, :string, required: true, values: ~w(condition instruction)
  attr :condition, :map, default: nil
  attr :assignments, :list, default: []
  attr :variables, :list, default: []
  attr :can_edit, :boolean, default: true
  attr :context, :map, default: %{}
  attr :switch_mode, :boolean, default: false
  attr :event_name, :string, default: nil
  attr :active_tab, :string, default: "builder"

  def expression_editor(assigns) do
    serialized_text =
      case assigns.mode do
        "condition" -> serialize_condition_to_text(assigns.condition)
        "instruction" -> serialize_assignments_to_text(assigns.assignments)
      end

    assigns = assign(assigns, :serialized_text, serialized_text)

    ~H"""
    <div id={@id} class="expression-editor">
      <div class="flex items-center gap-1 mb-2">
        <button
          type="button"
          class={"btn btn-xs #{if @active_tab == "builder", do: "btn-active", else: "btn-ghost"}"}
          phx-click="toggle_expression_tab"
          phx-value-id={@id}
          phx-value-tab="builder"
        >
          {dgettext("flows", "Builder")}
        </button>
        <button
          type="button"
          class={"btn btn-xs #{if @active_tab == "code", do: "btn-active", else: "btn-ghost"}"}
          phx-click="toggle_expression_tab"
          phx-value-id={@id}
          phx-value-tab="code"
        >
          {dgettext("flows", "Code")}
        </button>
      </div>

      <div :if={@active_tab == "builder"}>
        <.condition_builder
          :if={@mode == "condition"}
          id={"#{@id}-cond-builder"}
          condition={@condition}
          variables={@variables}
          can_edit={@can_edit}
          context={@context}
          switch_mode={@switch_mode}
          event_name={@event_name}
        />
        <.instruction_builder
          :if={@mode == "instruction"}
          id={"#{@id}-inst-builder"}
          assignments={@assignments}
          variables={@variables}
          can_edit={@can_edit}
          context={@context}
          event_name={@event_name}
        />
      </div>

      <div
        :if={@active_tab == "code"}
        id={"#{@id}-code-editor"}
        phx-hook="ExpressionEditor"
        phx-update="ignore"
        data-mode={if @mode == "condition", do: "expression", else: "assignments"}
        data-content={@serialized_text}
        data-editable={Jason.encode!(@can_edit)}
        data-variables={Jason.encode!(@variables)}
        data-context={Jason.encode!(@context)}
        data-event-name={@event_name}
        data-placeholder={
          if @mode == "condition",
            do: dgettext("flows", "mc.jaime.health > 50"),
            else: dgettext("flows", "mc.jaime.health = 50")
        }
        class="min-h-[60px] border border-base-300 rounded-lg overflow-hidden"
      >
      </div>
    </div>
    """
  end

  @doc """
  Serializes a condition map to DSL text.
  """
  @spec serialize_condition_to_text(map() | nil) :: String.t()
  def serialize_condition_to_text(nil), do: ""
  def serialize_condition_to_text(%{"rules" => []}), do: ""

  def serialize_condition_to_text(%{"blocks" => blocks} = condition) when is_list(blocks) do
    serialize_block_condition(condition)
  end

  def serialize_condition_to_text(condition) when is_map(condition) do
    rules = condition["rules"] || []
    joiner = if condition["logic"] == "any", do: " || ", else: " && "

    rules
    |> Enum.map(&format_rule_to_text/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(joiner)
  end

  def serialize_condition_to_text(_), do: ""

  defp serialize_block_condition(condition) do
    blocks = condition["blocks"] || []
    top_joiner = if condition["logic"] == "any", do: " || ", else: " && "

    blocks
    |> Enum.map(&serialize_block/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(top_joiner)
  end

  defp serialize_block(%{"type" => "group", "blocks" => inner_blocks} = group) do
    group_joiner = if group["logic"] == "any", do: " || ", else: " && "

    texts =
      (inner_blocks || [])
      |> Enum.map(&serialize_block/1)
      |> Enum.reject(&(&1 == ""))

    case texts do
      [] -> ""
      [single] -> single
      many -> "(#{Enum.join(many, group_joiner)})"
    end
  end

  defp serialize_block(%{"rules" => rules} = block) do
    block_joiner = if block["logic"] == "any", do: " || ", else: " && "

    texts =
      (rules || [])
      |> Enum.map(&format_rule_to_text/1)
      |> Enum.reject(&(&1 == ""))

    case texts do
      [] -> ""
      [single] -> single
      many -> "(#{Enum.join(many, block_joiner)})"
    end
  end

  defp serialize_block(_), do: ""

  @doc """
  Serializes a list of assignments to DSL text.
  """
  @spec serialize_assignments_to_text(list() | nil) :: String.t()
  def serialize_assignments_to_text(nil), do: ""
  def serialize_assignments_to_text([]), do: ""

  def serialize_assignments_to_text(assignments) do
    assignments
    |> Enum.map(&Flows.instruction_format_short/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp format_rule_to_text(rule) do
    sheet = rule["sheet"]
    variable = rule["variable"]
    operator = rule["operator"]
    value = rule["value"]

    if is_binary(sheet) and sheet != "" and is_binary(variable) and variable != "" do
      ref = "#{sheet}.#{variable}"
      format_comparison(ref, operator, value)
    else
      ""
    end
  end

  defp format_comparison(ref, "is_true", _), do: ref
  defp format_comparison(ref, "is_false", _), do: "!#{ref}"
  defp format_comparison(ref, "is_nil", _), do: "#{ref} == nil"
  defp format_comparison(ref, "is_empty", _), do: "#{ref} == \"\""

  defp format_comparison(ref, op, value) do
    symbol = operator_to_symbol(op)
    "#{ref} #{symbol} #{format_value(value)}"
  end

  defp operator_to_symbol("equals"), do: "=="
  defp operator_to_symbol("not_equals"), do: "!="
  defp operator_to_symbol("greater_than"), do: ">"
  defp operator_to_symbol("less_than"), do: "<"
  defp operator_to_symbol("greater_than_or_equal"), do: ">="
  defp operator_to_symbol("less_than_or_equal"), do: "<="
  defp operator_to_symbol("contains"), do: "contains"
  defp operator_to_symbol("starts_with"), do: "starts_with"
  defp operator_to_symbol("ends_with"), do: "ends_with"
  defp operator_to_symbol("not_contains"), do: "not_contains"
  defp operator_to_symbol("before"), do: "<"
  defp operator_to_symbol("after"), do: ">"
  defp operator_to_symbol(op), do: op

  defp format_value(nil), do: "?"

  defp format_value(v) when is_binary(v) do
    case Float.parse(v) do
      {_, ""} ->
        v

      _ ->
        escaped = v |> String.replace("\\", "\\\\") |> String.replace("\"", "\\\"")
        ~s("#{escaped}")
    end
  end

  defp format_value(v), do: to_string(v)
end
