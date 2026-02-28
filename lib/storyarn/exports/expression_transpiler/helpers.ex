defmodule Storyarn.Exports.ExpressionTranspiler.Helpers do
  @moduledoc """
  Shared helpers for all expression transpiler emitters.

  Provides variable reference formatting, literal value formatting,
  logic joining, and condition decoding from all storage formats.
  """

  # ---------------------------------------------------------------------------
  # Variable reference formatting
  # ---------------------------------------------------------------------------

  @doc """
  Builds a full variable reference string from sheet + variable.

  ## Styles

  - `:underscore` — `mc_jaime_health` (Ink)
  - `:dollar_underscore` — `$mc_jaime_health` (Yarn)
  - `:lua_dict` — `Variable["mc.jaime.health"]` (Unity)
  - `:dot` — `mc.jaime.health` (Unreal, articy)
  - `:dialogic_curly` — `{mc_jaime.health}` (Godot Dialogic)
  """
  @spec format_var_ref(String.t(), String.t(), atom()) :: String.t()
  def format_var_ref(sheet, variable, :underscore) do
    "#{dotted_to_underscore(sheet)}_#{dotted_to_underscore(variable)}"
  end

  def format_var_ref(sheet, variable, :dollar_underscore) do
    "$#{dotted_to_underscore(sheet)}_#{dotted_to_underscore(variable)}"
  end

  def format_var_ref(sheet, variable, :lua_dict) do
    safe_sheet = sanitize_identifier(sheet)
    safe_var = sanitize_identifier(variable)
    ~s(Variable["#{safe_sheet}.#{safe_var}"])
  end

  def format_var_ref(sheet, variable, :dot) do
    "#{sanitize_identifier(sheet)}.#{sanitize_identifier(variable)}"
  end

  def format_var_ref(sheet, variable, :dialogic_curly) do
    "{#{dotted_to_underscore(sheet)}.#{sanitize_identifier(variable)}}"
  end

  defp dotted_to_underscore(str) do
    str |> sanitize_identifier() |> String.replace(~r/[.\-]/, "_")
  end

  # Defense-in-depth: strip characters that could cause code injection.
  # Upstream Ecto validation (Validations.validate_shortcut + NameNormalizer)
  # already restricts these, but the transpiler should not blindly trust inputs.
  defp sanitize_identifier(str) when is_binary(str) do
    String.replace(str, ~r/[^a-zA-Z0-9_.\-]/, "")
  end

  # ---------------------------------------------------------------------------
  # Literal value formatting
  # ---------------------------------------------------------------------------

  @doc """
  Formats a literal value for the target engine syntax.

  Numbers and booleans stay unquoted. Strings get double-quoted.
  nil becomes the engine-specific null keyword.
  """
  @spec format_literal(term(), keyword()) :: String.t()
  def format_literal(nil, opts), do: Keyword.get(opts, :null_keyword, "null")
  def format_literal(value, _opts) when is_boolean(value), do: to_string(value)
  def format_literal(value, _opts) when is_integer(value), do: to_string(value)
  def format_literal(value, _opts) when is_float(value), do: to_string(value)

  def format_literal(value, opts) when is_binary(value) do
    cond do
      value in ["true", "false"] -> value
      numeric?(value) -> value
      value == "" -> ~s("")
      true -> quote_string(value, opts)
    end
  end

  def format_literal(value, _opts), do: to_string(value)

  defp numeric?(str), do: Regex.match?(~r/^-?\d+(\.\d+)?$/, str)

  defp quote_string(str, _opts) do
    escaped =
      str
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")
      |> String.replace("\n", "\\n")
      |> String.replace("\r", "\\r")
      |> String.replace("\0", "")

    ~s("#{escaped}")
  end

  # ---------------------------------------------------------------------------
  # Logic combinators
  # ---------------------------------------------------------------------------

  @doc "Joins transpiled expression parts with engine-specific AND/OR."
  @spec join_with_logic(String.t(), [String.t()], keyword()) :: String.t()
  def join_with_logic(logic, parts, opts) do
    joiner =
      case logic do
        "any" -> Keyword.get(opts, :or_keyword, " or ")
        _ -> Keyword.get(opts, :and_keyword, " and ")
      end

    Enum.join(parts, joiner)
  end

  # ---------------------------------------------------------------------------
  # Condition decoding (all storage formats)
  # ---------------------------------------------------------------------------

  @doc """
  Normalizes a condition from any storage format into a structured map.

  Returns `{:ok, condition_map}` for structured conditions,
  `{:ok, nil}` for nil/empty, or `{:error, {:legacy_condition, string}}`
  for legacy plain-text conditions that cannot be transpiled.

  ## Supported inputs

  - `nil` → `{:ok, nil}`
  - `%{"logic" => ..., "rules" => ...}` → pass through
  - `%{"logic" => ..., "blocks" => ...}` → pass through
  - JSON string → decode to map
  - Legacy plain string → `{:error, {:legacy_condition, string}}`
  """
  @spec decode_condition(term()) :: {:ok, map() | nil} | {:error, term()}
  def decode_condition(nil), do: {:ok, nil}
  def decode_condition(""), do: {:ok, nil}

  def decode_condition(%{"logic" => _, "rules" => _} = condition), do: {:ok, condition}
  def decode_condition(%{"logic" => _, "blocks" => _} = condition), do: {:ok, condition}

  def decode_condition(json_string) when is_binary(json_string) do
    case Jason.decode(json_string) do
      {:ok, %{"logic" => _, "rules" => _} = condition} -> {:ok, condition}
      {:ok, %{"logic" => _, "blocks" => _} = condition} -> {:ok, condition}
      {:ok, _} -> {:error, {:legacy_condition, json_string}}
      {:error, _} -> {:error, {:legacy_condition, json_string}}
    end
  end

  def decode_condition(_other), do: {:ok, nil}

  # ---------------------------------------------------------------------------
  # Rule extraction (flattens blocks → rules)
  # ---------------------------------------------------------------------------

  @doc """
  Extracts rules from a condition, handling both flat and block formats.

  For flat format, returns `{logic, rules}`.
  For block format, returns `{top_logic, block_groups}` where each group
  is `{block_logic, rules}`.
  """
  @spec extract_condition_structure(map()) ::
          {:flat, String.t(), [map()]} | {:blocks, String.t(), [{String.t(), [map()]}]}
  def extract_condition_structure(%{"logic" => logic, "blocks" => blocks})
      when is_list(blocks) do
    groups =
      blocks
      |> Enum.map(&extract_block/1)
      |> Enum.reject(&is_nil/1)

    {:blocks, logic, groups}
  end

  def extract_condition_structure(%{"logic" => logic, "rules" => rules})
      when is_list(rules) do
    {:flat, logic, rules}
  end

  def extract_condition_structure(_), do: {:flat, "all", []}

  defp extract_block(%{"type" => "block", "logic" => logic, "rules" => rules})
       when is_list(rules) do
    {logic, rules}
  end

  defp extract_block(%{"type" => "group", "logic" => logic, "blocks" => inner})
       when is_list(inner) do
    flat_rules =
      inner
      |> Enum.map(&extract_block/1)
      |> Enum.reject(&is_nil/1)

    {logic, flat_rules}
  end

  defp extract_block(_), do: nil

  # ---------------------------------------------------------------------------
  # Warning construction
  # ---------------------------------------------------------------------------

  @doc "Creates a structured warning for untranspilable operators."
  @spec unsupported_op_warning(String.t(), String.t(), String.t()) :: map()
  def unsupported_op_warning(operator, engine, var_ref) do
    %{
      type: :unsupported_operator,
      message: "Operator '#{operator}' is not supported by #{engine}",
      details: %{operator: operator, engine: engine, variable: var_ref}
    }
  end

  @doc "Creates a structured warning for operators requiring custom function registration."
  @spec custom_function_warning(String.t(), String.t(), String.t()) :: map()
  def custom_function_warning(operator, engine, var_ref) do
    func_name =
      case operator do
        "contains" -> "string_contains"
        "not_contains" -> "string_contains"
        "starts_with" -> "string_starts_with"
        "ends_with" -> "string_ends_with"
        _ -> operator
      end

    %{
      type: :custom_function_required,
      message: "Operator '#{operator}' requires custom function '#{func_name}' in #{engine}",
      operator: operator,
      function: func_name,
      engine: engine,
      variable: var_ref
    }
  end
end
