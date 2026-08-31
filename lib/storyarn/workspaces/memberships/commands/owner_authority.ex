defmodule Storyarn.Workspaces.Memberships.Commands.OwnerAuthority do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Workspaces.Memberships.Rules.OwnershipInvariant
  alias Storyarn.Workspaces.Workspace
  alias Storyarn.Workspaces.WorkspaceMembership

  @max_pg_bigint 9_223_372_036_854_775_807

  defguardp valid_id(id)
            when is_integer(id) and id > 0 and id <= @max_pg_bigint

  @type locked_state :: %{
          workspace: Workspace.t(),
          memberships: [WorkspaceMembership.t()],
          owner_membership: WorkspaceMembership.t()
        }

  @spec transact_as_owner(map(), pos_integer(), (locked_state() -> term())) :: term()
  def transact_as_owner(%{user: %{id: actor_id}}, workspace_id, fun)
      when valid_id(actor_id) and valid_id(workspace_id) and is_function(fun, 1) do
    Repo.transact(fn ->
      with {:ok, state} <- lock_and_validate(workspace_id),
           :ok <- authorize_owner(state.owner_membership, actor_id) do
        fun.(state)
      end
    end)
  end

  def transact_as_owner(_scope, _workspace_id, _fun), do: {:error, :unauthorized}

  @spec lock_and_validate(pos_integer()) ::
          {:ok, locked_state()} | {:error, :not_found | :ownership_invariant_violation}
  def lock_and_validate(workspace_id) when valid_id(workspace_id) do
    case lock_workspace(workspace_id) do
      %Workspace{} = workspace ->
        memberships = lock_memberships(workspace.id)

        case OwnershipInvariant.owner(workspace, memberships) do
          {:ok, owner_membership} ->
            {:ok,
             %{
               workspace: workspace,
               memberships: memberships,
               owner_membership: owner_membership
             }}

          error ->
            error
        end

      nil ->
        {:error, :not_found}
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

  defp authorize_owner(%WorkspaceMembership{user_id: actor_id}, actor_id), do: :ok
  defp authorize_owner(_owner_membership, _actor_id), do: {:error, :unauthorized}
end
