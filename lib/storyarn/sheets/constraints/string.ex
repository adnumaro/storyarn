defmodule Storyarn.Sheets.Constraints.String do
  @moduledoc """
  Constraints for text and rich_text blocks/columns: max_length.
  """

  alias Storyarn.Sheets.Constraints.Number, as: NumberConstraints

  @doc """
  Extracts string constraints from a config map.

  Returns a constraints map with parsed values, or nil if all are nil.

      iex> extract(%{"max_length" => "500"})
      %{"max_length" => 500.0}

      iex> extract(%{"max_length" => nil})
      nil
  """
  @spec extract(map()) :: map() | nil
  def extract(config) when is_map(config) do
    constraints = %{
      "max_length" => NumberConstraints.parse_constraint(config["max_length"])
    }

    if Enum.all?(Map.values(constraints), &is_nil/1), do: nil, else: constraints
  end

  def extract(_), do: nil

  @doc """
  Clamps a string value to the max_length constraint.

  Truncates the string if it exceeds the maximum length.
  Non-string values pass through unchanged.

      iex> clamp("hello world", %{"max_length" => 5})
      "hello"

      iex> clamp("hi", %{"max_length" => 5})
      "hi"

      iex> clamp("hello", nil)
      "hello"
  """
  @spec clamp(any(), map() | nil) :: any()
  def clamp(value, %{"max_length" => max}) when is_binary(value) and is_number(max) and max > 0 do
    if String.length(value) > trunc(max) do
      String.slice(value, 0, trunc(max))
    else
      value
    end
  end

  def clamp(value, _), do: value
end
