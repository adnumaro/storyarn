defmodule Storyarn.Sheets.Naming do
  @moduledoc """
  Sheet-owned name-to-identifier normalization.

  Duplicates the pieces of the shared name normalizer that Sheet writers use so
  a change elsewhere cannot alter Sheet variable and shortcut vocabulary.
  """

  @doc """
  Variable name: `"Health Points"` → `"health_points"`.
  Allows `[a-z0-9_.]` (dots for nested refs like `mc.jaime.health`).
  Returns `nil` for blank input.
  """
  def variablify(nil), do: nil
  def variablify(""), do: nil
  def variablify(name), do: normalize(name, "_", ".") || nil

  @doc """
  Entity shortcut: `"MC.Jaime"` → `"mc.jaime"`.
  Allows `[a-z0-9-.]` (dots preserved, spaces become hyphens).
  """
  def shortcutify(name), do: normalize(name, "-", ".")

  @doc """
  Returns the identifier to use when a name changes.

  - No current value → generate from the new name.
  - Referenced → keep the current value (avoid breaking refs).
  - Otherwise → regenerate from the new name.
  """
  def maybe_regenerate(current, new_name, referenced?, normalize_fn)

  def maybe_regenerate(nil, new_name, _referenced?, normalize_fn) do
    normalize_fn.(new_name)
  end

  def maybe_regenerate("", new_name, _referenced?, normalize_fn) do
    normalize_fn.(new_name)
  end

  def maybe_regenerate(current, _new_name, true, _normalize_fn) do
    current
  end

  def maybe_regenerate(_current, new_name, false, normalize_fn) do
    normalize_fn.(new_name)
  end

  defp normalize(nil, _sep, _extra), do: ""
  defp normalize("", _sep, _extra), do: ""

  defp normalize(name, separator, extra_chars) do
    allowed = "a-z0-9" <> Regex.escape(separator) <> Regex.escape(extra_chars)

    name
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
    |> String.replace(~r/[^#{allowed}\s]/, "")
    |> String.replace(~r/\s+/, separator)
    |> collapse_and_trim(separator, extra_chars)
  end

  defp collapse_and_trim(str, separator, extra_chars) do
    str = String.replace(str, ~r/#{Regex.escape(separator)}+/, separator)

    str =
      if extra_chars == "" do
        str
      else
        Enum.reduce(String.graphemes(extra_chars), str, fn char, acc ->
          String.replace(acc, ~r/#{Regex.escape(char)}+/, char)
        end)
      end

    trim_chars = separator <> extra_chars
    String.replace(str, ~r/^[#{Regex.escape(trim_chars)}]+|[#{Regex.escape(trim_chars)}]+$/, "")
  end
end
