defmodule Storyarn.Projects.Imports.Parsers.Yarn.Shortcut do
  @moduledoc false

  @max_length 50

  @spec unique(String.t(), MapSet.t(String.t()), String.t()) :: String.t()
  def unique(base, used, fallback \\ "character")
      when is_binary(base) and is_struct(used, MapSet) and is_binary(fallback) do
    base = bounded_base(base, @max_length, fallback)

    if MapSet.member?(used, base) do
      next_unique(base, used, fallback)
    else
      base
    end
  end

  defp next_unique(base, used, fallback) do
    2
    |> Stream.iterate(&(&1 + 1))
    |> Enum.find_value(fn suffix ->
      suffix = "-#{suffix}"
      available = @max_length - String.length(suffix)
      candidate = bounded_base(base, available, fallback) <> suffix

      if MapSet.member?(used, candidate), do: nil, else: candidate
    end)
  end

  # `String.trim_trailing/2` strips the literal two-char pair ".-", not a
  # character class — a bound that cut right after a separator left a shortcut
  # ending in `-` or `.`, which `Validations.validate_shortcut/1` rejects at
  # materialization, after the user already accepted the preview.
  defp bounded_base(base, max_length, fallback) do
    base
    |> String.slice(0, max_length)
    |> String.replace(~r/[.\-]+$/, "")
    |> fallback_if_empty(fallback, max_length)
  end

  defp fallback_if_empty("", fallback, max_length) do
    fallback
    |> String.slice(0, max_length)
    |> String.replace(~r/[.\-]+$/, "")
  end

  defp fallback_if_empty(base, _fallback, _max_length), do: base
end
