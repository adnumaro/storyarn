defmodule Storyarn.Sheets.Constraints.Number do
  @moduledoc """
  Constraints for number blocks and columns: min, max, step.

  Handles both string and number constraint values — config panel saves
  strings (from HTML forms) while table column settings save numbers
  (via `parse_constraint/1`). The clamping functions accept either.
  """

  @doc """
  Extracts number constraints from a config map.

  Returns a constraints map with parsed numeric values, or nil if all are nil.

      iex> extract(%{"min" => "0", "max" => "100", "step" => "1"})
      %{"min" => 0, "max" => 100, "step" => 1}

      iex> extract(%{"min" => nil, "max" => nil, "step" => nil})
      nil
  """
  @spec extract(map()) :: map() | nil
  def extract(config) when is_map(config) do
    constraints = %{
      "min" => parse_constraint(config["min"]),
      "max" => parse_constraint(config["max"]),
      "step" => parse_constraint(config["step"])
    }

    if Enum.all?(Map.values(constraints), &is_nil/1), do: nil, else: constraints
  end

  def extract(_), do: nil

  @doc """
  Clamps a numeric value to the min/max bounds in the given config map.

  Handles constraint values that are numbers, strings, or nil.

      iex> clamp(150, %{"min" => 0, "max" => 100})
      100

      iex> clamp(-5, %{"min" => "0", "max" => "100"})
      0

      iex> clamp(50, %{"min" => nil, "max" => nil})
      50
  """
  @spec clamp(number(), map() | nil) :: number()
  def clamp(value, config) when is_number(value) and is_map(config) do
    value
    |> clamp_bound(:min, config["min"])
    |> clamp_bound(:max, config["max"])
  end

  def clamp(value, _), do: value

  @doc """
  Parses a string value, clamps it, and formats back to string.

  Used by server-side handlers that receive form values as strings
  and need to clamp before persisting.

      iex> clamp_and_format("150", %{"min" => 0, "max" => 100})
      "100"

      iex> clamp_and_format("not_a_number", %{"min" => 0, "max" => 100})
      "not_a_number"
  """
  @spec clamp_and_format(String.t(), map() | nil) :: String.t()
  def clamp_and_format(value, config) when is_binary(value) and is_map(config) do
    case Float.parse(value) do
      {num, _} -> num |> clamp(config) |> format_number()
      :error -> value
    end
  end

  def clamp_and_format(value, _), do: value

  @doc """
  Parses a constraint value (from form params or config) into a number or nil.

      iex> parse_constraint("42")
      42

      iex> parse_constraint("")
      nil

      iex> parse_constraint(10)
      10
  """
  @spec parse_constraint(any()) :: number() | nil
  def parse_constraint(nil), do: nil
  def parse_constraint(""), do: nil
  def parse_constraint(val) when is_number(val), do: val

  def parse_constraint(val) when is_binary(val) do
    case Integer.parse(val) do
      {int, ""} -> int
      _ -> case Float.parse(val) do
             {num, _} -> num
             :error -> nil
           end
    end
  end

  @doc """
  Formats a number as a string, preferring integer representation
  when the float has no fractional part.

      iex> format_number(42.0)
      "42"

      iex> format_number(3.14)
      "3.14"
  """
  @spec format_number(number()) :: String.t()
  def format_number(num) when is_float(num) and trunc(num) == num,
    do: Integer.to_string(trunc(num))

  def format_number(num), do: to_string(num)

  # -- Private --

  defp clamp_bound(value, :min, bound) do
    case to_number(bound) do
      n when is_number(n) -> max(value, n)
      _ -> value
    end
  end

  defp clamp_bound(value, :max, bound) do
    case to_number(bound) do
      n when is_number(n) -> min(value, n)
      _ -> value
    end
  end

  defp to_number(nil), do: nil
  defp to_number(n) when is_number(n), do: n

  defp to_number(s) when is_binary(s) do
    case Float.parse(s) do
      {n, _} -> n
      :error -> nil
    end
  end
end
