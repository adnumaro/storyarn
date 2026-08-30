defmodule Storyarn.Projects.ProjectCrud do
  @moduledoc false

  alias Storyarn.Projects.Lifecycle.Commands.ProjectCommands
  alias Storyarn.Projects.Lifecycle.Queries.ProjectQueries

  defdelegate list_projects(scope), to: ProjectQueries
  defdelegate list_projects_for_workspace(workspace_id, scope), to: ProjectQueries
  defdelegate get_project(scope, id), to: ProjectQueries
  defdelegate reload_project(scope, id), to: ProjectQueries
  defdelegate get_project!(id), to: ProjectQueries
  defdelegate get_project_by_slugs(scope, workspace_slug, project_slug), to: ProjectQueries
  defdelegate list_deleted_projects(workspace_id), to: ProjectQueries
  defdelegate get_deleted_project(workspace_id, project_id), to: ProjectQueries
  defdelegate auto_versioning_enabled?(project_id, entity_type), to: ProjectQueries

  defdelegate create_project(scope, attrs), to: ProjectCommands
  defdelegate lock_and_check_workspace_capacity(workspace_id), to: ProjectCommands
  defdelegate change_project(project, attrs \\ %{}), to: ProjectCommands
  defdelegate change_new_project(), to: ProjectCommands
  defdelegate change_new_project(project, attrs \\ %{}), to: ProjectCommands
  defdelegate update_project(scope, project_id, attrs), to: ProjectCommands
  defdelegate touch_project(project_id, at \\ nil), to: ProjectCommands
  defdelegate delete_project(scope, project_id), to: ProjectCommands
  defdelegate permanently_delete_project(project), to: ProjectCommands
end
