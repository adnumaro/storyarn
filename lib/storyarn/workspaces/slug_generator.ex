defmodule Storyarn.Workspaces.SlugGenerator do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Workspaces.Workspace

  @doc """
  Generates a unique slug for a workspace name.
  """
  def generate_slug(name, suffix \\ nil) do
    base_slug =
      name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9\s-]/, "")
      |> String.replace(~r/\s+/, "-")
      |> String.replace(~r/-+/, "-")
      |> String.trim("-")

    slug = if suffix, do: "#{base_slug}-#{suffix}", else: base_slug

    if slug_available?(slug) do
      slug
    else
      generate_slug(name, generate_suffix())
    end
  end

  defp slug_available?(slug) do
    not Repo.exists?(from(w in Workspace, where: w.slug == ^slug))
  end

  defp generate_suffix do
    :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
  end
end
