defmodule Storyarn.Projects.SlugGenerator do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Projects.Project
  alias Storyarn.Repo

  @doc """
  Generates a unique slug for a project name within a workspace.
  """
  def generate_slug(workspace_id, name, suffix \\ nil) do
    base_slug =
      name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9\s-]/, "")
      |> String.replace(~r/\s+/, "-")
      |> String.replace(~r/-+/, "-")
      |> String.trim("-")

    slug = if suffix, do: "#{base_slug}-#{suffix}", else: base_slug

    if slug_available?(workspace_id, slug) do
      slug
    else
      generate_slug(workspace_id, name, generate_suffix())
    end
  end

  defp slug_available?(workspace_id, slug) do
    not Repo.exists?(
      from(p in Project, where: p.workspace_id == ^workspace_id and p.slug == ^slug)
    )
  end

  defp generate_suffix do
    :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
  end
end
