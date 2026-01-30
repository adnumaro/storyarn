defmodule Storyarn.Workspaces.Invitations do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Workspaces.{Memberships, Workspace, WorkspaceInvitation, WorkspaceNotifier}

  # Maximum invitations per user per workspace per hour
  @invitation_rate_limit 10
  @invitation_rate_limit_ms 60_000 * 60

  @doc """
  Lists pending invitations for a workspace.
  """
  def list_pending_invitations(workspace_id) do
    WorkspaceInvitation
    |> where(workspace_id: ^workspace_id)
    |> where([i], is_nil(i.accepted_at))
    |> where([i], i.expires_at > ^DateTime.utc_now())
    |> preload(:invited_by)
    |> order_by([i], desc: i.inserted_at)
    |> Repo.all()
  end

  @doc """
  Creates an invitation and sends the invitation email.
  """
  def create_invitation(%Workspace{} = workspace, invited_by, email, role \\ "member") do
    with :ok <- check_invitation_rate_limit(workspace.id, invited_by.id) do
      email = String.downcase(email)

      cond do
        member_exists?(workspace.id, email) ->
          {:error, :already_member}

        pending_invitation_exists?(workspace.id, email) ->
          {:error, :already_invited}

        true ->
          do_create_invitation(workspace, invited_by, email, role)
      end
    end
  end

  @doc """
  Gets an invitation by token.
  """
  def get_invitation_by_token(token) do
    case WorkspaceInvitation.verify_token_query(token) do
      {:ok, query} ->
        case Repo.one(query) do
          nil -> {:error, :invalid_token}
          invitation -> {:ok, invitation}
        end

      :error ->
        {:error, :invalid_token}
    end
  end

  @doc """
  Accepts an invitation and creates a membership for the user.
  """
  def accept_invitation(%WorkspaceInvitation{} = invitation, user) do
    cond do
      not is_nil(invitation.accepted_at) ->
        {:error, :already_accepted}

      DateTime.compare(invitation.expires_at, DateTime.utc_now()) == :lt ->
        {:error, :expired}

      String.downcase(user.email) != String.downcase(invitation.email) ->
        {:error, :email_mismatch}

      Memberships.get_membership(invitation.workspace_id, user.id) != nil ->
        {:error, :already_member}

      true ->
        do_accept_invitation(invitation, user)
    end
  end

  @doc """
  Revokes a pending invitation.
  """
  def revoke_invitation(%WorkspaceInvitation{} = invitation) do
    Repo.delete(invitation)
  end

  @doc """
  Gets a pending invitation by ID.
  """
  def get_pending_invitation(id) do
    WorkspaceInvitation
    |> where([i], i.id == ^id)
    |> where([i], is_nil(i.accepted_at))
    |> where([i], i.expires_at > ^DateTime.utc_now())
    |> Repo.one()
  end

  # Private helpers

  defp check_invitation_rate_limit(workspace_id, user_id) do
    key = "workspace_invitation:#{workspace_id}:#{user_id}"

    case Hammer.check_rate(key, @invitation_rate_limit_ms, @invitation_rate_limit) do
      {:allow, _count} -> :ok
      {:deny, _limit} -> {:error, :rate_limited}
    end
  end

  defp member_exists?(workspace_id, email) do
    from(m in Storyarn.Workspaces.WorkspaceMembership,
      join: u in assoc(m, :user),
      where: m.workspace_id == ^workspace_id,
      where: fragment("lower(?)", u.email) == ^email
    )
    |> Repo.exists?()
  end

  defp pending_invitation_exists?(workspace_id, email) do
    from(i in WorkspaceInvitation,
      where: i.workspace_id == ^workspace_id,
      where: fragment("lower(?)", i.email) == ^email,
      where: is_nil(i.accepted_at),
      where: i.expires_at > ^DateTime.utc_now()
    )
    |> Repo.exists?()
  end

  defp do_create_invitation(workspace, invited_by, email, role) do
    {encoded_token, invitation} =
      WorkspaceInvitation.build_invitation(workspace, invited_by, email, role)

    case Repo.insert(invitation) do
      {:ok, invitation} ->
        invitation = Repo.preload(invitation, [:workspace, :invited_by])
        WorkspaceNotifier.deliver_invitation(invitation, encoded_token)
        {:ok, invitation}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp do_accept_invitation(invitation, user) do
    Repo.transact(fn ->
      with {:ok, _invitation} <- mark_invitation_accepted(invitation),
           {:ok, membership} <-
             Memberships.create_membership(invitation.workspace_id, user.id, invitation.role) do
        {:ok, membership}
      else
        {:error, %Ecto.Changeset{} = changeset} ->
          handle_membership_error(changeset)

        error ->
          error
      end
    end)
  end

  defp handle_membership_error(%Ecto.Changeset{errors: errors} = changeset) do
    if Keyword.has_key?(errors, :workspace_id) do
      {:error, :already_member}
    else
      {:error, changeset}
    end
  end

  defp mark_invitation_accepted(invitation) do
    invitation
    |> Ecto.Changeset.change(accepted_at: DateTime.utc_now(:second))
    |> Repo.update()
  end
end
