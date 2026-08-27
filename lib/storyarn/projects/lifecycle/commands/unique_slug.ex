defmodule Storyarn.Projects.Lifecycle.Commands.UniqueSlug do
  @moduledoc """
  Allocates collision-resistant slugs inside a persistence scope.

  Normalization remains a pure domain rule in `Storyarn.Projects.NameNormalizer`;
  this command owns the database availability check and random retry suffix.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Projects.NameNormalizer
  alias Storyarn.Repo

  @spec generate(term(), keyword(), String.t(), String.t() | nil) :: String.t()
  def generate(queryable, scope, name, suffix \\ nil) do
    base_slug = NameNormalizer.slugify(name)
    slug = if suffix, do: "#{base_slug}-#{suffix}", else: base_slug

    if available?(queryable, scope, slug) do
      slug
    else
      generate(queryable, scope, name, generate_suffix())
    end
  end

  defp available?(queryable, scope, slug) do
    query = from(q in queryable, where: q.slug == ^slug)

    query =
      Enum.reduce(scope, query, fn {field, value}, scoped_query ->
        from(record in scoped_query, where: field(record, ^field) == ^value)
      end)

    not Repo.exists?(query)
  end

  defp generate_suffix do
    4 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
  end
end
