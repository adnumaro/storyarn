defmodule Storyarn.Workspaces.Memberships.Commands.RemoveMember do
  @moduledoc false

  alias Storyarn.Repo
  alias Storyarn.Workspaces.Memberships.Commands.OwnerAuthority
  alias Storyarn.Workspaces.Memberships.Rules.OwnerProtection
  alias Storyarn.Workspaces.WorkspaceMembership

  @max_pg_bigint 9_223_372_036_854_775_807

  defguardp valid_id(id)
            when is_integer(id) and id > 0 and id <= @max_pg_bigint

  @spec remove(map(), integer(), integer()) ::
          {:ok, WorkspaceMembership.t()}
          | {:error,
             Ecto.Changeset.t()
             | :cannot_remove_owner
             | :not_found
             | :ownership_invariant_violation
             | :unauthorized}
  def remove(scope, workspace_id, membership_id) when valid_id(workspace_id) and valid_id(membership_id) do
    OwnerAuthority.transact_as_owner(scope, workspace_id, fn state ->
      with %WorkspaceMembership{} = locked_membership <- find_membership(state.memberships, membership_id),
           :ok <- OwnerProtection.allow_removal(locked_membership) do
        Repo.delete(locked_membership)
      else
        nil -> {:error, :not_found}
        error -> error
      end
    end)
  end

  def remove(_scope, _workspace_id, _membership_id), do: {:error, :not_found}

  defp find_membership(memberships, membership_id) do
    Enum.find(memberships, &(&1.id == membership_id))
  end
end
