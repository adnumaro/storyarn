defmodule Storyarn.Workspaces.Memberships.Queries.Authorize do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Workspaces.Memberships.Queries.Members
  alias Storyarn.Workspaces.Memberships.Rules.OwnershipInvariant
  alias Storyarn.Workspaces.Memberships.Rules.Permissions
  alias Storyarn.Workspaces.Workspace
  alias Storyarn.Workspaces.WorkspaceMembership

  @canonical_owner_actions [:manage_workspace, :run_bulk_ai]
  @ownership_sensitive_actions [:manage_workspace, :manage_members, :run_bulk_ai]

  @spec call(%{user: %{id: integer()}}, integer(), atom()) ::
          {:ok, Workspace.t(), map()}
          | {:error, :not_found | :unauthorized | :ownership_invariant_violation}
  def call(%{user: user}, workspace_id, action) do
    with %Workspace{} = workspace <- Repo.get(Workspace, workspace_id),
         %WorkspaceMembership{} = membership <- Members.get(workspace_id, user.id),
         :ok <- authorize_membership(workspace, membership, user.id, action) do
      {:ok, workspace, membership}
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp authorize_membership(workspace, membership, user_id, action) when action in @ownership_sensitive_actions do
    owner_memberships = list_owner_memberships_for_authorization(workspace.id)

    with {:ok, owner_membership} <- OwnershipInvariant.owner(workspace, owner_memberships),
         :ok <- authorize_canonical_owner(action, owner_membership, user_id),
         true <- Permissions.allowed?(membership.role, action) do
      :ok
    else
      false -> {:error, :unauthorized}
      {:error, reason} -> {:error, reason}
    end
  end

  defp authorize_membership(_workspace, membership, _user_id, action) do
    if Permissions.allowed?(membership.role, action),
      do: :ok,
      else: {:error, :unauthorized}
  end

  defp authorize_canonical_owner(action, %{user_id: user_id}, user_id) when action in @canonical_owner_actions, do: :ok

  defp authorize_canonical_owner(action, _owner_membership, _user_id) when action in @canonical_owner_actions,
    do: {:error, :unauthorized}

  defp authorize_canonical_owner(:manage_members, _owner_membership, _user_id), do: :ok

  defp list_owner_memberships_for_authorization(workspace_id) do
    Repo.all(
      from(membership in WorkspaceMembership,
        where: membership.workspace_id == ^workspace_id and membership.role == "owner",
        order_by: [asc: membership.user_id, asc: membership.id]
      )
    )
  end
end
