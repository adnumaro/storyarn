defmodule Storyarn.AI.Governance.Queries.ProjectAccess do
  @moduledoc """
  AI-owned project access reads over Governance-local SQL projections.

  Direct project membership wins. Otherwise a workspace role is translated to
  the same synthetic project role the AI policy decision has always used.
  """

  import Ecto.Query, warn: false

  alias Storyarn.AI.Governance.Data.ProjectMembershipRecord, as: ProjectMembership
  alias Storyarn.AI.Governance.Data.ProjectRecord, as: Project
  alias Storyarn.AI.Governance.Data.WorkspaceMembershipRecord, as: WorkspaceMembership
  alias Storyarn.AI.Governance.Rules.ProjectPermissions
  alias Storyarn.Repo

  @spec get(Storyarn.AI.Governance.scope(), pos_integer()) ::
          {:ok, Project.t(), ProjectMembership.t()} | {:error, :not_found}
  def get(%{user: %{id: user_id}}, id) do
    project = Repo.one(from(project in Project, where: project.id == ^id and is_nil(project.deleted_at)))

    with %Project{} <- project,
         %ProjectMembership{} = membership <-
           effective_membership(project.id, user_id, project.workspace_id) do
      {:ok, project, membership}
    else
      nil -> {:error, :not_found}
    end
  end

  def get(%{user: _user}, _id), do: {:error, :not_found}

  @spec can?(String.t() | nil, atom()) :: boolean()
  defdelegate can?(role, action), to: ProjectPermissions, as: :allowed?

  @spec effective_role(String.t() | nil, String.t() | nil) :: String.t() | nil
  defdelegate effective_role(project_role, workspace_role), to: ProjectPermissions

  defp effective_membership(project_id, user_id, workspace_id) do
    case Repo.get_by(ProjectMembership, project_id: project_id, user_id: user_id) do
      %ProjectMembership{} = membership ->
        membership

      nil ->
        workspace_membership(project_id, user_id, workspace_id)
    end
  end

  defp workspace_membership(project_id, user_id, workspace_id) do
    case Repo.get_by(WorkspaceMembership, workspace_id: workspace_id, user_id: user_id) do
      %WorkspaceMembership{role: workspace_role} ->
        %ProjectMembership{
          project_id: project_id,
          user_id: user_id,
          role: ProjectPermissions.effective_role(nil, workspace_role)
        }

      nil ->
        nil
    end
  end
end
