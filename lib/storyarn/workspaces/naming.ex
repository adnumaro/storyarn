defmodule Storyarn.Workspaces.Naming do
  @moduledoc """
  Workspace-owned copy of the shared naming pipeline used for workspace slugs.

  Byte-identical to the retired shared normalizer so workspace slugs generate
  exactly as before.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Workspaces.Workspace

  @doc "Generates a globally unique workspace slug with a collision suffix."
  def generate_unique_slug(name, suffix \\ nil) do
    base_slug = slugify(name)

    slug = if suffix, do: "#{base_slug}-#{suffix}", else: base_slug

    if slug_available?(slug) do
      slug
    else
      generate_unique_slug(name, generate_suffix())
    end
  end

  @doc ~s(URL slug: `"My Workspace"` -> `"my-workspace"`. Allows only `[a-z0-9-]`.)
  def slugify(name), do: normalize(name, "-", "")

  defp slug_available?(slug) do
    not Repo.exists?(from(workspace in Workspace, where: workspace.slug == ^slug))
  end

  defp generate_suffix do
    4 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
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
