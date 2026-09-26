defmodule Storyarn.Projects.Access.Commands.TransferOwnership do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Commercial
  alias Storyarn.Projects.Access.Commands.OwnerAuthority
  alias Storyarn.Projects.Persistence.UserRecord, as: User
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.ProjectMembership
  alias Storyarn.Repo

  @max_pg_bigint 9_223_372_036_854_775_807

  defguardp valid_id(id)
            when is_integer(id) and id > 0 and id <= @max_pg_bigint

  @type error_reason ::
          :not_found
          | :unauthorized
          | :target_not_member
          | :ownership_invariant_violation
          | :ownership_transfer_failed
          | :seat_requires_account_owner

  @spec transfer(map(), pos_integer(), pos_integer(), keyword()) ::
          {:ok, Project.t()}
          | {:error, error_reason() | Ecto.Changeset.t()}
          | {:error, :limit_reached, map()}
  def transfer(scope, project_id, target_user_id, opts \\ [])

  def transfer(%{user: %{id: actor_id}} = scope, project_id, target_user_id, opts)
      when valid_id(project_id) and valid_id(target_user_id) and is_list(opts) do
    scope
    |> OwnerAuthority.transact_as_owner(project_id, fn state ->
      transfer_locked(state, target_user_id, actor_id, opts)
    end)
    |> restore_limit_error()
  end

  def transfer(_scope, _project_id, _target_user_id, _opts), do: {:error, :not_found}

  defp transfer_locked(%{project: project}, target_user_id, _actor_id, _opts) when project.owner_id == target_user_id do
    {:ok, project}
  end

  defp transfer_locked(state, target_user_id, actor_id, opts) do
    with %ProjectMembership{} = target_membership <-
           Enum.find(state.memberships, &(&1.user_id == target_user_id)),
         {:ok, target} <- lock_transfer_users(state.owner_membership.user_id, target_user_id),
         :ok <- check_editor_seat(state.project, target, actor_id),
         {:ok, _former_owner} <- change_role(state.owner_membership, "editor"),
         :ok <- run_after_owner_demotion(opts),
         {:ok, _new_owner} <- change_role(target_membership, "owner"),
         {:ok, project} <- change_project_owner(state.project, target_user_id),
         :ok <- verify_postcondition(project.id, target_user_id) do
      {:ok, project}
    else
      nil -> {:error, :target_not_member}
      error -> error
    end
  end

  defp lock_transfer_users(previous_owner_id, target_user_id) do
    user_ids = Enum.sort([previous_owner_id, target_user_id])

    # Keep this lock at KEY SHARE. Template publication locks the participating
    # users before it reaches the project, while ownership transfer already
    # holds the project before reaching the users. Strengthening this to UPDATE
    # would therefore turn those opposite acquisition paths into a deadlock;
    # KEY SHARE is sufficient to keep the user rows present for the FK writes.
    users =
      Repo.all(
        from(user in User,
          where: user.id in ^user_ids,
          order_by: [asc: user.id],
          lock: "FOR KEY SHARE"
        )
      )

    if Enum.map(users, & &1.id) == user_ids do
      {:ok, Enum.find(users, &(&1.id == target_user_id))}
    else
      {:error, :target_not_member}
    end
  end

  # A viewer who becomes the owner takes an editor seat of the workspace
  # owner's account.
  defp check_editor_seat(project, target, actor_id) do
    case Commercial.check_editor_seat(project, target.email, "owner", actor_id) do
      {:error, :limit_reached, details} -> {:error, {:limit_reached, details}}
      result -> result
    end
  end

  defp restore_limit_error({:error, {:limit_reached, details}}), do: {:error, :limit_reached, details}
  defp restore_limit_error(result), do: result

  defp change_role(membership, role) do
    membership
    |> ProjectMembership.changeset(%{role: role})
    |> Repo.update()
  end

  defp change_project_owner(%Project{} = project, target_user_id) do
    project
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

  defp verify_postcondition(project_id, target_user_id) do
    case OwnerAuthority.lock_and_validate(project_id) do
      {:ok, %{project: %{owner_id: ^target_user_id}, owner_membership: %{user_id: ^target_user_id}}} ->
        :ok

      {:ok, _unexpected_owner} ->
        {:error, :ownership_invariant_violation}

      error ->
        error
    end
  end
end
