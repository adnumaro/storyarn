defmodule Storyarn.Projects.FlowVariableConstraints do
  @moduledoc """
  Flow-owned interpretation of variable constraints used by the evaluator and
  variable catalog.
  """

  @spec extract(String.t(), map()) :: map() | nil
  def extract("number", config) when is_map(config) do
    compact_constraints(%{
      "min" => parse_number(config["min"]),
      "max" => parse_number(config["max"]),
      "step" => parse_number(config["step"])
    })
  end

  def extract(type, config) when type in ["text", "rich_text"] and is_map(config) do
    compact_constraints(%{"max_length" => parse_number(config["max_length"])})
  end

  def extract(type, config) when type in ["select", "multi_select"] and is_map(config) do
    compact_constraints(%{"max_options" => parse_number(config["max_options"])})
  end

  def extract("date", config) when is_map(config) do
    compact_constraints(%{
      "min_date" => parse_date(config["min_date"]),
      "max_date" => parse_date(config["max_date"])
    })
  end

  def extract("boolean", config) when is_map(config) do
    case config["mode"] do
      mode when mode not in [nil, "two_state"] -> %{"mode" => mode}
      _default -> nil
    end
  end

  def extract(_type, _config), do: nil

  @spec clamp(term(), map() | nil, String.t()) :: term()
  def clamp(value, constraints, "number") when is_number(value) and is_map(constraints) do
    value
    |> clamp_min(constraints["min"])
    |> clamp_max(constraints["max"])
  end

  def clamp(value, %{"max_length" => maximum}, "text") when is_binary(value) and is_number(maximum) and maximum > 0 do
    String.slice(value, 0, trunc(maximum))
  end

  def clamp(value, _constraints, "rich_text"), do: value

  def clamp(value, %{"max_options" => maximum}, type)
      when is_list(value) and is_number(maximum) and maximum > 0 and type in ["select", "multi_select"] do
    Enum.take(value, trunc(maximum))
  end

  def clamp(value, constraints, "date") when is_binary(value) and value != "" and is_map(constraints) do
    value
    |> clamp_date_min(constraints["min_date"])
    |> clamp_date_max(constraints["max_date"])
  end

  def clamp(nil, %{"mode" => "tri_state"}, "boolean"), do: nil
  def clamp(nil, _constraints, "boolean"), do: false
  def clamp(value, _constraints, _type), do: value

  defp compact_constraints(constraints) do
    if Enum.all?(Map.values(constraints), &is_nil/1), do: nil, else: constraints
  end

  defp parse_number(nil), do: nil
  defp parse_number(""), do: nil
  defp parse_number(value) when is_number(value), do: value

  defp parse_number(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} ->
        integer

      _not_integer ->
        case Float.parse(value) do
          {number, _rest} -> number
          :error -> nil
        end
    end
  end

  defp parse_number(_value), do: nil

  defp parse_date(value) when is_binary(value) and value != "", do: value
  defp parse_date(_value), do: nil

  defp clamp_min(value, bound) when is_number(bound), do: max(value, bound)
  defp clamp_min(value, bound) when is_binary(bound), do: clamp_min(value, parse_number(bound))
  defp clamp_min(value, _bound), do: value

  defp clamp_max(value, bound) when is_number(bound), do: min(value, bound)
  defp clamp_max(value, bound) when is_binary(bound), do: clamp_max(value, parse_number(bound))
  defp clamp_max(value, _bound), do: value

  defp clamp_date_min(value, minimum) when is_binary(minimum) and value < minimum, do: minimum
  defp clamp_date_min(value, _minimum), do: value

  defp clamp_date_max(value, maximum) when is_binary(maximum) and value > maximum, do: maximum
  defp clamp_date_max(value, _maximum), do: value
end
