defmodule Storyarn.Shared.NameNormalizer do
  @moduledoc """
  Centralised name-to-identifier conversion.

  Every identifier in Storyarn (URL slugs, variable names, shortcuts)
  is derived from a human-readable name through the same pipeline:

  1. Unicode NFD decomposition + combining-mark removal (á → a)
  2. Lowercasing
  3. Stripping characters outside the allowed set
  4. Collapsing/trimming the chosen separator

  Public functions expose the three flavours used across the app:

  - `slugify/1`     — URL slugs (`"my-project"`)
  - `variablify/1`  — variable names (`"health_points"`, allows `.`)
  - `shortcutify/1` — entity shortcuts (`"mc.jaime"`, allows `.`)
  """

  import Ecto.Query, warn: false

  alias Storyarn.Repo

  # ---------------------------------------------------------------------------
  # Slug generation (URL-safe identifiers)
  # ---------------------------------------------------------------------------

  @doc """
  Generates a unique slug for a name, checking against an Ecto schema.

  ## Examples

      generate_unique_slug(Workspace, [], "My Workspace")
      generate_unique_slug(Project, [workspace_id: 1], "My Project")
  """
  def generate_unique_slug(queryable, scope, name, suffix \\ nil) do
    base_slug = slugify(name)

    slug = if suffix, do: "#{base_slug}-#{suffix}", else: base_slug

    if slug_available?(queryable, scope, slug) do
      slug
    else
      generate_unique_slug(queryable, scope, name, generate_suffix())
    end
  end

  # ---------------------------------------------------------------------------
  # Public normalizers
  # ---------------------------------------------------------------------------

  @doc """
  URL slug: `"My Project"` → `"my-project"`.
  Allows only `[a-z0-9-]`.
  """
  def slugify(name), do: normalize(name, "-", "")

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

  # ---------------------------------------------------------------------------
  # Conditional regeneration
  # ---------------------------------------------------------------------------

  @doc """
  Returns the identifier to use when a name changes.

  - No current value → generate from the new name.
  - Referenced → keep the current value (avoid breaking refs).
  - Otherwise → regenerate from the new name.

  `normalize_fn` is one of `&slugify/1`, `&variablify/1`, or `&shortcutify/1`.
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

  # ---------------------------------------------------------------------------
  # Core pipeline (private)
  # ---------------------------------------------------------------------------

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
      if extra_chars != "" do
        Enum.reduce(String.graphemes(extra_chars), str, fn char, acc ->
          String.replace(acc, ~r/#{Regex.escape(char)}+/, char)
        end)
      else
        str
      end

    trim_chars = separator <> extra_chars
    String.replace(str, ~r/^[#{Regex.escape(trim_chars)}]+|[#{Regex.escape(trim_chars)}]+$/, "")
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp slug_available?(queryable, scope, slug) do
    query = from(q in queryable, where: q.slug == ^slug)

    query =
      Enum.reduce(scope, query, fn {field, value}, q ->
        from(r in q, where: field(r, ^field) == ^value)
      end)

    not Repo.exists?(query)
  end

  defp generate_suffix do
    :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
  end
end
