defmodule Storyarn.Projects.Memberships do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Projects.Access.Rules.OwnershipInvariant
  alias Storyarn.Projects.MembershipOperations
  alias Storyarn.Projects.Persistence.WorkspaceMembershipRecord, as: WorkspaceMembership
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.ProjectMembership
  alias Storyarn.Repo

  @max_pg_bigint 9_223_372_036_854_775_807

  defguardp valid_id(id)
            when is_integer(id) and id > 0 and id <= @max_pg_bigint

  @config %{
    membership_schema: ProjectMembership,
    parent_key: :project_id
  }

  # Workspace role → synthetic project role mapping
  @workspace_to_project_role %{
    "owner" => "editor",
    "admin" => "editor",
    "member" => "editor",
    "viewer" => "viewer"
  }

  @canonical_owner_actions [:manage_project, :manage_members, :run_bulk_ai]

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

  def update_member_role(scope, project_id, membership_id, role) when valid_id(project_id) and valid_id(membership_id) do
    Repo.transact(fn ->
      with {:ok, _project, _actor_membership} <-
             authorize_locked(scope, project_id, :manage_members, :update),
           %ProjectMembership{} = membership <- lock_membership(project_id, membership_id) do
        MembershipOperations.update_member_role(@config, membership, role)
      else
        nil -> {:error, :not_found}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  def update_member_role(_scope, _project_id, _membership_id, _role), do: {:error, :not_found}

  def remove_member(scope, project_id, membership_id) when valid_id(project_id) and valid_id(membership_id) do
    Repo.transact(fn ->
      with {:ok, _project, _actor_membership} <-
             authorize_locked(scope, project_id, :manage_members, :update),
           %ProjectMembership{} = membership <- lock_membership(project_id, membership_id) do
        MembershipOperations.remove_member(membership)
      else
        nil -> {:error, :not_found}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  def remove_member(_scope, _project_id, _membership_id), do: {:error, :not_found}

  def authorize(%{user: %{id: user_id}}, project_id, action) when valid_id(project_id) and valid_id(user_id) do
    with %Project{} = project <-
           Repo.one(from(project in Project, where: project.id == ^project_id and is_nil(project.deleted_at))),
         {:ok, %ProjectMembership{} = membership} <-
           authorize_membership(project, user_id, action) do
      {:ok, project, membership}
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def authorize(_scope, _project_id, _action), do: {:error, :unauthorized}

  @doc false
  @spec authorize_locked(map(), pos_integer(), atom()) ::
          {:ok, Project.t(), ProjectMembership.t()}
          | {:error, :not_found | :unauthorized | :ownership_invariant_violation | :authorization_transaction_required}
  def authorize_locked(scope, project_id, action), do: authorize_locked(scope, project_id, action, :share)

  @doc false
  @spec authorize_locked(map(), pos_integer(), atom(), :share | :update) ::
          {:ok, Project.t(), ProjectMembership.t()}
          | {:error, :not_found | :unauthorized | :ownership_invariant_violation | :authorization_transaction_required}
  def authorize_locked(%{user: %{id: user_id}}, project_id, action, lock_mode)
      when valid_id(project_id) and valid_id(user_id) and lock_mode in [:share, :update] do
    if Repo.in_transaction?() do
      with %Project{} = project <- lock_project(project_id, lock_mode),
           {:ok, %ProjectMembership{} = membership} <-
             authorize_membership_locked(project, user_id, action, lock_mode) do
        {:ok, project, membership}
      else
        nil -> {:error, :not_found}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :authorization_transaction_required}
    end
  end

  def authorize_locked(_scope, _project_id, _action, _lock_mode), do: {:error, :unauthorized}

  defp authorize_membership_locked(project, user_id, action, lock_mode) when action in @canonical_owner_actions do
    with :ok <- ensure_canonical_owner_actor(project, user_id),
         memberships = lock_all_project_memberships(project.id, lock_mode),
         {:ok, %ProjectMembership{user_id: ^user_id} = membership} <-
           OwnershipInvariant.owner(project, memberships) do
      {:ok, membership}
    else
      {:ok, _different_owner} -> {:error, :unauthorized}
      {:error, reason} -> {:error, reason}
    end
  end

  defp authorize_membership_locked(project, user_id, action, _lock_mode) do
    with %ProjectMembership{role: role} = membership <- locked_effective_membership(project, user_id),
         true <- ProjectMembership.can?(role, action) do
      {:ok, membership}
    else
      nil -> {:error, :not_found}
      false -> {:error, :unauthorized}
    end
  end

  defp ensure_canonical_owner_actor(%Project{owner_id: user_id}, user_id), do: :ok
  defp ensure_canonical_owner_actor(%Project{}, _user_id), do: {:error, :unauthorized}

  defp authorize_membership(project, user_id, action) when action in @canonical_owner_actions do
    with %ProjectMembership{} = membership <-
           get_effective_membership(project.id, user_id, project.workspace_id),
         owner_memberships = list_project_owner_memberships_for_authorization(project.id),
         {:ok, %ProjectMembership{user_id: ^user_id}} <-
           OwnershipInvariant.owner(project, owner_memberships) do
      {:ok, membership}
    else
      nil -> {:error, :not_found}
      {:ok, _different_owner} -> {:error, :unauthorized}
      {:error, reason} -> {:error, reason}
    end
  end

  defp authorize_membership(project, user_id, action) do
    with %ProjectMembership{role: role} = membership <-
           get_effective_membership(project.id, user_id, project.workspace_id),
         true <- ProjectMembership.can?(role, action) do
      {:ok, membership}
    else
      nil -> {:error, :not_found}
      false -> {:error, :unauthorized}
    end
  end

  defp list_project_owner_memberships_for_authorization(project_id) do
    Repo.all(
      from(membership in ProjectMembership,
        where: membership.project_id == ^project_id and membership.role == "owner",
        order_by: [asc: membership.user_id, asc: membership.id]
      )
    )
  end

  defp lock_project(project_id, :share) do
    Repo.one(
      from(project in Project,
        where: project.id == ^project_id and is_nil(project.deleted_at),
        lock: "FOR SHARE"
      )
    )
  end

  defp lock_project(project_id, :update) do
    Repo.one(
      from(project in Project,
        where: project.id == ^project_id and is_nil(project.deleted_at),
        lock: "FOR UPDATE"
      )
    )
  end

  defp lock_all_project_memberships(project_id, :share) do
    Repo.all(
      from(membership in ProjectMembership,
        where: membership.project_id == ^project_id,
        order_by: [asc: membership.user_id, asc: membership.id],
        lock: "FOR SHARE"
      )
    )
  end

  defp lock_all_project_memberships(project_id, :update) do
    Repo.all(
      from(membership in ProjectMembership,
        where: membership.project_id == ^project_id,
        order_by: [asc: membership.user_id, asc: membership.id],
        lock: "FOR UPDATE"
      )
    )
  end

  defp lock_membership(project_id, membership_id) do
    Repo.one(
      from(membership in ProjectMembership,
        where: membership.id == ^membership_id and membership.project_id == ^project_id,
        lock: "FOR UPDATE"
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
