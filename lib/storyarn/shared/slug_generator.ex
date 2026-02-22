defmodule Storyarn.Shared.SlugGenerator do
  @moduledoc """
  Shared slug generation utilities.

  Provides a parameterized slug generator that can check uniqueness
  against any Ecto schema with a `:slug` field.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Repo

  @doc """
  Generates a unique slug for a name.

  Takes a queryable (Ecto schema) and an optional scope as a keyword list
  of field/value pairs to filter uniqueness.

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

  @doc """
  Slugifies a name into a URL-friendly format.

  - Converts to lowercase
  - Replaces spaces with hyphens
  - Removes special characters (keeps alphanumeric and hyphens)
  - Collapses multiple hyphens
  - Trims leading/trailing hyphens
  """
  def slugify(name) do
    name
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.replace(~r/-+/, "-")
    |> String.trim("-")
  end

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
