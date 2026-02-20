defmodule Storyarn.Flows.Condition do
  @moduledoc """
  Condition structure and validation for dialogue responses.

  A condition is stored as JSON in the response's `condition` field.
  The structure supports compound conditions with AND/OR logic.

  ## Flat Format (legacy, still supported)

  ```json
  {
    "logic": "all",
    "rules": [
      {
        "sheet": "mc.jaime",
        "variable": "class",
        "operator": "equals",
        "value": "mage"
      }
    ]
  }
  ```

  ## Block Format (nested conditions with grouping)

  ```json
  {
    "logic": "any",
    "blocks": [
      {"id": "block_1", "type": "block", "logic": "all", "rules": [...]},
      {"id": "group_1", "type": "group", "logic": "all", "blocks": [
        {"id": "block_2", "type": "block", "logic": "all", "rules": [...]},
        {"id": "block_3", "type": "block", "logic": "all", "rules": [...]}
      ]}
    ]
  }
  ```

  Detection: presence of `"blocks"` key = block format. Max nesting: 1 level
  (groups cannot contain groups).

  ## Operators by Block Type

  - `text`: equals, not_equals, contains, starts_with, ends_with, is_empty
  - `number`: equals, not_equals, greater_than, greater_than_or_equal, less_than, less_than_or_equal
  - `boolean`: is_true, is_false, is_nil
  - `select`: equals, not_equals, is_nil
  - `multi_select`: contains, not_contains, is_empty
  - `date`: equals, not_equals, before, after

  ## Backward Compatibility

  Plain string conditions (legacy) are preserved as-is.
  JSON parsing failures result in `nil` condition (fail gracefully).
  Flat format is never auto-migrated in DB — upgrade happens on first edit in JS.
  """

  @logic_types ["all", "any"]

  @text_operators ~w(equals not_equals contains starts_with ends_with is_empty)
  @number_operators ~w(equals not_equals greater_than greater_than_or_equal less_than less_than_or_equal)
  @boolean_operators ~w(is_true is_false is_nil)
  @select_operators ~w(equals not_equals is_nil)
  @multi_select_operators ~w(contains not_contains is_empty)
  @date_operators ~w(equals not_equals before after)

  @all_operators @text_operators ++
                   @number_operators ++
                   @boolean_operators ++
                   @select_operators ++
                   @multi_select_operators ++
                   @date_operators

  # =============================================================================
  # Public API
  # =============================================================================

  @doc """
  Returns the list of valid logic types.
  """
  @spec logic_types() :: [String.t()]
  def logic_types, do: @logic_types

  @doc """
  Returns operators available for a given block type.
  """
  @spec operators_for_type(String.t()) :: [String.t()]
  def operators_for_type("text"), do: @text_operators
  def operators_for_type("rich_text"), do: @text_operators
  def operators_for_type("number"), do: @number_operators
  def operators_for_type("boolean"), do: @boolean_operators
  def operators_for_type("select"), do: @select_operators
  def operators_for_type("multi_select"), do: @multi_select_operators
  def operators_for_type("date"), do: @date_operators
  def operators_for_type(_), do: @text_operators

  @doc """
  Returns a human-readable label for an operator.
  """
  @spec operator_label(String.t()) :: String.t()
  def operator_label("equals"), do: "equals"
  def operator_label("not_equals"), do: "not equals"
  def operator_label("contains"), do: "contains"
  def operator_label("starts_with"), do: "starts with"
  def operator_label("ends_with"), do: "ends with"
  def operator_label("is_empty"), do: "is empty"
  def operator_label("greater_than"), do: ">"
  def operator_label("greater_than_or_equal"), do: ">="
  def operator_label("less_than"), do: "<"
  def operator_label("less_than_or_equal"), do: "<="
  def operator_label("is_true"), do: "is true"
  def operator_label("is_false"), do: "is false"
  def operator_label("is_nil"), do: "is not set"
  def operator_label("not_contains"), do: "does not contain"
  def operator_label("before"), do: "before"
  def operator_label("after"), do: "after"
  def operator_label(op), do: op

  @doc """
  Returns true if the operator requires a value input.
  """
  @spec operator_requires_value?(String.t()) :: boolean()
  def operator_requires_value?(operator)
      when operator in ["is_empty", "is_true", "is_false", "is_nil"],
      do: false

  def operator_requires_value?(_operator), do: true

  @doc """
  Parses a condition string (JSON) into a structured map.
  Returns nil if parsing fails or the string is empty.
  Returns :legacy if the string is not valid JSON (legacy plain-text condition).
  """
  @spec parse(String.t() | nil) :: map() | :legacy | nil
  def parse(nil), do: nil
  def parse(""), do: nil

  def parse(condition_string) when is_binary(condition_string) do
    case Jason.decode(condition_string) do
      {:ok, %{"logic" => logic, "blocks" => blocks}}
      when logic in @logic_types and is_list(blocks) ->
        %{
          "logic" => logic,
          "blocks" => Enum.map(blocks, &normalize_block/1) |> Enum.reject(&is_nil/1)
        }

      {:ok, %{"logic" => logic, "rules" => rules}}
      when logic in @logic_types and is_list(rules) ->
        %{
          "logic" => logic,
          "rules" => Enum.map(rules, &normalize_rule/1)
        }

      {:ok, _invalid} ->
        # Valid JSON but wrong structure
        :legacy

      {:error, _} ->
        # Not valid JSON, treat as legacy expression
        :legacy
    end
  end

  @doc """
  Serializes a condition map to JSON string.
  Returns nil if the condition has no rules at all.
  Keeps incomplete rules (user is still editing them).
  """
  @spec to_json(map() | nil) :: String.t() | nil
  def to_json(nil), do: nil
  def to_json(%{"rules" => []}), do: nil
  def to_json(%{"rules" => nil}), do: nil
  def to_json(%{"blocks" => []}), do: nil
  def to_json(%{"blocks" => nil}), do: nil

  def to_json(%{"logic" => logic, "blocks" => blocks}) when is_list(blocks) do
    normalized_blocks = Enum.map(blocks, &normalize_block/1) |> Enum.reject(&is_nil/1)
    Jason.encode!(%{"logic" => logic, "blocks" => normalized_blocks})
  end

  def to_json(%{"logic" => logic, "rules" => rules}) when is_list(rules) do
    # Keep all rules, including incomplete ones (user is editing)
    normalized_rules = Enum.map(rules, &normalize_rule/1)
    Jason.encode!(%{"logic" => logic, "rules" => normalized_rules})
  end

  def to_json(_), do: nil

  @doc """
  Creates a new empty condition with the given logic type.
  """
  @spec new(String.t()) :: map()
  def new(logic \\ "all") when logic in @logic_types do
    %{"logic" => logic, "rules" => []}
  end

  @doc """
  Adds a new rule to a condition.
  Options:
  - :with_label - include a label field (for switch mode)
  """
  @spec add_rule(map(), keyword()) :: map()
  def add_rule(condition, opts \\ [])

  def add_rule(%{"logic" => logic, "rules" => rules}, opts) do
    new_rule = %{
      "id" => generate_rule_id(),
      "sheet" => nil,
      "variable" => nil,
      "operator" => "equals",
      "value" => nil
    }

    # Add label field if requested (for switch mode)
    new_rule =
      if Keyword.get(opts, :with_label, false) do
        Map.put(new_rule, "label", "")
      else
        new_rule
      end

    %{"logic" => logic, "rules" => rules ++ [new_rule]}
  end

  @doc """
  Removes a rule from a condition by its ID.
  """
  @spec remove_rule(map(), String.t()) :: map()
  def remove_rule(%{"logic" => logic, "rules" => rules}, rule_id) do
    updated_rules = Enum.reject(rules, fn rule -> rule["id"] == rule_id end)
    %{"logic" => logic, "rules" => updated_rules}
  end

  @doc """
  Updates a specific field of a rule.
  """
  @spec update_rule(map(), String.t(), String.t(), any()) :: map()
  def update_rule(%{"logic" => logic, "rules" => rules}, rule_id, field, value) do
    updated_rules =
      Enum.map(rules, fn rule ->
        if rule["id"] == rule_id do
          Map.put(rule, field, value)
        else
          rule
        end
      end)

    %{"logic" => logic, "rules" => updated_rules}
  end

  @doc """
  Sets the logic type (all/any) of a condition.
  """
  @spec set_logic(map(), String.t()) :: map()
  def set_logic(%{"rules" => rules}, logic) when logic in @logic_types do
    %{"logic" => logic, "rules" => rules}
  end

  @known_keys ~w(id sheet variable operator value label)
  @known_block_keys ~w(id type logic rules label)
  @known_group_keys ~w(id type logic blocks)

  @doc """
  Sanitizes a condition map received from the JS hook.
  Keeps only known keys, normalizes rules, and validates logic.
  Supports both flat (rules) and block-based (blocks) formats.
  """
  @spec sanitize(map()) :: map()
  def sanitize(%{"logic" => logic, "blocks" => blocks}) when is_list(blocks) do
    sanitized_logic = if logic in @logic_types, do: logic, else: "all"

    sanitized_blocks =
      blocks
      |> Enum.filter(&is_map/1)
      |> Enum.map(&sanitize_block/1)
      |> Enum.reject(&is_nil/1)

    %{"logic" => sanitized_logic, "blocks" => sanitized_blocks}
  end

  def sanitize(%{"logic" => logic, "rules" => rules}) when is_list(rules) do
    sanitized_logic = if logic in @logic_types, do: logic, else: "all"

    sanitized_rules =
      rules
      |> Enum.filter(&is_map/1)
      |> Enum.map(fn rule ->
        rule
        |> Map.take(@known_keys)
        |> normalize_rule()
      end)
      |> Enum.reject(&is_nil/1)

    %{"logic" => sanitized_logic, "rules" => sanitized_rules}
  end

  def sanitize(_), do: %{"logic" => "all", "rules" => []}

  @doc """
  Validates that a condition structure is valid.
  Returns {:ok, condition} or {:error, reason}.
  """
  @spec validate(map()) :: {:ok, map()} | {:error, String.t()}
  def validate(%{"logic" => logic, "blocks" => blocks})
      when logic in @logic_types and is_list(blocks) do
    if Enum.all?(blocks, &valid_block_structure?/1) do
      {:ok, %{"logic" => logic, "blocks" => blocks}}
    else
      {:error, "Invalid block structure"}
    end
  end

  def validate(%{"logic" => logic, "rules" => rules})
      when logic in @logic_types and is_list(rules) do
    if Enum.all?(rules, &valid_rule_structure?/1) do
      {:ok, %{"logic" => logic, "rules" => rules}}
    else
      {:error, "Invalid rule structure"}
    end
  end

  def validate(_), do: {:error, "Invalid condition structure"}

  @doc """
  Returns true if a condition has any complete, evaluable rules.
  """
  @spec has_rules?(map() | nil) :: boolean()
  def has_rules?(nil), do: false

  def has_rules?(%{"blocks" => blocks}) when is_list(blocks),
    do: Enum.any?(blocks, &block_has_rules?/1)

  def has_rules?(%{"rules" => rules}) when is_list(rules), do: Enum.any?(rules, &valid_rule?/1)
  def has_rules?(_), do: false

  @doc """
  Upgrades a flat-format condition to block format.
  Wraps the existing rules into a single block.
  Passes through block-format conditions unchanged.
  """
  @spec upgrade(map() | nil) :: map()
  def upgrade(nil), do: new_block_condition()

  def upgrade(%{"blocks" => _} = condition), do: condition

  def upgrade(%{"logic" => logic, "rules" => rules}) when is_list(rules) do
    block = %{
      "id" => generate_block_id(),
      "type" => "block",
      "logic" => logic,
      "rules" => rules
    }

    %{"logic" => "all", "blocks" => [block]}
  end

  def upgrade(_), do: new_block_condition()

  @doc """
  Creates an empty block-format condition.
  """
  @spec new_block_condition(String.t()) :: map()
  def new_block_condition(logic \\ "all") when logic in @logic_types do
    %{"logic" => logic, "blocks" => []}
  end

  @doc """
  Extracts all rules from either format into a flat list.
  Recursively traverses blocks and groups to collect every leaf rule.
  """
  @spec extract_all_rules(map() | nil) :: [map()]
  def extract_all_rules(nil), do: []

  def extract_all_rules(%{"blocks" => blocks}) when is_list(blocks) do
    Enum.flat_map(blocks, &extract_block_rules/1)
  end

  def extract_all_rules(%{"rules" => rules}) when is_list(rules), do: rules
  def extract_all_rules(_), do: []

  # =============================================================================
  # Private Helpers
  # =============================================================================

  defp normalize_rule(rule) when is_map(rule) do
    base = %{
      "id" => rule["id"] || generate_rule_id(),
      "sheet" => rule["sheet"],
      "variable" => rule["variable"],
      "operator" => normalize_operator(rule["operator"]),
      "value" => rule["value"]
    }

    # Preserve label field if present (for switch mode)
    if Map.has_key?(rule, "label") do
      Map.put(base, "label", rule["label"])
    else
      base
    end
  end

  defp normalize_rule(_), do: nil

  defp normalize_operator(nil), do: "equals"
  defp normalize_operator(op) when op in @all_operators, do: op
  defp normalize_operator(_), do: "equals"

  defp valid_rule_structure?(rule) when is_map(rule) do
    Map.has_key?(rule, "sheet") and
      Map.has_key?(rule, "variable") and
      Map.has_key?(rule, "operator")
  end

  defp valid_rule_structure?(_), do: false

  # A rule is considered valid/complete if it has page, variable, and operator set
  # (value may be nil for operators like is_empty, is_true, is_false, is_nil)
  defp valid_rule?(rule) when is_map(rule) do
    page = rule["sheet"]
    variable = rule["variable"]
    operator = rule["operator"]

    is_binary(page) and page != "" and
      is_binary(variable) and variable != "" and
      is_binary(operator) and operator in @all_operators
  end

  defp valid_rule?(_), do: false

  defp generate_rule_id do
    "rule_#{:erlang.unique_integer([:positive])}"
  end

  defp generate_block_id do
    "block_#{:erlang.unique_integer([:positive])}"
  end

  # -- Block processing (shared by normalize and sanitize) --

  defp process_block(%{"type" => "block", "rules" => rules} = block, mode) when is_list(rules) do
    processed_rules =
      rules
      |> Enum.filter(&is_map/1)
      |> then(fn rs ->
        if mode == :sanitize,
          do: Enum.map(rs, &Map.take(&1, @known_keys)),
          else: rs
      end)
      |> Enum.map(&normalize_rule/1)
      |> Enum.reject(&is_nil/1)

    base = %{
      "id" => block["id"] || generate_block_id(),
      "type" => "block",
      "logic" => if(block["logic"] in @logic_types, do: block["logic"], else: "all"),
      "rules" => processed_rules
    }

    if Map.has_key?(block, "label"), do: Map.put(base, "label", block["label"]), else: base
  end

  defp process_block(%{"type" => "group", "blocks" => inner_blocks} = group, mode)
       when is_list(inner_blocks) do
    normalized_inner =
      inner_blocks
      |> Enum.filter(fn b -> is_map(b) and b["type"] == "block" end)
      |> Enum.map(&process_block(&1, mode))
      |> Enum.reject(&is_nil/1)

    %{
      "id" => group["id"] || generate_block_id(),
      "type" => "group",
      "logic" => if(group["logic"] in @logic_types, do: group["logic"], else: "all"),
      "blocks" => normalized_inner
    }
  end

  defp process_block(_, _mode), do: nil

  defp normalize_block(block), do: process_block(block, :normalize)

  defp sanitize_block(%{"type" => "block"} = block) do
    process_block(Map.take(block, @known_block_keys), :sanitize)
  end

  defp sanitize_block(%{"type" => "group"} = group) do
    process_block(Map.take(group, @known_group_keys), :sanitize)
  end

  defp sanitize_block(_), do: nil

  # -- Block rule checking --

  defp block_has_rules?(%{"type" => "block", "rules" => rules}) when is_list(rules) do
    Enum.any?(rules, &valid_rule?/1)
  end

  defp block_has_rules?(%{"type" => "group", "blocks" => blocks}) when is_list(blocks) do
    Enum.any?(blocks, &block_has_rules?/1)
  end

  defp block_has_rules?(_), do: false

  # -- Block rule extraction --

  defp extract_block_rules(%{"type" => "block", "rules" => rules}) when is_list(rules), do: rules

  defp extract_block_rules(%{"type" => "group", "blocks" => blocks}) when is_list(blocks) do
    Enum.flat_map(blocks, &extract_block_rules/1)
  end

  defp extract_block_rules(_), do: []

  # -- Block structure validation --

  defp valid_block_structure?(%{"type" => "block", "rules" => rules}) when is_list(rules) do
    Enum.all?(rules, &valid_rule_structure?/1)
  end

  defp valid_block_structure?(%{"type" => "group", "blocks" => blocks}) when is_list(blocks) do
    Enum.all?(blocks, fn b -> is_map(b) and b["type"] == "block" and valid_block_structure?(b) end)
  end

  defp valid_block_structure?(_), do: false
end
