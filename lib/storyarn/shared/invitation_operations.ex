defmodule Storyarn.Shared.InvitationOperations do
  @moduledoc """
  Generic invitation operations shared by Projects and Workspaces.

  Parameterized by a config map containing:
  - `invitation_schema` — e.g., ProjectInvitation or WorkspaceInvitation
  - `membership_schema` — e.g., ProjectMembership or WorkspaceMembership
  - `parent_key` — e.g., :project_id or :workspace_id
  - `rate_limit_context` — e.g., "project" or "workspace"
  - `parent_assoc` — e.g., :project or :workspace
  - `template` — e.g., :project_invitation
  - `invitation_path_prefix` — e.g., "/projects/invitations" or "/workspaces/invitations"
  - `memberships_module` — e.g., Projects.Memberships or Workspaces.Memberships
  - `preload_after_insert` — e.g., [:project, :invited_by] or [:workspace, :invited_by]
  """

  import Ecto.Query, warn: false

  alias Storyarn.Billing
  alias Storyarn.RateLimiter
  alias Storyarn.Repo
  alias Storyarn.Shared.InvitationNotifier
  alias Storyarn.Shared.TimeHelpers

  @doc """
  Lists pending invitations for a parent entity.
  """
  def list_pending_invitations(config, parent_id) do
    config.invitation_schema
    |> where([i], field(i, ^config.parent_key) == ^parent_id)
    |> where([i], is_nil(i.accepted_at))
    |> where([i], i.expires_at > ^TimeHelpers.now())
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
          create_if_within_limits(config, parent, invited_by, email, role)
      end
    end
  end

  @doc """
  Creates an admin-initiated invitation (no rate limit, no invited_by user).

  Used by `Storyarn.Release.invite_member/5` for CLI-approved invitations.
  """
  def create_admin_invitation(config, parent, email, role, opts \\ []) do
    parent_id = Map.fetch!(parent, :id)
    email = String.downcase(email)

    cond do
      member_exists?(config, parent_id, email) ->
        {:error, :already_member}

      pending_invitation_exists?(config, parent_id, email) ->
        {:error, :already_invited}

      true ->
        with :ok <- Billing.can_invite_member?(parent) do
          do_create_invitation(config, parent, nil, email, role, opts)
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

      DateTime.compare(invitation.expires_at, TimeHelpers.now()) == :lt ->
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
    |> where([i], i.expires_at > ^TimeHelpers.now())
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
      where: i.expires_at > ^TimeHelpers.now()
    )
    |> Repo.exists?()
  end

  defp create_if_within_limits(config, parent, invited_by, email, role) do
    with :ok <- Billing.can_invite_member?(parent) do
      do_create_invitation(config, parent, invited_by, email, role)
    end
  end

  defp do_create_invitation(config, parent, invited_by, email, role, opts \\ []) do
    {encoded_token, invitation} =
      config.invitation_schema.build_invitation(parent, invited_by, email, role)

    changeset =
      invitation
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.unique_constraint(:email,
        name: invitation_unique_index(config.parent_key)
      )

    case Repo.insert(changeset) do
      {:ok, invitation} ->
        invitation = Repo.preload(invitation, config.preload_after_insert)
        url = invitation_url(config.invitation_path_prefix, encoded_token)
        InvitationNotifier.deliver_invitation(config, invitation, url, opts)
        {:ok, invitation}

      {:error, %Ecto.Changeset{errors: errors}} = error ->
        if Keyword.has_key?(errors, :email) do
          {:error, :already_invited}
        else
          error
        end
    end
  end

  defp invitation_unique_index(:project_id),
    do: "project_invitations_project_id_email_index"

  defp invitation_unique_index(:workspace_id),
    do: "workspace_invitations_workspace_id_email_index"

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

  defp invitation_url(path_prefix, token) do
    Storyarn.Urls.base_url() <> path_prefix <> "/" <> token
  end

  defp mark_invitation_accepted(invitation) do
    invitation
    |> Ecto.Changeset.change(accepted_at: TimeHelpers.now())
    |> Repo.update()
  end
end
