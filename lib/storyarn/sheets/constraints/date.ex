defmodule Storyarn.Sheets.Constraints.Date do
  @moduledoc """
  Constraints for date blocks/columns: min_date, max_date.

  Date constraints are ISO 8601 date strings (e.g., "2025-01-01").
  """

  @doc """
  Extracts date constraints from a config map.

  Returns a constraints map with date strings, or nil if all are nil/empty.

      iex> extract(%{"min_date" => "2025-01-01", "max_date" => "2025-12-31"})
      %{"min_date" => "2025-01-01", "max_date" => "2025-12-31"}

      iex> extract(%{"min_date" => nil, "max_date" => nil})
      nil
  """
  @spec extract(map()) :: map() | nil
  def extract(config) when is_map(config) do
    constraints = %{
      "min_date" => parse_date(config["min_date"]),
      "max_date" => parse_date(config["max_date"])
    }

    if Enum.all?(Map.values(constraints), &is_nil/1), do: nil, else: constraints
  end

  def extract(_), do: nil

  @doc """
  Clamps a date string to the min_date/max_date constraints.

  Compares dates lexicographically (ISO 8601 strings sort correctly).
  Non-string values pass through unchanged.

      iex> clamp("2024-06-15", %{"min_date" => "2025-01-01", "max_date" => "2025-12-31"})
      "2025-01-01"

      iex> clamp("2026-03-01", %{"min_date" => "2025-01-01", "max_date" => "2025-12-31"})
      "2025-12-31"

      iex> clamp("2025-06-15", %{"min_date" => "2025-01-01", "max_date" => "2025-12-31"})
      "2025-06-15"
  """
  @spec clamp(any(), map() | nil) :: any()
  def clamp(value, config) when is_binary(value) and value != "" and is_map(config) do
    value
    |> clamp_min(config["min_date"])
    |> clamp_max(config["max_date"])
  end

  def clamp(value, _), do: value

  # -- Private --

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil
  defp parse_date(date) when is_binary(date), do: date
  defp parse_date(_), do: nil

  defp clamp_min(value, nil), do: value
  defp clamp_min(value, min) when is_binary(min) and value < min, do: min
  defp clamp_min(value, _), do: value

  defp clamp_max(value, nil), do: value
  defp clamp_max(value, max) when is_binary(max) and value > max, do: max
  defp clamp_max(value, _), do: value
end
