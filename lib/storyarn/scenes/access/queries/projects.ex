defmodule Storyarn.Scenes.Access.Queries.Projects do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Scenes.Access.Projections.ProjectMembershipRecord
  alias Storyarn.Scenes.Access.Projections.ProjectRecord
  alias Storyarn.Scenes.Access.Projections.WorkspaceMembershipRecord
  alias Storyarn.Scenes.Access.Projections.WorkspaceRecord

  @workspace_to_project_role %{
    "owner" => "editor",
    "admin" => "editor",
    "member" => "editor",
    "viewer" => "viewer"
  }

  def get_project(%{user: %{id: user_id}}, project_id)
      when is_integer(user_id) and user_id > 0 and is_integer(project_id) do
    project =
      Repo.one(
        from project in ProjectRecord,
          where: project.id == ^project_id and is_nil(project.deleted_at),
          preload: [:workspace]
      )

    authorize_project(project, user_id)
  end

  def get_project(_scope, _project_id), do: {:error, :not_found}

  def get_project_by_slugs(%{user: %{id: user_id}}, workspace_slug, project_slug)
      when is_integer(user_id) and user_id > 0 and is_binary(workspace_slug) and is_binary(project_slug) do
    project =
      Repo.one(
        from project in ProjectRecord,
          join: workspace in WorkspaceRecord,
          on: workspace.id == project.workspace_id,
          where:
            workspace.slug == ^workspace_slug and project.slug == ^project_slug and
              is_nil(project.deleted_at),
          preload: [workspace: workspace]
      )

    authorize_project(project, user_id)
  end

  def get_project_by_slugs(_scope, _workspace_slug, _project_slug), do: {:error, :not_found}

  defp authorize_project(nil, _user_id), do: {:error, :not_found}

  defp authorize_project(%ProjectRecord{} = project, user_id) do
    case effective_membership(project.id, user_id, project.workspace_id) do
      %ProjectMembershipRecord{} = membership -> {:ok, project, membership}
      nil -> {:error, :not_found}
    end
  end

  defp effective_membership(project_id, user_id, workspace_id) do
    case Repo.get_by(ProjectMembershipRecord, project_id: project_id, user_id: user_id) do
      %ProjectMembershipRecord{} = membership -> membership
      nil -> workspace_membership(project_id, user_id, workspace_id)
    end
  end

  defp workspace_membership(project_id, user_id, workspace_id) do
    case Repo.get_by(WorkspaceMembershipRecord, workspace_id: workspace_id, user_id: user_id) do
      %WorkspaceMembershipRecord{role: workspace_role} ->
        %ProjectMembershipRecord{
          project_id: project_id,
          user_id: user_id,
          role: Map.get(@workspace_to_project_role, workspace_role, "viewer")
        }

      nil ->
        nil
    end
  end
end
