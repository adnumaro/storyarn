defmodule Storyarn.Platform.Kernel.MapAccess do
  @moduledoc "Business-neutral normalization for maps crossing serialization boundaries."

  @spec stringify_keys(map()) :: map()
  def stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      pair -> pair
    end)
  end

  @spec get_flexible(map(), atom()) :: term()
  def get_flexible(map, field) when is_map(map) and is_atom(field) do
    case Map.fetch(map, field) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(field))
    end
  end
end
