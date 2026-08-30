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
  alias Storyarn.Workspaces.Memberships
  alias Storyarn.Workspaces.Workspace
  alias Storyarn.Workspaces.WorkspaceInvitation
  alias Storyarn.Workspaces.WorkspaceMembership

  @preload_after_insert [:workspace, :invited_by]
  @max_pg_bigint 9_223_372_036_854_775_807

  defguardp valid_id(id)
            when is_integer(id) and id > 0 and id <= @max_pg_bigint

  def execute(scope, workspace_id, email, role \\ "member")

  def execute(%{user: %{id: actor_id} = actor} = scope, workspace_id, email, role)
      when valid_id(actor_id) and valid_id(workspace_id) and is_binary(email) do
    normalized_email = Email.normalize(email)

    scope
    |> Memberships.transact_manage_members(workspace_id, fn %{workspace: workspace} ->
      with :ok <- check_invitation_rate_limit(workspace.id, actor.id) do
        persist_locked_invitation(workspace, actor, normalized_email, role, [])
      end
    end)
    |> finalize_invitation([])
  end

  def execute(_scope, _workspace_id, _email, _role), do: {:error, :unauthorized}

  def execute_admin(%Workspace{} = workspace, email, role, opts \\ []) do
    result =
      Repo.transact(fn ->
        with {:ok, locked_workspace} <- lock_workspace(workspace.id) do
          persist_locked_invitation(locked_workspace, nil, Email.normalize(email), role, opts)
        end
      end)

    finalize_invitation(result, opts)
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

  defp persist_locked_invitation(workspace, invited_by, email, role, opts) do
    {encoded_token, invitation} = Issuer.issue(workspace, invited_by, email, role)

    changeset =
      invitation
      |> invitation_changeset()
      |> Ecto.Changeset.unique_constraint(:email,
        name: "workspace_invitations_workspace_id_email_index"
      )

    if changeset.valid? do
      with :ok <- ensure_invitation_available(workspace.id, email),
           :ok <- normalize_limit_result(Commercial.can_invite_member?(workspace, email)),
           :ok <- delete_inactive_invitation(workspace.id, email),
           {:ok, invitation} <- insert_invitation(changeset),
           {:ok, job} <- InvitationQueue.enqueue(encoded_token, opts) do
        {:ok, {invitation, job}}
      end
    else
      {:error, changeset}
    end
  end

  defp finalize_invitation(result, opts) do
    case restore_limit_error(result) do
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

  defp lock_workspace(workspace_id) do
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
