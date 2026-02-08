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
end
