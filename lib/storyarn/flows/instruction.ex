defmodule Storyarn.Flows.Instruction do
  @moduledoc """
  Domain logic for Instruction node assignments.

  The "write" counterpart to Condition (which is "read").
  Manages a list of variable assignments within an instruction node.

  ## Operators by Block Type

  - `number`: set, add, subtract
  - `boolean`: set_true, set_false, toggle
  - `text` / `rich_text`: set, clear
  - `select` / `multi_select`: set
  - `date`: set

  ## Assignment Structure

      %{
        "id" => "assign_12345",
        "page" => "mc.jaime",
        "variable" => "health",
        "operator" => "add",
        "value" => "10",
        "value_type" => "literal",
        "value_page" => nil
      }

  ## Value Types

  - `"literal"` (default) — typed value (string, parsed by game engine)
  - `"variable_ref"` — references another variable via `value_page` + `value`
  """

  @number_operators ~w(set add subtract)
  @boolean_operators ~w(set_true set_false toggle)
  @text_operators ~w(set clear)
  @select_operators ~w(set)
  @date_operators ~w(set)

  @all_operators Enum.uniq(
                   @number_operators ++
                     @boolean_operators ++
                     @text_operators ++
                     @select_operators ++
                     @date_operators
                 )

  @value_types ~w(literal variable_ref)

  @known_keys ~w(id page variable operator value value_type value_page)

  # =============================================================================
  # Public API
  # =============================================================================

  @doc """
  Returns operators available for a given block type.
  """
  @spec operators_for_type(String.t()) :: [String.t()]
  def operators_for_type("number"), do: @number_operators
  def operators_for_type("boolean"), do: @boolean_operators
  def operators_for_type("text"), do: @text_operators
  def operators_for_type("rich_text"), do: @text_operators
  def operators_for_type("select"), do: @select_operators
  def operators_for_type("multi_select"), do: @select_operators
  def operators_for_type("date"), do: @date_operators
  def operators_for_type(_), do: @text_operators

  @doc """
  Returns a human-readable label for an operator.
  """
  @spec operator_label(String.t()) :: String.t()
  def operator_label("set"), do: "="
  def operator_label("add"), do: "+="
  def operator_label("subtract"), do: "-="
  def operator_label("set_true"), do: "= true"
  def operator_label("set_false"), do: "= false"
  def operator_label("toggle"), do: "toggle"
  def operator_label("clear"), do: "clear"
  def operator_label(op), do: op

  @doc """
  Returns true if the operator requires a value input.
  """
  @spec operator_requires_value?(String.t()) :: boolean()
  def operator_requires_value?(operator)
      when operator in ["set_true", "set_false", "toggle", "clear"],
      do: false

  def operator_requires_value?(_operator), do: true

  @doc """
  Returns true if the value type is valid.
  """
  @spec valid_value_type?(String.t()) :: boolean()
  def valid_value_type?(type) when type in @value_types, do: true
  def valid_value_type?(_), do: false

  @doc """
  Returns true if the operator is known.
  """
  @spec valid_operator?(String.t()) :: boolean()
  def valid_operator?(op) when op in @all_operators, do: true
  def valid_operator?(_), do: false

  @doc """
  Returns all known operators.
  """
  @spec all_operators() :: [String.t()]
  def all_operators, do: @all_operators

  @doc """
  Returns the list of known assignment keys for sanitization.
  """
  @spec known_keys() :: [String.t()]
  def known_keys, do: @known_keys

  @doc """
  Creates a new empty assignments list.
  """
  @spec new() :: list()
  def new, do: []

  @doc """
  Appends a new empty assignment to the list.
  """
  @spec add_assignment(list()) :: list()
  def add_assignment(assignments) when is_list(assignments) do
    new_assignment = %{
      "id" => generate_assignment_id(),
      "page" => nil,
      "variable" => nil,
      "operator" => "set",
      "value" => nil,
      "value_type" => "literal",
      "value_page" => nil
    }

    assignments ++ [new_assignment]
  end

  @doc """
  Removes an assignment by its ID.
  """
  @spec remove_assignment(list(), String.t()) :: list()
  def remove_assignment(assignments, assignment_id) when is_list(assignments) do
    Enum.reject(assignments, fn a -> a["id"] == assignment_id end)
  end

  @doc """
  Updates a single field of an assignment by its ID.

  Special behavior:
  - When `value_type` changes to `"literal"` → clears `value_page`
  - When `value_type` changes to `"variable_ref"` → clears `value`
  """
  @spec update_assignment(list(), String.t(), String.t(), any()) :: list()
  def update_assignment(assignments, assignment_id, field, value) when is_list(assignments) do
    Enum.map(assignments, fn assignment ->
      if assignment["id"] == assignment_id do
        assignment
        |> Map.put(field, value)
        |> maybe_clear_on_value_type_change(field, value)
      else
        assignment
      end
    end)
  end

  @doc """
  Returns a human-readable short string for an assignment.

  ## Examples

      iex> format_assignment_short(%{"page" => "mc.jaime", "variable" => "health", "operator" => "add", "value" => "10", "value_type" => "literal"})
      "mc.jaime.health += 10"

      iex> format_assignment_short(%{"page" => "mc.link", "variable" => "hasMasterSword", "operator" => "set", "value_type" => "variable_ref", "value_page" => "global.quests", "value" => "swordDone"})
      "mc.link.hasMasterSword = global.quests.swordDone"

      iex> format_assignment_short(%{"page" => "mc.jaime", "variable" => "alive", "operator" => "set_true"})
      "mc.jaime.alive = true"
  """
  # Keep in sync with assets/js/hooks/flow_canvas/components/node_formatters.js:formatAssignment
  @spec format_assignment_short(map()) :: String.t()
  def format_assignment_short(%{"page" => page, "variable" => variable} = assignment)
      when is_binary(page) and page != "" and is_binary(variable) and variable != "" do
    ref = "#{page}.#{variable}"
    operator = assignment["operator"] || "set"

    case operator do
      "set_true" ->
        "#{ref} = true"

      "set_false" ->
        "#{ref} = false"

      "toggle" ->
        "toggle #{ref}"

      "clear" ->
        "clear #{ref}"

      op ->
        value_display = format_value(assignment)
        "#{ref} #{operator_label(op)} #{value_display}"
    end
  end

  def format_assignment_short(_), do: ""

  @doc """
  Returns true if an assignment has all required fields for execution.
  """
  @spec complete_assignment?(map()) :: boolean()
  def complete_assignment?(assignment) when is_map(assignment) do
    page = assignment["page"]
    variable = assignment["variable"]
    operator = assignment["operator"]

    has_target =
      is_binary(page) and page != "" and
        is_binary(variable) and variable != "" and
        is_binary(operator) and operator in @all_operators

    if has_target and operator_requires_value?(operator) do
      has_value?(assignment)
    else
      has_target
    end
  end

  def complete_assignment?(_), do: false

  @doc """
  Returns true if the assignments list has any complete assignments.
  """
  @spec has_assignments?(list() | nil) :: boolean()
  def has_assignments?(nil), do: false

  def has_assignments?(assignments) when is_list(assignments) do
    Enum.any?(assignments, &complete_assignment?/1)
  end

  def has_assignments?(_), do: false

  @doc """
  Sanitizes an assignments list, keeping only known keys.
  """
  @spec sanitize(list()) :: list()
  def sanitize(assignments) when is_list(assignments) do
    Enum.map(assignments, fn assignment ->
      assignment
      |> Map.take(@known_keys)
      |> normalize_assignment()
    end)
  end

  def sanitize(_), do: []

  # =============================================================================
  # Private Helpers
  # =============================================================================

  defp format_value(%{"value_type" => "variable_ref", "value_page" => vp, "value" => v})
       when is_binary(vp) and vp != "" and is_binary(v) and v != "" do
    "#{vp}.#{v}"
  end

  defp format_value(%{"value" => value}) when is_binary(value) and value != "", do: value
  defp format_value(_), do: "?"

  defp has_value?(%{"value_type" => "variable_ref"} = assignment) do
    vp = assignment["value_page"]
    v = assignment["value"]
    is_binary(vp) and vp != "" and is_binary(v) and v != ""
  end

  defp has_value?(assignment) when is_map(assignment) do
    value = assignment["value"]
    is_binary(value) and value != ""
  end

  defp has_value?(_), do: false

  defp maybe_clear_on_value_type_change(assignment, "value_type", "literal") do
    Map.put(assignment, "value_page", nil)
  end

  defp maybe_clear_on_value_type_change(assignment, "value_type", "variable_ref") do
    Map.put(assignment, "value", nil)
  end

  defp maybe_clear_on_value_type_change(assignment, _field, _value), do: assignment

  defp normalize_assignment(assignment) do
    assignment
    |> Map.put_new("id", generate_assignment_id())
    |> Map.put_new("operator", "set")
    |> Map.put_new("value_type", "literal")
    |> Map.put_new("value_page", nil)
  end

  defp generate_assignment_id do
    "assign_#{:erlang.unique_integer([:positive])}"
  end
end
