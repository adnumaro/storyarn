defmodule Storyarn.Workspaces.Invitations do
  @moduledoc """
  Workspace invitation lifecycle.

  Absorbed the workspace half of the retired shared invitation machinery,
  byte-for-byte over Workspace-owned records. Billing seat checks and the
  durable delivery worker remain reviewed coordination seams.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Billing
  alias Storyarn.Platform.RateLimiter
  alias Storyarn.Platform.Shared.EncryptedBinary
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo
  alias Storyarn.Workers.DeliverInvitationWorker
  alias Storyarn.Workspaces.InvitationNotifier
  alias Storyarn.Workspaces.Memberships
  alias Storyarn.Workspaces.Persistence.UserRecord
  alias Storyarn.Workspaces.Workspace
  alias Storyarn.Workspaces.WorkspaceInvitation
  alias Storyarn.Workspaces.WorkspaceMembership

  require Logger

  @invitation_path_prefix "/workspaces/invitations"
  @rate_limit_context "workspace"
  @preload_after_insert [:workspace, :invited_by]

  @doc """
  Lists pending invitations for a workspace.
  """
  def list_pending_invitations(workspace_id) do
    WorkspaceInvitation
    |> where([i], i.workspace_id == ^workspace_id)
    |> where([i], is_nil(i.accepted_at))
    |> where([i], i.expires_at > ^TimeHelpers.now())
    |> preload(:invited_by)
    |> order_by([i], desc: i.updated_at)
    |> Repo.all()
  end

  @doc """
  Creates an invitation and queues the invitation email for durable delivery.
  """
  def create_invitation(%Workspace{} = workspace, invited_by, email, role \\ "member") do
    with :ok <- check_invitation_rate_limit(workspace.id, invited_by.id) do
      create_serialized_invitation(workspace, invited_by, normalize_email(email), role)
    end
  end

  @doc """
  Creates an admin-initiated invitation (no rate limit, no invited_by user).

  Used by `Storyarn.Platform.Release.invite_member/5` for CLI-approved invitations.
  """
  def create_admin_invitation(%Workspace{} = workspace, email, role, opts \\ []) do
    create_serialized_invitation(workspace, nil, normalize_email(email), role, opts)
  end

  @doc false
  def deliver_invitation_email(encoded_token, opts \\ []) do
    case get_invitation_by_token(encoded_token) do
      {:ok, invitation} ->
        url = invitation_url(encoded_token)
        InvitationNotifier.deliver_invitation(invitation, url, opts)

      {:error, :invalid_token} ->
        {:cancel, :invitation_unavailable}
    end
  end

  @doc false
  def cancel_invitation_delivery(encoded_token) do
    case get_invitation_by_token(encoded_token) do
      {:ok, invitation} -> revoke_invitation(invitation)
      {:error, :invalid_token} -> :ok
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
    case invitation |> Repo.preload(:workspace) |> Map.fetch!(:workspace) do
      nil -> {:error, :invitation_unavailable}
      workspace -> accept_available_invitation(workspace, invitation, user)
    end
  end

  @doc """
  Revokes a pending invitation.
  """
  def revoke_invitation(%WorkspaceInvitation{} = invitation) do
    {deleted_count, _} =
      WorkspaceInvitation
      |> where([i], i.id == ^invitation.id)
      |> where([i], is_nil(i.accepted_at))
      |> where([i], i.expires_at > ^TimeHelpers.now())
      |> Repo.delete_all()

    if deleted_count == 1 do
      {:ok, invitation}
    else
      changeset =
        invitation
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.add_error(:id, "is no longer pending")

      {:error, changeset}
    end
  end

  @doc """
  Gets a pending invitation by ID.
  """
  def get_pending_invitation(id) do
    WorkspaceInvitation
    |> where([i], i.id == ^id)
    |> where([i], is_nil(i.accepted_at))
    |> where([i], i.expires_at > ^TimeHelpers.now())
    |> Repo.one()
  end

  # Private helpers

  defp check_invitation_rate_limit(workspace_id, user_id) do
    RateLimiter.check_invitation(@rate_limit_context, workspace_id, user_id)
  end

  defp member_exists?(workspace_id, email) do
    Repo.exists?(
      from(m in WorkspaceMembership,
        join: u in assoc(m, :user),
        where: m.workspace_id == ^workspace_id,
        where: fragment("lower(?)", u.email) == ^email
      )
    )
  end

  defp pending_invitation_exists?(workspace_id, email) do
    Repo.exists?(
      from(i in WorkspaceInvitation,
        where: i.workspace_id == ^workspace_id,
        where: fragment("lower(?)", i.email) == ^email,
        where: is_nil(i.accepted_at),
        where: i.expires_at > ^TimeHelpers.now()
      )
    )
  end

  defp create_serialized_invitation(workspace, invited_by, email, role, opts \\ []) do
    {encoded_token, invitation} = WorkspaceInvitation.build_invitation(workspace, invited_by, email, role)

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
    Repo.transact(fn ->
      with {:ok, locked_workspace} <- lock_workspace(workspace),
           :ok <- ensure_invitation_available(locked_workspace.id, email),
           :ok <- normalize_limit_result(Billing.can_invite_member?(locked_workspace, email)),
           :ok <- delete_inactive_invitation(locked_workspace.id, email),
           {:ok, invitation} <- insert_invitation(changeset),
           {:ok, _job} <- enqueue_delivery(encoded_token, opts) do
        {:ok, invitation}
      end
    end)
  end

  defp ensure_invitation_available(workspace_id, email) do
    cond do
      member_exists?(workspace_id, email) -> {:error, :already_member}
      pending_invitation_exists?(workspace_id, email) -> {:error, :already_invited}
      true -> :ok
    end
  end

  defp delete_inactive_invitation(workspace_id, email) do
    WorkspaceInvitation
    |> where([i], i.workspace_id == ^workspace_id)
    |> where([i], fragment("lower(?)", i.email) == ^email)
    |> where([i], not is_nil(i.accepted_at) or i.expires_at <= ^TimeHelpers.now())
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

  defp enqueue_delivery(encoded_token, opts) do
    with {:ok, encrypted_token} <- encrypt_token(encoded_token) do
      %{
        context: @rate_limit_context,
        encrypted_token: encrypted_token,
        inviter_name: Keyword.get(opts, :inviter_name),
        locale: Gettext.get_locale(Storyarn.Gettext)
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()
      |> DeliverInvitationWorker.new()
      |> Oban.insert()
    end
  end

  defp encrypt_token(encoded_token) do
    encryptor =
      Application.get_env(:storyarn, :invitation_token_encryptor, EncryptedBinary)

    case encryptor.dump(encoded_token) do
      {:ok, encrypted_token} ->
        {:ok, Base.encode64(encrypted_token)}

      _error ->
        Logger.error("Invitation token encryption failed")
        {:error, :encryption_unavailable}
    end
  rescue
    error ->
      Logger.error("Invitation token encryption failed: #{Exception.message(error)}")
      {:error, :encryption_unavailable}
  end

  defp normalize_email(email), do: email |> String.trim() |> String.downcase()

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

  defp accept_available_invitation(workspace, invitation, user) do
    fn -> accept_invitation_transaction(workspace, invitation, user) end
    |> Repo.transact()
    |> restore_limit_error()
  end

  defp accept_invitation_transaction(workspace, invitation, user) do
    with {:ok, locked_workspace} <- lock_workspace(workspace),
         {:ok, current_invitation} <- lock_invitation(invitation),
         {:ok, current_user} <- lock_user(user),
         :ok <- validate_invitation_acceptance(current_invitation, current_user),
         :ok <- normalize_limit_result(Billing.can_accept_member?(locked_workspace, current_user.email)),
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

  defp validate_invitation_acceptance(invitation, user) do
    cond do
      not is_nil(invitation.accepted_at) ->
        {:error, :already_accepted}

      DateTime.compare(invitation.expires_at, TimeHelpers.now()) != :gt ->
        {:error, :expired}

      String.downcase(user.email) != String.downcase(invitation.email) ->
        {:error, :email_mismatch}

      Memberships.get_membership(invitation.workspace_id, user.id) != nil ->
        {:error, :already_member}

      true ->
        :ok
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

  defp invitation_url(token) do
    Storyarn.Platform.Urls.base_url() <> @invitation_path_prefix <> "/" <> token
  end

  defp mark_invitation_accepted(invitation) do
    invitation
    |> Ecto.Changeset.change(accepted_at: TimeHelpers.now())
    |> Repo.update(stale_error_field: :id, stale_error_message: "is no longer available")
  end
end
