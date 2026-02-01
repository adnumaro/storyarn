defmodule Storyarn.Projects.Invitations do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Projects.{
    Memberships,
    Project,
    ProjectInvitation,
    ProjectMembership,
    ProjectNotifier
  }

  alias Storyarn.RateLimiter
  alias Storyarn.Repo

  @doc """
  Lists pending invitations for a project.
  """
  def list_pending_invitations(project_id) do
    ProjectInvitation
    |> where(project_id: ^project_id)
    |> where([i], is_nil(i.accepted_at))
    |> where([i], i.expires_at > ^DateTime.utc_now())
    |> preload(:invited_by)
    |> order_by([i], desc: i.inserted_at)
    |> Repo.all()
  end

  @doc """
  Creates an invitation and sends the invitation email.
  """
  def create_invitation(%Project{} = project, invited_by, email, role \\ "editor") do
    with :ok <- check_invitation_rate_limit(project.id, invited_by.id) do
      email = String.downcase(email)

      cond do
        member_exists?(project.id, email) ->
          {:error, :already_member}

        pending_invitation_exists?(project.id, email) ->
          {:error, :already_invited}

        true ->
          do_create_invitation(project, invited_by, email, role)
      end
    end
  end

  @doc """
  Gets an invitation by token.
  """
  def get_invitation_by_token(token) do
    case ProjectInvitation.verify_token_query(token) do
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
  def accept_invitation(%ProjectInvitation{} = invitation, user) do
    cond do
      not is_nil(invitation.accepted_at) ->
        {:error, :already_accepted}

      DateTime.compare(invitation.expires_at, DateTime.utc_now()) == :lt ->
        {:error, :expired}

      String.downcase(user.email) != String.downcase(invitation.email) ->
        {:error, :email_mismatch}

      Memberships.get_membership(invitation.project_id, user.id) != nil ->
        {:error, :already_member}

      true ->
        do_accept_invitation(invitation, user)
    end
  end

  @doc """
  Revokes a pending invitation.
  """
  def revoke_invitation(%ProjectInvitation{} = invitation) do
    Repo.delete(invitation)
  end

  # Private helpers

  defp check_invitation_rate_limit(project_id, user_id) do
    RateLimiter.check_invitation("project", project_id, user_id)
  end

  defp member_exists?(project_id, email) do
    from(m in ProjectMembership,
      join: u in assoc(m, :user),
      where: m.project_id == ^project_id,
      where: fragment("lower(?)", u.email) == ^email
    )
    |> Repo.exists?()
  end

  defp pending_invitation_exists?(project_id, email) do
    from(i in ProjectInvitation,
      where: i.project_id == ^project_id,
      where: fragment("lower(?)", i.email) == ^email,
      where: is_nil(i.accepted_at),
      where: i.expires_at > ^DateTime.utc_now()
    )
    |> Repo.exists?()
  end

  defp do_create_invitation(project, invited_by, email, role) do
    {encoded_token, invitation} =
      ProjectInvitation.build_invitation(project, invited_by, email, role)

    case Repo.insert(invitation) do
      {:ok, invitation} ->
        invitation = Repo.preload(invitation, [:project, :invited_by])
        ProjectNotifier.deliver_invitation(invitation, encoded_token)
        {:ok, invitation}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp do_accept_invitation(invitation, user) do
    Repo.transact(fn ->
      with {:ok, _invitation} <- mark_invitation_accepted(invitation),
           {:ok, membership} <-
             Memberships.create_membership(invitation.project_id, user.id, invitation.role) do
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
    if Keyword.has_key?(errors, :project_id) do
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
