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

  alias Storyarn.Accounts.User
  alias Storyarn.Billing
  alias Storyarn.Projects.Project
  alias Storyarn.RateLimiter
  alias Storyarn.Repo
  alias Storyarn.Shared.EncryptedBinary
  alias Storyarn.Shared.InvitationNotifier
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Workers.DeliverInvitationWorker
  alias Storyarn.Workspaces.Workspace

  @doc """
  Lists pending invitations for a parent entity.
  """
  def list_pending_invitations(config, parent_id) do
    config.invitation_schema
    |> where([i], field(i, ^config.parent_key) == ^parent_id)
    |> where([i], is_nil(i.accepted_at))
    |> where([i], i.expires_at > ^TimeHelpers.now())
    |> available_parent_query(config)
    |> preload(:invited_by)
    |> order_by([i], desc: i.updated_at)
    |> Repo.all()
  end

  @doc """
  Creates an invitation and queues the invitation email for durable delivery.
  """
  def create_invitation(config, parent, invited_by, email, role) do
    parent_id = Map.fetch!(parent, :id)

    with :ok <- check_invitation_rate_limit(config, parent_id, invited_by.id) do
      create_serialized_invitation(config, parent, invited_by, normalize_email(email), role)
    end
  end

  @doc """
  Creates an admin-initiated invitation (no rate limit, no invited_by user).

  Used by `Storyarn.Release.invite_member/5` for CLI-approved invitations.
  """
  def create_admin_invitation(config, parent, email, role, opts \\ []) do
    create_serialized_invitation(config, parent, nil, normalize_email(email), role, opts)
  end

  @doc false
  def deliver_invitation_email(config, encoded_token, opts \\ []) do
    case get_invitation_by_token(config, encoded_token) do
      {:ok, invitation} ->
        url = invitation_url(config.invitation_path_prefix, encoded_token)
        InvitationNotifier.deliver_invitation(config, invitation, url, opts)

      {:error, :invalid_token} ->
        {:cancel, :invitation_unavailable}
    end
  end

  @doc false
  def cancel_invitation_delivery(config, encoded_token) do
    case get_invitation_by_token(config, encoded_token) do
      {:ok, invitation} -> revoke_invitation(invitation)
      {:error, :invalid_token} -> :ok
    end
  end

  @doc """
  Gets an invitation by token.
  """
  def get_invitation_by_token(config, token) do
    case config.invitation_schema.verify_token_query(token) do
      {:ok, query} ->
        case query |> available_parent_query(config) |> Repo.one() do
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
    do_accept_invitation(config, invitation, user)
  end

  @doc """
  Revokes a pending invitation.
  """
  def revoke_invitation(invitation) do
    schema = invitation.__struct__

    {deleted_count, _} =
      schema
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
  def get_pending_invitation(config, id) do
    config.invitation_schema
    |> where([i], i.id == ^id)
    |> where([i], is_nil(i.accepted_at))
    |> where([i], i.expires_at > ^TimeHelpers.now())
    |> available_parent_query(config)
    |> Repo.one()
  end

  # Private helpers

  defp check_invitation_rate_limit(config, parent_id, user_id) do
    RateLimiter.check_invitation(config.rate_limit_context, parent_id, user_id)
  end

  defp member_exists?(config, parent_id, email) do
    Repo.exists?(
      from(m in config.membership_schema,
        join: u in assoc(m, :user),
        where: field(m, ^config.parent_key) == ^parent_id,
        where: fragment("lower(?)", u.email) == ^email
      )
    )
  end

  defp pending_invitation_exists?(config, parent_id, email) do
    Repo.exists?(
      from(i in config.invitation_schema,
        where: field(i, ^config.parent_key) == ^parent_id,
        where: fragment("lower(?)", i.email) == ^email,
        where: is_nil(i.accepted_at),
        where: i.expires_at > ^TimeHelpers.now()
      )
    )
  end

  defp create_serialized_invitation(config, parent, invited_by, email, role, opts \\ []) do
    {encoded_token, invitation} =
      config.invitation_schema.build_invitation(parent, invited_by, email, role)

    changeset =
      config
      |> invitation_changeset(invitation)
      |> Ecto.Changeset.unique_constraint(:email,
        name: invitation_unique_index(config.parent_key)
      )

    if changeset.valid? do
      config
      |> transact_invitation(parent, email, changeset, encoded_token, opts)
      |> restore_limit_error()
    else
      {:error, changeset}
    end
  end

  defp transact_invitation(config, parent, email, changeset, encoded_token, opts) do
    Repo.transact(fn ->
      with {:ok, locked_workspace} <- lock_workspace(parent),
           {:ok, locked_parent} <- lock_available_parent(config, parent, locked_workspace),
           parent_id = Map.fetch!(locked_parent, :id),
           :ok <- ensure_invitation_available(config, parent_id, email),
           :ok <- normalize_limit_result(Billing.can_invite_member?(locked_parent, email)),
           :ok <- delete_inactive_invitation(config, parent_id, email),
           {:ok, invitation} <- insert_invitation(config, changeset),
           {:ok, _job} <- enqueue_delivery(config, encoded_token, opts) do
        {:ok, invitation}
      end
    end)
  end

  defp ensure_invitation_available(config, parent_id, email) do
    cond do
      member_exists?(config, parent_id, email) -> {:error, :already_member}
      pending_invitation_exists?(config, parent_id, email) -> {:error, :already_invited}
      true -> :ok
    end
  end

  defp delete_inactive_invitation(config, parent_id, email) do
    config.invitation_schema
    |> where([i], field(i, ^config.parent_key) == ^parent_id)
    |> where([i], fragment("lower(?)", i.email) == ^email)
    |> where([i], not is_nil(i.accepted_at) or i.expires_at <= ^TimeHelpers.now())
    |> Repo.delete_all()

    :ok
  end

  defp insert_invitation(config, changeset) do
    case Repo.insert(changeset) do
      {:ok, invitation} ->
        invitation = Repo.preload(invitation, config.preload_after_insert)
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

  defp enqueue_delivery(config, encoded_token, opts) do
    encrypted_token = encrypt_token!(encoded_token)

    %{
      context: config.rate_limit_context,
      encrypted_token: encrypted_token,
      inviter_name: Keyword.get(opts, :inviter_name),
      locale: Gettext.get_locale(Storyarn.Gettext)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
    |> DeliverInvitationWorker.new()
    |> Oban.insert()
  end

  defp encrypt_token!(encoded_token) do
    {:ok, encrypted_token} = EncryptedBinary.dump(encoded_token)
    Base.encode64(encrypted_token)
  end

  defp normalize_email(email), do: email |> String.trim() |> String.downcase()

  defp invitation_changeset(config, invitation) do
    schema = config.invitation_schema

    attrs = %{
      config.parent_key => Map.fetch!(invitation, config.parent_key),
      email: invitation.email,
      role: invitation.role,
      invited_by_id: invitation.invited_by_id
    }

    schema
    |> struct()
    |> schema.changeset(attrs)
    |> Ecto.Changeset.put_change(:token, invitation.token)
    |> Ecto.Changeset.put_change(:expires_at, invitation.expires_at)
  end

  defp lock_workspace(%Workspace{id: workspace_id}) do
    lock_workspace_by_id(workspace_id)
  end

  defp lock_workspace(%Project{workspace_id: workspace_id}) do
    lock_workspace_by_id(workspace_id)
  end

  defp lock_workspace_by_id(workspace_id) do
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

  defp invitation_unique_index(:project_id), do: "project_invitations_project_id_email_index"

  defp invitation_unique_index(:workspace_id), do: "workspace_invitations_workspace_id_email_index"

  defp do_accept_invitation(config, invitation, user) do
    parent =
      invitation
      |> Repo.preload(config.parent_assoc)
      |> Map.fetch!(config.parent_assoc)

    case parent do
      nil -> {:error, :invitation_unavailable}
      parent -> accept_available_invitation(config, parent, invitation, user)
    end
  end

  defp accept_available_invitation(config, parent, invitation, user) do
    fn -> accept_invitation_transaction(config, parent, invitation, user) end
    |> Repo.transact()
    |> restore_limit_error()
  end

  defp accept_invitation_transaction(config, parent, invitation, user) do
    with {:ok, locked_workspace} <- lock_workspace(parent),
         {:ok, locked_parent} <- lock_available_parent(config, parent, locked_workspace),
         {:ok, current_invitation} <- lock_invitation(config, invitation),
         {:ok, current_user} <- lock_user(user),
         :ok <- validate_invitation_acceptance(config, current_invitation, current_user),
         :ok <- normalize_limit_result(Billing.can_accept_member?(locked_parent, current_user.email)),
         {:ok, _invitation} <- mark_invitation_accepted(current_invitation),
         {:ok, membership} <-
           config.memberships_module.create_membership(
             Map.fetch!(current_invitation, config.parent_key),
             current_user.id,
             current_invitation.role
           ) do
      {:ok, membership}
    else
      {:error, reason} when reason in [:not_found, :user_unavailable] ->
        {:error, :invitation_unavailable}

      {:error, %Ecto.Changeset{} = changeset} ->
        handle_membership_error(config, changeset)

      error ->
        error
    end
  end

  defp lock_available_parent(%{parent_key: :workspace_id}, %Workspace{}, locked_workspace) do
    {:ok, locked_workspace}
  end

  defp lock_available_parent(%{parent_key: :project_id}, %Project{id: project_id, workspace_id: workspace_id}, %Workspace{
         id: workspace_id
       }) do
    case Repo.one(
           from(project in Project,
             where: project.id == ^project_id and is_nil(project.deleted_at),
             lock: "FOR UPDATE"
           )
         ) do
      nil -> {:error, :not_found}
      project -> {:ok, project}
    end
  end

  defp lock_invitation(config, invitation) do
    case Repo.one(
           from(current_invitation in config.invitation_schema,
             where: current_invitation.id == ^invitation.id,
             lock: "FOR UPDATE"
           )
         ) do
      nil -> {:error, stale_invitation_changeset(invitation)}
      current_invitation -> {:ok, current_invitation}
    end
  end

  defp lock_user(%User{id: user_id}) do
    case Repo.one(from(user in User, where: user.id == ^user_id, lock: "FOR UPDATE")) do
      nil -> {:error, :user_unavailable}
      user -> {:ok, user}
    end
  end

  defp validate_invitation_acceptance(config, invitation, user) do
    parent_id = Map.fetch!(invitation, config.parent_key)

    cond do
      not is_nil(invitation.accepted_at) ->
        {:error, :already_accepted}

      DateTime.compare(invitation.expires_at, TimeHelpers.now()) != :gt ->
        {:error, :expired}

      String.downcase(user.email) != String.downcase(invitation.email) ->
        {:error, :email_mismatch}

      config.memberships_module.get_membership(parent_id, user.id) != nil ->
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

  defp available_parent_query(query, %{parent_key: :workspace_id}), do: query

  defp available_parent_query(query, %{parent_key: :project_id}) do
    from(invitation in query,
      join: project in Project,
      on: project.id == invitation.project_id,
      where: is_nil(project.deleted_at)
    )
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
    |> Repo.update(stale_error_field: :id, stale_error_message: "is no longer available")
  end
end
