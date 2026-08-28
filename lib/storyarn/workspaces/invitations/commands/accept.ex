defmodule Storyarn.Workspaces.Invitations.Commands.Accept do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Platform
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo
  alias Storyarn.Workspaces.Invitations.Projections.UserRecord
  alias Storyarn.Workspaces.Invitations.Rules.Acceptance
  alias Storyarn.Workspaces.Memberships
  alias Storyarn.Workspaces.Workspace
  alias Storyarn.Workspaces.WorkspaceInvitation

  def execute(%WorkspaceInvitation{} = invitation, user) do
    case invitation |> Repo.preload(:workspace) |> Map.fetch!(:workspace) do
      nil -> {:error, :invitation_unavailable}
      workspace -> accept_available_invitation(workspace, invitation, user)
    end
  end

  defp accept_available_invitation(workspace, invitation, user) do
    fn -> accept_invitation_transaction(workspace, invitation, user) end
    |> Repo.transact()
    |> restore_limit_error()
  end

  defp accept_invitation_transaction(workspace, invitation, user) do
    with {:ok, locked_workspace} <- lock_workspace(workspace),
         {:ok, current_invitation} <- lock_invitation(invitation),
         {:ok, current_user} <- lock_user(user),
         :ok <- Acceptance.validate(current_invitation, current_user),
         :ok <-
           current_invitation.workspace_id
           |> Memberships.get_membership(current_user.id)
           |> Acceptance.ensure_not_member(),
         :ok <- normalize_limit_result(Platform.can_accept_member?(locked_workspace, current_user.email)),
         {:ok, _invitation} <- mark_invitation_accepted(current_invitation),
         {:ok, membership} <-
           Memberships.create_membership(
             current_invitation.workspace_id,
             current_user.id,
             current_invitation.role
           ) do
      {:ok, membership}
    else
      {:error, reason} when reason in [:not_found, :user_unavailable] ->
        {:error, :invitation_unavailable}

      {:error, %Ecto.Changeset{} = changeset} ->
        handle_membership_error(changeset)

      error ->
        error
    end
  end

  defp lock_workspace(%Workspace{id: workspace_id}) do
    case Repo.one(
           from(workspace in Workspace,
             where: workspace.id == ^workspace_id,
             lock: "FOR UPDATE"
           )
         ) do
      nil -> {:error, :not_found}
      workspace -> {:ok, workspace}
    end
  end

  defp lock_invitation(invitation) do
    case Repo.one(
           from(current_invitation in WorkspaceInvitation,
             where: current_invitation.id == ^invitation.id,
             lock: "FOR UPDATE"
           )
         ) do
      nil -> {:error, stale_invitation_changeset(invitation)}
      current_invitation -> {:ok, current_invitation}
    end
  end

  defp lock_user(%{id: user_id}) do
    case Repo.one(from(user in UserRecord, where: user.id == ^user_id, lock: "FOR UPDATE")) do
      nil -> {:error, :user_unavailable}
      user -> {:ok, user}
    end
  end

  defp stale_invitation_changeset(invitation) do
    invitation
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.add_error(:id, "is no longer available")
  end

  defp handle_membership_error(%Ecto.Changeset{errors: errors} = changeset) do
    if Keyword.has_key?(errors, :workspace_id) do
      {:error, :already_member}
    else
      {:error, changeset}
    end
  end

  defp normalize_limit_result({:error, :limit_reached, details}) do
    {:error, {:limit_reached, details}}
  end

  defp normalize_limit_result(result), do: result

  defp restore_limit_error({:error, {:limit_reached, details}}) do
    {:error, :limit_reached, details}
  end

  defp restore_limit_error(result), do: result

  defp mark_invitation_accepted(invitation) do
    invitation
    |> Ecto.Changeset.change(accepted_at: TimeHelpers.now())
    |> Repo.update(stale_error_field: :id, stale_error_message: "is no longer available")
  end
end
