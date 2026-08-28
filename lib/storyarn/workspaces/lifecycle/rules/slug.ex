defmodule Storyarn.Workspaces.Lifecycle.Rules.Slug do
  @moduledoc false

  @spec slugify(String.t() | nil) :: String.t()
  def slugify(name), do: normalize(name, "-", "")

  defp normalize(nil, _separator, _extra_chars), do: ""
  defp normalize("", _separator, _extra_chars), do: ""

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

  defp collapse_and_trim(value, separator, extra_chars) do
    value = String.replace(value, ~r/#{Regex.escape(separator)}+/, separator)

    value =
      if extra_chars == "" do
        value
      else
        Enum.reduce(String.graphemes(extra_chars), value, fn character, result ->
          String.replace(result, ~r/#{Regex.escape(character)}+/, character)
        end)
      end

    trim_chars = separator <> extra_chars
    String.replace(value, ~r/^[#{Regex.escape(trim_chars)}]+|[#{Regex.escape(trim_chars)}]+$/, "")
  end
end
