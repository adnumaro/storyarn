defmodule Storyarn.Workspaces.Invitations.Commands.Revoke do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo
  alias Storyarn.Workspaces.Memberships
  alias Storyarn.Workspaces.Workspace
  alias Storyarn.Workspaces.WorkspaceInvitation

  @max_pg_bigint 9_223_372_036_854_775_807

  defguardp valid_id(id)
            when is_integer(id) and id > 0 and id <= @max_pg_bigint

  def execute(scope, workspace_id, invitation_id, opts \\ [])

  def execute(scope, workspace_id, invitation_id, opts)
      when valid_id(workspace_id) and valid_id(invitation_id) and is_list(opts) do
    Memberships.transact_manage_members(scope, workspace_id, fn _state ->
      case lock_pending_invitation(workspace_id, invitation_id) do
        %WorkspaceInvitation{} = invitation -> delete_invitation(invitation, opts)
        nil -> {:error, :not_found}
      end
    end)
  end

  def execute(_scope, _workspace_id, _invitation_id, _opts), do: {:error, :not_found}

  @doc false
  def execute_delivery_cleanup(workspace_id, invitation_id) when valid_id(workspace_id) and valid_id(invitation_id) do
    Repo.transact(fn ->
      with %Workspace{} <- lock_workspace(workspace_id),
           %WorkspaceInvitation{} = invitation <-
             lock_pending_invitation(workspace_id, invitation_id) do
        Repo.delete(invitation)
      else
        _unavailable -> {:error, :not_found}
      end
    end)
  end

  def execute_delivery_cleanup(_workspace_id, _invitation_id), do: {:error, :not_found}

  defp delete_invitation(invitation, opts) do
    with {:ok, deleted} <- Repo.delete(invitation),
         :ok <- run_after_delete(opts) do
      {:ok, deleted}
    end
  end

  defp run_after_delete(opts) do
    callback = Keyword.get(opts, :after_delete, fn -> :ok end)

    case callback.() do
      :ok -> :ok
      {:error, _reason} = error -> error
      _unexpected -> {:error, :invitation_revoke_failed}
    end
  end

  defp lock_pending_invitation(workspace_id, invitation_id) do
    Repo.one(
      from(invitation in WorkspaceInvitation,
        where:
          invitation.id == ^invitation_id and invitation.workspace_id == ^workspace_id and
            is_nil(invitation.accepted_at) and invitation.expires_at > ^TimeHelpers.now(),
        lock: "FOR UPDATE"
      )
    )
  end

  defp lock_workspace(workspace_id) do
    Repo.one(
      from(workspace in Workspace,
        where: workspace.id == ^workspace_id,
        lock: "FOR UPDATE"
      )
    )
  end
end
