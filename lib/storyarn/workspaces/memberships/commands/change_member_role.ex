defmodule Storyarn.Workspaces.Memberships.Commands.ChangeMemberRole do
  @moduledoc false

  alias Storyarn.Commercial
  alias Storyarn.Repo
  alias Storyarn.Workspaces.Memberships.Commands.OwnerAuthority
  alias Storyarn.Workspaces.Memberships.Rules.OwnerProtection
  alias Storyarn.Workspaces.WorkspaceMembership

  @max_pg_bigint 9_223_372_036_854_775_807

  defguardp valid_id(id)
            when is_integer(id) and id > 0 and id <= @max_pg_bigint

  @spec change(map(), integer(), integer(), String.t()) ::
          {:ok, WorkspaceMembership.t()}
          | {:error,
             Ecto.Changeset.t()
             | :cannot_assign_owner_role
             | :cannot_change_owner_role
             | :not_found
             | :ownership_invariant_violation
             | :unauthorized}
          | {:error, :limit_reached, map()}
  def change(%{user: %{id: actor_id}} = scope, workspace_id, membership_id, role)
      when valid_id(workspace_id) and valid_id(membership_id) do
    scope
    |> OwnerAuthority.transact_as_owner(workspace_id, :manage_members, fn state ->
      with %WorkspaceMembership{} = locked_membership <- find_membership(state.memberships, membership_id),
           :ok <- OwnerProtection.allow_role_change(locked_membership),
           :ok <- OwnerProtection.allow_role_assignment(role),
           :ok <- check_editor_seat(state.workspace, locked_membership, role, actor_id) do
        locked_membership
        |> WorkspaceMembership.changeset(%{role: role})
        |> Repo.update()
      else
        nil -> {:error, :not_found}
        error -> error
      end
    end)
    |> restore_limit_error()
  end

  def change(_scope, _workspace_id, _membership_id, _role), do: {:error, :not_found}

  # Turning a viewer into an editor can take a new seat of the account.
  defp check_editor_seat(workspace, membership, role, actor_id) do
    %{user: %{email: email}} = Repo.preload(membership, :user)

    case Commercial.check_editor_seat(workspace, email, role, actor_id) do
      {:error, :limit_reached, details} -> {:error, {:limit_reached, details}}
      result -> result
    end
  end

  defp restore_limit_error({:error, {:limit_reached, details}}), do: {:error, :limit_reached, details}
  defp restore_limit_error(result), do: result

  defp find_membership(memberships, membership_id) do
    Enum.find(memberships, &(&1.id == membership_id))
  end
end
