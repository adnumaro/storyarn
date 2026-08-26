defmodule Storyarn.Platform.Notifications.ProjectAccess do
  @moduledoc """
  Notification-owned project access reads over the shared project tables.

  ENG-92 copy of the Projects access read the delivery paths depend on:
  effective membership resolution (direct project role first, then the
  workspace role mapped to a synthetic project role).
  """

  import Ecto.Query, warn: false

  alias Storyarn.Platform.Notifications.Data.ProjectMembershipRecord, as: ProjectMembership
  alias Storyarn.Platform.Notifications.Data.ProjectRecord, as: Project
  alias Storyarn.Platform.Notifications.Data.WorkspaceMembershipRecord, as: WorkspaceMembership
  alias Storyarn.Repo

  @workspace_to_project_role %{
    "owner" => "editor",
    "admin" => "editor",
    "member" => "editor",
    "viewer" => "viewer"
  }

  @doc """
  Gets a project by ID with the effective membership for the scope's user.
  """
  def get_project(%{user: user}, id) do
    project = Repo.one(from(p in Project, where: p.id == ^id and is_nil(p.deleted_at)))

    with %Project{} <- project,
         %ProjectMembership{} = membership <- get_effective_membership(project.id, user.id, project.workspace_id) do
      {:ok, project, membership}
    else
      nil -> {:error, :not_found}
    end
  end

  defp get_effective_membership(project_id, user_id, workspace_id) do
    case Repo.get_by(ProjectMembership, project_id: project_id, user_id: user_id) do
      %ProjectMembership{} = membership ->
        membership

      nil ->
        case Repo.get_by(WorkspaceMembership, workspace_id: workspace_id, user_id: user_id) do
          %WorkspaceMembership{role: workspace_role} ->
            %ProjectMembership{
              project_id: project_id,
              user_id: user_id,
              role: Map.get(@workspace_to_project_role, workspace_role, "viewer")
            }

          nil ->
            nil
        end
    end
  end
end
