defmodule Storyarn.Workspaces.Invitations.Commands.Create do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Commercial
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo
  alias Storyarn.Workspaces.Invitations.Adapters.Jobs.InvitationQueue
  alias Storyarn.Workspaces.Invitations.Queries.Pending
  alias Storyarn.Workspaces.Invitations.RateLimits
  alias Storyarn.Workspaces.Invitations.Rules.Email
  alias Storyarn.Workspaces.Invitations.Tokens.Issuer
  alias Storyarn.Workspaces.Workspace
  alias Storyarn.Workspaces.WorkspaceInvitation
  alias Storyarn.Workspaces.WorkspaceMembership

  @preload_after_insert [:workspace, :invited_by]

  def execute(%Workspace{} = workspace, invited_by, email, role \\ "member") do
    with :ok <- check_invitation_rate_limit(workspace.id, invited_by.id) do
      create_serialized_invitation(workspace, invited_by, Email.normalize(email), role)
    end
  end

  def execute_admin(%Workspace{} = workspace, email, role, opts \\ []) do
    create_serialized_invitation(workspace, nil, Email.normalize(email), role, opts)
  end

  defp check_invitation_rate_limit(workspace_id, user_id) do
    RateLimits.check(workspace_id, user_id)
  end

  defp member_exists?(workspace_id, email) do
    Repo.exists?(
      from(membership in WorkspaceMembership,
        join: user in assoc(membership, :user),
        where: membership.workspace_id == ^workspace_id,
        where: fragment("lower(?)", user.email) == ^email
      )
    )
  end

  defp create_serialized_invitation(workspace, invited_by, email, role, opts \\ []) do
    {encoded_token, invitation} = Issuer.issue(workspace, invited_by, email, role)

    changeset =
      invitation
      |> invitation_changeset()
      |> Ecto.Changeset.unique_constraint(:email,
        name: "workspace_invitations_workspace_id_email_index"
      )

    if changeset.valid? do
      workspace
      |> transact_invitation(email, changeset, encoded_token, opts)
      |> restore_limit_error()
    else
      {:error, changeset}
    end
  end

  defp transact_invitation(workspace, email, changeset, encoded_token, opts) do
    result =
      Repo.transact(fn ->
        with {:ok, locked_workspace} <- lock_workspace(workspace),
             :ok <- ensure_invitation_available(locked_workspace.id, email),
             :ok <- normalize_limit_result(Commercial.can_invite_member?(locked_workspace, email)),
             :ok <- delete_inactive_invitation(locked_workspace.id, email),
             {:ok, invitation} <- insert_invitation(changeset),
             {:ok, job} <- InvitationQueue.enqueue(encoded_token, opts) do
          {:ok, {invitation, job}}
        end
      end)

    case result do
      {:ok, {invitation, job}} ->
        InvitationQueue.wake_after_commit(job, opts)
        {:ok, invitation}

      error ->
        error
    end
  end

  defp ensure_invitation_available(workspace_id, email) do
    cond do
      member_exists?(workspace_id, email) -> {:error, :already_member}
      Pending.exists?(workspace_id, email) -> {:error, :already_invited}
      true -> :ok
    end
  end

  defp delete_inactive_invitation(workspace_id, email) do
    WorkspaceInvitation
    |> where([invitation], invitation.workspace_id == ^workspace_id)
    |> where([invitation], fragment("lower(?)", invitation.email) == ^email)
    |> where(
      [invitation],
      not is_nil(invitation.accepted_at) or invitation.expires_at <= ^TimeHelpers.now()
    )
    |> Repo.delete_all()

    :ok
  end

  defp insert_invitation(changeset) do
    case Repo.insert(changeset) do
      {:ok, invitation} ->
        invitation = Repo.preload(invitation, @preload_after_insert)
        {:ok, invitation}

      {:error, %Ecto.Changeset{errors: errors}} = error ->
        if Keyword.has_key?(errors, :email) do
          {:error, :already_invited}
        else
          error
        end
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

  defp invitation_changeset(invitation) do
    attrs = %{
      workspace_id: invitation.workspace_id,
      email: invitation.email,
      role: invitation.role,
      invited_by_id: invitation.invited_by_id
    }

    %WorkspaceInvitation{}
    |> WorkspaceInvitation.changeset(attrs)
    |> Ecto.Changeset.put_change(:token, invitation.token)
    |> Ecto.Changeset.put_change(:expires_at, invitation.expires_at)
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
end
