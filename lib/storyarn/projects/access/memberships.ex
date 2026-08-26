defmodule Storyarn.Projects.Memberships do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Projects.MembershipOperations
  alias Storyarn.Projects.Persistence.WorkspaceMembershipRecord, as: WorkspaceMembership
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.ProjectMembership
  alias Storyarn.Repo

  @config %{
    membership_schema: ProjectMembership,
    parent_schema: Project,
    parent_key: :project_id
  }

  # Workspace role → synthetic project role mapping
  @workspace_to_project_role %{
    "owner" => "editor",
    "admin" => "editor",
    "member" => "editor",
    "viewer" => "viewer"
  }

  def list_project_members(project_id), do: MembershipOperations.list_members(@config, project_id)

  def get_membership(project_id, user_id), do: MembershipOperations.get_membership(@config, project_id, user_id)

  @doc """
  Resolves the effective project role from a direct project role and a
  workspace role, with the same precedence as `get_effective_membership/3`:
  a direct project membership wins; otherwise the workspace role maps to a
  synthetic project role. Returns `nil` when the user has neither.
  """
  def effective_role(project_role, workspace_role)
  def effective_role(nil, nil), do: nil
  def effective_role(nil, workspace_role), do: Map.get(@workspace_to_project_role, workspace_role, "viewer")
  def effective_role(project_role, _workspace_role), do: project_role

  @doc """
  Gets the effective membership for a user on a project.

  First checks for a direct ProjectMembership. If none exists, falls back to
  the user's WorkspaceMembership and maps the workspace role to a synthetic
  project role (owner/admin/member → editor, viewer → viewer).

  Returns `%ProjectMembership{}` or `nil`.
  """
  def get_effective_membership(project_id, user_id, workspace_id) do
    case get_membership(project_id, user_id) do
      %ProjectMembership{} = pm ->
        pm

      nil ->
        case Repo.get_by(WorkspaceMembership, workspace_id: workspace_id, user_id: user_id) do
          %WorkspaceMembership{role: ws_role} ->
            project_role = Map.get(@workspace_to_project_role, ws_role, "viewer")

            %ProjectMembership{
              project_id: project_id,
              user_id: user_id,
              role: project_role
            }

          nil ->
            nil
        end
    end
  end

  def create_membership(project_id, user_id, role),
    do: MembershipOperations.create_membership(@config, project_id, user_id, role)

  def update_member_role(membership, role), do: MembershipOperations.update_member_role(@config, membership, role)

  def remove_member(membership), do: MembershipOperations.remove_member(membership)

  def authorize(%{user: %{id: user_id}}, project_id, action)
      when is_integer(project_id) and project_id > 0 and is_integer(user_id) and user_id > 0 do
    with %Project{} = project <-
           Repo.one(from(project in Project, where: project.id == ^project_id and is_nil(project.deleted_at))),
         %ProjectMembership{role: role} = membership <-
           get_effective_membership(project.id, user_id, project.workspace_id),
         true <- ProjectMembership.can?(role, action) do
      {:ok, project, membership}
    else
      nil -> {:error, :not_found}
      false -> {:error, :unauthorized}
    end
  end

  def authorize(_scope, _project_id, _action), do: {:error, :unauthorized}

  @doc false
  @spec authorize_locked(map(), pos_integer(), atom()) ::
          {:ok, Project.t(), ProjectMembership.t()}
          | {:error, :not_found | :unauthorized | :authorization_transaction_required}
  def authorize_locked(%{user: %{id: user_id}}, project_id, action)
      when is_integer(project_id) and project_id > 0 and is_integer(user_id) and user_id > 0 do
    if Repo.in_transaction?() do
      with %Project{} = project <- lock_project(project_id),
           %ProjectMembership{role: role} = membership <- locked_effective_membership(project, user_id),
           true <- ProjectMembership.can?(role, action) do
        {:ok, project, membership}
      else
        nil -> {:error, :not_found}
        false -> {:error, :unauthorized}
      end
    else
      {:error, :authorization_transaction_required}
    end
  end

  def authorize_locked(_scope, _project_id, _action), do: {:error, :unauthorized}

  defp lock_project(project_id) do
    Repo.one(
      from(project in Project,
        where: project.id == ^project_id and is_nil(project.deleted_at),
        lock: "FOR SHARE"
      )
    )
  end

  defp locked_effective_membership(%Project{} = project, user_id) do
    case lock_project_membership(project.id, user_id) do
      %ProjectMembership{} = membership -> membership
      nil -> lock_workspace_membership(project, user_id)
    end
  end

  defp lock_project_membership(project_id, user_id) do
    Repo.one(
      from(membership in ProjectMembership,
        where: membership.project_id == ^project_id and membership.user_id == ^user_id,
        lock: "FOR SHARE"
      )
    )
  end

  defp lock_workspace_membership(%Project{} = project, user_id) do
    case Repo.one(
           from(membership in WorkspaceMembership,
             where: membership.workspace_id == ^project.workspace_id and membership.user_id == ^user_id,
             lock: "FOR SHARE"
           )
         ) do
      %WorkspaceMembership{role: workspace_role} ->
        %ProjectMembership{
          project_id: project.id,
          user_id: user_id,
          role: Map.get(@workspace_to_project_role, workspace_role, "viewer")
        }

      nil ->
        nil
    end
  end
end
