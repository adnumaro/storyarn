defmodule Storyarn.Projects.Assets.StorageKey do
  @moduledoc "Pure validation for canonical Project asset-storage keys and prefixes."

  @spec canonical?(term()) :: boolean()
  def canonical?(key) when is_binary(key) do
    key != "" and
      String.valid?(key) and
      not String.contains?(key, [<<0>>, "\\"]) and
      canonical_segments?(String.split(key, "/", trim: false))
  end

  def canonical?(_key), do: false

  @spec canonical_prefix?(term()) :: boolean()
  def canonical_prefix?(prefix) when is_binary(prefix) do
    String.ends_with?(prefix, "/") and not String.ends_with?(prefix, "//") and
      canonical?(String.trim_trailing(prefix, "/"))
  end

  def canonical_prefix?(_prefix), do: false

  defp canonical_segments?(segments) do
    segments != [] and
      Enum.all?(segments, fn segment ->
        segment != "" and segment not in [".", ".."]
      end)
  end
end
