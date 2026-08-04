defmodule Storyarn.GlobalSearch.VariableQuery do
  @moduledoc """
  Parses the body of a command-palette variable search.

  The leading `$` is routing syntax owned by the palette and is therefore not
  part of the input accepted here. A query is either a reference fragment used
  for autocomplete or a reference followed by one supported predicate.
  """

  # A table reference contains sheet, table, row and column slugs. The command
  # palette already caps the complete wire payload, so this parser mirrors that
  # bound without rejecting legitimate qualified references.
  @max_length 399
  @operators ~w(+= -= >= <= != !~ = ~ > <)
  @operator_pattern ~r/(\+=|-=|>=|<=|!=|!~|=|~|>|<)/
  @reference_pattern ~r/^[A-Za-z0-9_][A-Za-z0-9_.-]*$/

  @enforce_keys [:reference]
  defstruct [:reference, :operator, :literal]

  @type operator ::
          :add
          | :subtract
          | :greater_than_or_equal
          | :less_than_or_equal
          | :not_equal
          | :not_contains
          | :equal
          | :contains
          | :greater_than
          | :less_than

  @type t :: %__MODULE__{
          reference: String.t(),
          operator: operator() | nil,
          literal: String.t() | nil
        }

  @type error_reason ::
          :empty
          | :too_long
          | :invalid_reference
          | :invalid_predicate

  @spec parse(term()) :: {:ok, t()} | {:error, error_reason()}
  def parse(query) when is_binary(query) do
    cond do
      String.length(query) > @max_length ->
        {:error, :too_long}

      String.trim(query) == "" ->
        {:error, :empty}

      true ->
        parse_query(String.trim(query))
    end
  end

  def parse(_query), do: {:error, :invalid_predicate}

  defp parse_query(query) do
    case Regex.run(@operator_pattern, query, return: :index) do
      nil ->
        build_autocomplete(query)

      [{operator_offset, operator_length} | _captures] ->
        reference =
          query
          |> binary_part(0, operator_offset)
          |> String.trim()

        literal_offset = operator_offset + operator_length

        literal =
          query
          |> binary_part(literal_offset, byte_size(query) - literal_offset)
          |> String.trim()

        operator = binary_part(query, operator_offset, operator_length)
        build_predicate(reference, operator, literal)
    end
  end

  defp build_autocomplete(reference) do
    if valid_reference?(reference) do
      {:ok, %__MODULE__{reference: reference}}
    else
      {:error, :invalid_reference}
    end
  end

  defp build_predicate("", _operator, _literal), do: {:error, :invalid_reference}
  defp build_predicate(_reference, _operator, ""), do: {:error, :invalid_predicate}

  defp build_predicate(reference, operator, literal) do
    cond do
      not valid_reference?(reference) ->
        {:error, :invalid_reference}

      operator not in @operators ->
        {:error, :invalid_predicate}

      starts_with_operator?(literal) ->
        {:error, :invalid_predicate}

      operator in ["~", "!~"] and empty_contains_literal?(literal) ->
        {:error, :invalid_predicate}

      true ->
        {:ok,
         %__MODULE__{
           reference: reference,
           operator: normalize_operator(operator),
           literal: literal
         }}
    end
  end

  defp valid_reference?(reference), do: Regex.match?(@reference_pattern, reference)
  defp starts_with_operator?(literal), do: Regex.match?(~r/^(\+=|-=|>=|<=|!=|!~|=|~|>|<)/, literal)

  defp empty_contains_literal?(literal) do
    literal
    |> unquote_literal()
    |> String.trim()
    |> Kernel.==("")
  end

  defp unquote_literal(<<"\"", rest::binary>>) do
    if String.ends_with?(rest, "\""),
      do: binary_part(rest, 0, byte_size(rest) - 1),
      else: "\"" <> rest
  end

  defp unquote_literal(literal), do: literal

  defp normalize_operator("+="), do: :add
  defp normalize_operator("-="), do: :subtract
  defp normalize_operator(">="), do: :greater_than_or_equal
  defp normalize_operator("<="), do: :less_than_or_equal
  defp normalize_operator("!="), do: :not_equal
  defp normalize_operator("!~"), do: :not_contains
  defp normalize_operator("="), do: :equal
  defp normalize_operator("~"), do: :contains
  defp normalize_operator(">"), do: :greater_than
  defp normalize_operator("<"), do: :less_than
end
