defmodule Storyarn.Workspaces.Lifecycle.Queries.UniqueSlug do
  @moduledoc false

  alias Storyarn.Workspaces.Lifecycle.Queries.SlugAvailability
  alias Storyarn.Workspaces.Lifecycle.Rules.Slug

  @spec generate(String.t()) :: String.t()
  def generate(name), do: generate(name, nil)

  defp generate(name, suffix) do
    base_slug = Slug.slugify(name)
    slug = if suffix, do: "#{base_slug}-#{suffix}", else: base_slug

    if SlugAvailability.available?(slug) do
      slug
    else
      generate(name, generate_suffix())
    end
  end

  defp generate_suffix do
    4 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
  end
end
