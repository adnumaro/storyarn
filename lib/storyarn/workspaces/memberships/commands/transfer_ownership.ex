defmodule Storyarn.Workspaces.Memberships.Commands.TransferOwnership do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Commercial
  alias Storyarn.Repo
  alias Storyarn.Workspaces.Memberships.Commands.OwnerAuthority
  alias Storyarn.Workspaces.Memberships.Projections.UserRecord
  alias Storyarn.Workspaces.WorkspaceMembership

  @max_pg_bigint 9_223_372_036_854_775_807

  defguardp valid_id(id)
            when is_integer(id) and id > 0 and id <= @max_pg_bigint

  @type receipt :: %{
          required(:workspace_id) => pos_integer(),
          required(:previous_owner_id) => pos_integer(),
          required(:new_owner_id) => pos_integer(),
          required(:changed?) => boolean()
        }

  @type error_reason ::
          :not_found
          | :unauthorized
          | :target_not_member
          | :ownership_invariant_violation
          | :ownership_transfer_failed

  @spec transfer(map(), pos_integer(), pos_integer(), keyword()) ::
          {:ok, receipt()}
          | {:error, error_reason() | Ecto.Changeset.t()}
          | {:error, :limit_reached, map()}
  def transfer(scope, workspace_id, target_user_id, opts \\ [])

  def transfer(scope, workspace_id, target_user_id, opts)
      when valid_id(workspace_id) and valid_id(target_user_id) and is_list(opts) do
    scope
    |> OwnerAuthority.transact_as_owner(workspace_id, fn state ->
      transfer_locked(state, target_user_id, opts)
    end)
    |> restore_limit_error()
  end

  def transfer(_scope, _workspace_id, _target_user_id, _opts), do: {:error, :not_found}

  defp transfer_locked(%{workspace: workspace, owner_membership: owner}, target_user_id, _opts)
       when workspace.owner_id == target_user_id do
    {:ok, receipt(workspace.id, owner.user_id, target_user_id, false)}
  end

  defp transfer_locked(state, target_user_id, opts) do
    with %WorkspaceMembership{} = target_membership <-
           Enum.find(state.memberships, &(&1.user_id == target_user_id)),
         {:ok, target_user} <- lock_transfer_users(state.owner_membership.user_id, target_user_id),
         :ok <- normalize_capacity(Commercial.can_receive_workspace?(target_user)),
         {:ok, _previous_owner} <- change_role(state.owner_membership, "admin"),
         :ok <- run_after_owner_demotion(opts),
         {:ok, _new_owner} <- change_role(target_membership, "owner"),
         {:ok, _workspace} <- change_workspace_owner(state.workspace, target_user_id),
         :ok <- verify_postcondition(state.workspace.id, target_user_id) do
      {:ok,
       receipt(
         state.workspace.id,
         state.owner_membership.user_id,
         target_user_id,
         true
       )}
    else
      nil -> {:error, :target_not_member}
      error -> error
    end
  end

  defp lock_transfer_users(previous_owner_id, target_user_id) do
    user_ids = Enum.sort([previous_owner_id, target_user_id])

    users =
      Repo.all(
        from(user in UserRecord,
          where: user.id in ^user_ids,
          order_by: [asc: user.id],
          lock: "FOR UPDATE"
        )
      )

    case users do
      [_, %UserRecord{id: ^target_user_id} = target_user] -> {:ok, target_user}
      [%UserRecord{id: ^target_user_id} = target_user, _] -> {:ok, target_user}
      _missing_user -> {:error, :target_not_member}
    end
  end

  defp normalize_capacity(:ok), do: :ok

  defp normalize_capacity({:error, :limit_reached, details}) do
    {:error, {:limit_reached, details}}
  end

  defp change_role(membership, role) do
    membership
    |> WorkspaceMembership.changeset(%{role: role})
    |> Repo.update()
  end

  defp change_workspace_owner(workspace, target_user_id) do
    workspace
    |> Ecto.Changeset.change(owner_id: target_user_id)
    |> Repo.update()
  end

  defp run_after_owner_demotion(opts) do
    callback = Keyword.get(opts, :after_owner_demotion, fn -> :ok end)

    case callback.() do
      :ok -> :ok
      {:error, _reason} = error -> error
      _unexpected -> {:error, :ownership_transfer_failed}
    end
  end

  defp verify_postcondition(workspace_id, target_user_id) do
    case OwnerAuthority.lock_and_validate(workspace_id) do
      {:ok, %{workspace: %{owner_id: ^target_user_id}, owner_membership: %{user_id: ^target_user_id}}} ->
        :ok

      {:ok, _unexpected_owner} ->
        {:error, :ownership_invariant_violation}

      error ->
        error
    end
  end

  defp receipt(workspace_id, previous_owner_id, new_owner_id, changed?) do
    %{
      workspace_id: workspace_id,
      previous_owner_id: previous_owner_id,
      new_owner_id: new_owner_id,
      changed?: changed?
    }
  end

  defp restore_limit_error({:error, {:limit_reached, details}}) do
    {:error, :limit_reached, details}
  end

  defp restore_limit_error(result), do: result
end
