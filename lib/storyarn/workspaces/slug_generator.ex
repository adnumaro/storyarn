defmodule Storyarn.Workspaces.SlugGenerator do
  @moduledoc false

  alias Storyarn.Shared.SlugGenerator
  alias Storyarn.Workspaces.Workspace

  @doc """
  Generates a unique slug for a workspace name.
  """
  def generate_slug(name, _suffix \\ nil) do
    SlugGenerator.generate_unique_slug(Workspace, [], name)
  end
end
