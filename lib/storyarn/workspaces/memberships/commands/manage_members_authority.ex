defmodule Storyarn.Workspaces.Memberships.Commands.ManageMembersAuthority do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Workspaces.Memberships.Queries.ReadOnly
  alias Storyarn.Workspaces.Memberships.Rules.OwnershipInvariant
  alias Storyarn.Workspaces.Memberships.Rules.Permissions
  alias Storyarn.Workspaces.Workspace
  alias Storyarn.Workspaces.WorkspaceMembership

  @max_pg_bigint 9_223_372_036_854_775_807

  @type locked_state :: %{
          workspace: Workspace.t(),
          memberships: [WorkspaceMembership.t()],
          actor_membership: WorkspaceMembership.t()
        }

  defguardp valid_id(id)
            when is_integer(id) and id > 0 and id <= @max_pg_bigint

  # `action` is `:manage_members` or `:remove_members`: what `fun` does, so a
  # read-only workspace can refuse it.
  @spec transact(map(), pos_integer(), atom(), (locked_state() -> term())) :: term()
  def transact(%{user: %{id: actor_id}}, workspace_id, action, fun)
      when valid_id(actor_id) and valid_id(workspace_id) and action in [:manage_members, :remove_members] and
             is_function(fun, 1) do
    Repo.transact(fn ->
      case lock_workspace(workspace_id) do
        %Workspace{} = workspace ->
          authorize_locked(workspace, actor_id, action, fun)

        nil ->
          {:error, :not_found}
      end
    end)
  end

  def transact(_scope, _workspace_id, _action, _fun), do: {:error, :unauthorized}

  defp authorize_locked(workspace, actor_id, action, fun) do
    memberships = lock_memberships(workspace.id)

    with {:ok, _owner_membership} <- OwnershipInvariant.owner(workspace, memberships),
         %WorkspaceMembership{} = actor_membership <-
           Enum.find(memberships, &(&1.user_id == actor_id)),
         true <- Permissions.allowed?(actor_membership.role, action),
         :ok <- ReadOnly.ensure_allowed(workspace.id, action) do
      fun.(%{
        workspace: workspace,
        memberships: memberships,
        actor_membership: actor_membership
      })
    else
      nil -> {:error, :unauthorized}
      false -> {:error, :unauthorized}
      {:error, reason} -> {:error, reason}
    end
  end

  defp lock_workspace(workspace_id) do
    Repo.one(
      from(workspace in Workspace,
        where: workspace.id == ^workspace_id,
        lock: "FOR UPDATE"
      )
    )
  end

  defp lock_memberships(workspace_id) do
    Repo.all(
      from(membership in WorkspaceMembership,
        where: membership.workspace_id == ^workspace_id,
        order_by: [asc: membership.user_id, asc: membership.id],
        lock: "FOR UPDATE"
      )
    )
  end
end
