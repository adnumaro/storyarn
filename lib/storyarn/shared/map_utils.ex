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
end
