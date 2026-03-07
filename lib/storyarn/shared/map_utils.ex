defmodule Storyarn.Shared.MapUtils do
  @moduledoc """
  Shared map utility functions.
  """

  @doc """
  Converts all atom keys in a map to string keys.
  Leaves string keys unchanged.
  """
  @spec stringify_keys(map()) :: map()
  def stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end

  @doc """
  Parses a value to an integer, returning nil for empty/unparseable values.
  """
  @spec parse_int(any()) :: integer() | nil
  def parse_int(""), do: nil
  def parse_int(nil), do: nil
  def parse_int(val) when is_integer(val), do: val

  def parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {int, ""} -> int
      _ -> nil
    end
  end

  @doc """
  Parses any value to a float for formula evaluation.
  Returns 0.0 for nil, unparseable, or non-numeric values.
  """
  @spec parse_to_number(any()) :: float()
  def parse_to_number(nil), do: 0.0
  def parse_to_number(n) when is_integer(n), do: n / 1
  def parse_to_number(n) when is_float(n), do: n

  def parse_to_number(s) when is_binary(s) do
    case Float.parse(s) do
      {n, _} -> n
      :error -> 0.0
    end
  end

  def parse_to_number(_), do: 0.0

  @doc """
  Formats a numeric result: truncates whole floats to integer.
  E.g. `10.0` → `10`, `3.14` → `3.14`. Passes non-floats through.
  """
  @spec format_number_result(number() | any()) :: number()
  def format_number_result(n) when is_float(n) do
    if n == Float.floor(n) and n >= -1.0e15 and n <= 1.0e15,
      do: trunc(n),
      else: n
  end

  def format_number_result(n), do: n
end
