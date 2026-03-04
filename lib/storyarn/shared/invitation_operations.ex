defmodule Storyarn.Shared.InvitationOperations do
  @moduledoc """
  Generic invitation operations shared by Projects and Workspaces.

  Parameterized by a config map containing:
  - `invitation_schema` — e.g., ProjectInvitation or WorkspaceInvitation
  - `membership_schema` — e.g., ProjectMembership or WorkspaceMembership
  - `parent_key` — e.g., :project_id or :workspace_id
  - `rate_limit_context` — e.g., "project" or "workspace"
  - `notifier_module` — e.g., ProjectNotifier or WorkspaceNotifier
  - `memberships_module` — e.g., Projects.Memberships or Workspaces.Memberships
  - `preload_after_insert` — e.g., [:project, :invited_by] or [:workspace, :invited_by]
  """

  import Ecto.Query, warn: false

  alias Storyarn.RateLimiter
  alias Storyarn.Repo

  @doc """
  Lists pending invitations for a parent entity.
  """
  def list_pending_invitations(config, parent_id) do
    config.invitation_schema
    |> where([i], field(i, ^config.parent_key) == ^parent_id)
    |> where([i], is_nil(i.accepted_at))
    |> where([i], i.expires_at > ^DateTime.utc_now())
    |> preload(:invited_by)
    |> order_by([i], desc: i.inserted_at)
    |> Repo.all()
  end

  @doc """
  Creates an invitation and sends the invitation email.
  """
  def create_invitation(config, parent, invited_by, email, role) do
    parent_id = Map.fetch!(parent, :id)

    with :ok <- check_invitation_rate_limit(config, parent_id, invited_by.id) do
      email = String.downcase(email)

      cond do
        member_exists?(config, parent_id, email) ->
          {:error, :already_member}

        pending_invitation_exists?(config, parent_id, email) ->
          {:error, :already_invited}

        true ->
          do_create_invitation(config, parent, invited_by, email, role)
      end
    end
  end

  @doc """
  Gets an invitation by token.
  """
  def get_invitation_by_token(config, token) do
    case config.invitation_schema.verify_token_query(token) do
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
  def accept_invitation(config, invitation, user) do
    parent_id = Map.fetch!(invitation, config.parent_key)

    cond do
      not is_nil(invitation.accepted_at) ->
        {:error, :already_accepted}

      DateTime.compare(invitation.expires_at, DateTime.utc_now()) == :lt ->
        {:error, :expired}

      String.downcase(user.email) != String.downcase(invitation.email) ->
        {:error, :email_mismatch}

      config.memberships_module.get_membership(parent_id, user.id) != nil ->
        {:error, :already_member}

      true ->
        do_accept_invitation(config, invitation, user)
    end
  end

  @doc """
  Revokes a pending invitation.
  """
  def revoke_invitation(invitation) do
    Repo.delete(invitation)
  end

  @doc """
  Gets a pending invitation by ID.
  """
  def get_pending_invitation(config, id) do
    config.invitation_schema
    |> where([i], i.id == ^id)
    |> where([i], is_nil(i.accepted_at))
    |> where([i], i.expires_at > ^DateTime.utc_now())
    |> Repo.one()
  end

  # Private helpers

  defp check_invitation_rate_limit(config, parent_id, user_id) do
    RateLimiter.check_invitation(config.rate_limit_context, parent_id, user_id)
  end

  defp member_exists?(config, parent_id, email) do
    from(m in config.membership_schema,
      join: u in assoc(m, :user),
      where: field(m, ^config.parent_key) == ^parent_id,
      where: fragment("lower(?)", u.email) == ^email
    )
    |> Repo.exists?()
  end

  defp pending_invitation_exists?(config, parent_id, email) do
    from(i in config.invitation_schema,
      where: field(i, ^config.parent_key) == ^parent_id,
      where: fragment("lower(?)", i.email) == ^email,
      where: is_nil(i.accepted_at),
      where: i.expires_at > ^DateTime.utc_now()
    )
    |> Repo.exists?()
  end

  defp do_create_invitation(config, parent, invited_by, email, role) do
    {encoded_token, invitation} =
      config.invitation_schema.build_invitation(parent, invited_by, email, role)

    case Repo.insert(invitation) do
      {:ok, invitation} ->
        invitation = Repo.preload(invitation, config.preload_after_insert)
        config.notifier_module.deliver_invitation(invitation, encoded_token)
        {:ok, invitation}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp do_accept_invitation(config, invitation, user) do
    parent_id = Map.fetch!(invitation, config.parent_key)

    Repo.transact(fn ->
      with {:ok, _invitation} <- mark_invitation_accepted(invitation),
           {:ok, membership} <-
             config.memberships_module.create_membership(parent_id, user.id, invitation.role) do
        {:ok, membership}
      else
        {:error, %Ecto.Changeset{} = changeset} ->
          handle_membership_error(config, changeset)

        error ->
          error
      end
    end)
  end

  defp handle_membership_error(config, %Ecto.Changeset{errors: errors} = changeset) do
    if Keyword.has_key?(errors, config.parent_key) do
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
