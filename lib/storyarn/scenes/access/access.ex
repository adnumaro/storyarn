defmodule Storyarn.Scenes.Access do
  @moduledoc """
  Scene-owned project access boundary.

  It exposes only the project identity and authorization facts required by
  Scene workflows, backed by consumer-local projections.
  """

  alias Storyarn.Scenes.Access.Queries.Projects

  defdelegate get_project(scope, project_id), to: Projects
  defdelegate get_project_by_slugs(scope, workspace_slug, project_slug), to: Projects
end
