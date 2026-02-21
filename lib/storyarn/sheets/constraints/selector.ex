defmodule Storyarn.Sheets.Constraints.Selector do
  @moduledoc """
  Constraints for select and multi_select blocks/columns: max_options.

  Only multi_select uses max_options — select has no constraints.
  """

  alias Storyarn.Sheets.Constraints.Number, as: NumberConstraints

  @doc """
  Extracts selector constraints from a config map.

  Returns a constraints map with parsed values, or nil if all are nil.
  Only meaningful for multi_select (max_options).

      iex> extract(%{"max_options" => "3"})
      %{"max_options" => 3.0}

      iex> extract(%{"max_options" => nil})
      nil
  """
  @spec extract(map()) :: map() | nil
  def extract(config) when is_map(config) do
    constraints = %{
      "max_options" => NumberConstraints.parse_constraint(config["max_options"])
    }

    if Enum.all?(Map.values(constraints), &is_nil/1), do: nil, else: constraints
  end

  def extract(_), do: nil

  @doc """
  Clamps a list of selected values to the max_options constraint.

  Truncates the list if it exceeds the maximum number of selections.
  Non-list values pass through unchanged.

      iex> clamp(["a", "b", "c", "d"], %{"max_options" => 2})
      ["a", "b"]

      iex> clamp(["a"], %{"max_options" => 2})
      ["a"]

      iex> clamp("single", nil)
      "single"
  """
  @spec clamp(any(), map() | nil) :: any()
  def clamp(value, %{"max_options" => max}) when is_list(value) and is_number(max) and max > 0 do
    Enum.take(value, trunc(max))
  end

  def clamp(value, _), do: value
end
