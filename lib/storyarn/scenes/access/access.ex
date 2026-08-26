defmodule Storyarn.Scenes.Access do
  @moduledoc false

  alias Storyarn.Scenes.Access.Queries.Projects

  defdelegate get_project(scope, project_id), to: Projects
  defdelegate get_project_by_slugs(scope, workspace_slug, project_slug), to: Projects
end
