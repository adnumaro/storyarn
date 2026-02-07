defmodule Storyarn.Projects.SlugGenerator do
  @moduledoc false

  alias Storyarn.Projects.Project
  alias Storyarn.Shared.SlugGenerator

  @doc """
  Generates a unique slug for a project name within a workspace.
  """
  def generate_slug(workspace_id, name, _suffix \\ nil) do
    SlugGenerator.generate_unique_slug(Project, [workspace_id: workspace_id], name)
  end
end
