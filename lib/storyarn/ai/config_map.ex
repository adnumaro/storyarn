defmodule Storyarn.AI.ConfigMap do
  @moduledoc false

  @spec normalize(term()) :: map()
  def normalize(value) when is_list(value), do: value |> Map.new() |> normalize()
  def normalize(value) when is_map(value), do: Map.new(value, fn {key, item} -> {to_string(key), item} end)
  def normalize(_value), do: %{}
end
