defmodule Storyarn.Projects.SheetNaming do
  @moduledoc """
  Project-owned copy of the Sheet naming normalization used by import writes.

  Byte-identical to the Sheet tool's pipeline so imported labels produce the
  exact same variable names and slugs the editor would.
  """

  @doc "Normalizes a label into a variable name; nil on blank input."
  def variablify(nil), do: nil
  def variablify(""), do: nil
  def variablify(name), do: normalize(name, "_", ".") || nil

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
