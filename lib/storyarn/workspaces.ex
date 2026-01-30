defmodule Storyarn.Workspaces do
  @moduledoc """
  The Workspaces context.

  Handles workspace management including CRUD operations and memberships.
  Workspaces are containers for projects and support team collaboration.
  """

  import Ecto.Query, warn: false
  alias Storyarn.Repo

  alias Storyarn.Accounts.{Scope, User}

  alias Storyarn.Workspaces.{
    Workspace,
    WorkspaceInvitation,
    WorkspaceMembership,
    WorkspaceNotifier
  }

  ## Workspaces

  @doc """
  Lists all workspaces the user has access to.
  """
  def list_workspaces(%Scope{user: user}) do
    Workspace
    |> join(:inner, [w], m in WorkspaceMembership,
      on: m.workspace_id == w.id and m.user_id == ^user.id
    )
    |> select([w, m], %{workspace: w, role: m.role})
    |> order_by([w], asc: w.inserted_at)
    |> Repo.all()
  end

  @doc """
  Lists all workspaces for a user (simpler version for sidebar).
  """
  def list_workspaces_for_user(%User{} = user) do
    Workspace
    |> join(:inner, [w], m in WorkspaceMembership,
      on: m.workspace_id == w.id and m.user_id == ^user.id
    )
    |> order_by([w], asc: w.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets the user's default workspace.

  Priority: First owned workspace, then first workspace with membership.
  """
  def get_default_workspace(%User{} = user) do
    Workspace
    |> join(:inner, [w], m in WorkspaceMembership,
      on: m.workspace_id == w.id and m.user_id == ^user.id
    )
    |> order_by([w, m],
      desc: fragment("CASE WHEN ? = 'owner' THEN 1 ELSE 0 END", m.role),
      asc: w.inserted_at
    )
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Gets a workspace by ID with authorization check.

  Returns `{:ok, workspace, membership}` if the user has access,
  `{:error, :not_found}` if the workspace doesn't exist,
  `{:error, :unauthorized}` if the user doesn't have access.
  """
  def get_workspace(%Scope{user: user}, id) do
    with %Workspace{} = workspace <- Repo.get(Workspace, id),
         %WorkspaceMembership{} = membership <- get_membership(workspace.id, user.id) do
      {:ok, workspace, membership}
    else
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Gets a workspace by slug with authorization check.
  """
  def get_workspace_by_slug(%Scope{user: user}, slug) do
    with %Workspace{} = workspace <- Repo.get_by(Workspace, slug: slug),
         %WorkspaceMembership{} = membership <- get_membership(workspace.id, user.id) do
      {:ok, workspace, membership}
    else
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Gets a workspace by slug without authorization check.
  """
  def get_workspace_by_slug!(slug) do
    Repo.get_by!(Workspace, slug: slug)
  end

  @doc """
  Gets a workspace by ID without authorization check.
  """
  def get_workspace!(id), do: Repo.get!(Workspace, id)

  @doc """
  Creates a workspace and sets up the owner membership.

  The creating user becomes the owner of the workspace.
  """
  def create_workspace(%Scope{user: user}, attrs) do
    Repo.transact(fn ->
      with {:ok, workspace} <- insert_workspace(user, attrs),
           {:ok, _membership} <- create_owner_membership(workspace, user) do
        {:ok, workspace}
      end
    end)
  end

  @doc """
  Creates a workspace with owner membership (for internal use, e.g., registration).
  """
  def create_workspace_with_owner(%User{} = user, attrs) do
    Repo.transact(fn ->
      with {:ok, workspace} <- insert_workspace(user, attrs),
           {:ok, _membership} <- create_owner_membership(workspace, user) do
        {:ok, workspace}
      end
    end)
  end

  defp insert_workspace(user, attrs) do
    %Workspace{owner_id: user.id}
    |> Workspace.create_changeset(attrs)
    |> Repo.insert()
  end

  defp create_owner_membership(workspace, user) do
    %WorkspaceMembership{}
    |> WorkspaceMembership.changeset(%{
      workspace_id: workspace.id,
      user_id: user.id,
      role: "owner"
    })
    |> Repo.insert()
  end

  @doc """
  Returns a changeset for tracking workspace changes.
  """
  def change_workspace(%Workspace{} = workspace, attrs \\ %{}) do
    Workspace.update_changeset(workspace, attrs)
  end

  @doc """
  Updates a workspace.
  """
  def update_workspace(%Workspace{} = workspace, attrs) do
    workspace
    |> Workspace.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a workspace.
  """
  def delete_workspace(%Workspace{} = workspace) do
    Repo.delete(workspace)
  end

  ## Memberships

  @doc """
  Lists all members of a workspace.
  """
  def list_workspace_members(workspace_id) do
    WorkspaceMembership
    |> where(workspace_id: ^workspace_id)
    |> preload(:user)
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a membership by workspace and user.

  Accepts either IDs or struct tuples.
  """
  def get_membership(%Workspace{id: workspace_id}, %User{id: user_id}) do
    get_membership(workspace_id, user_id)
  end

  def get_membership(workspace_id, user_id)
      when is_integer(workspace_id) and is_integer(user_id) do
    Repo.get_by(WorkspaceMembership, workspace_id: workspace_id, user_id: user_id)
  end

  @doc """
  Creates a membership.
  """
  def create_membership(workspace_id, user_id, role) do
    %WorkspaceMembership{}
    |> WorkspaceMembership.changeset(%{
      workspace_id: workspace_id,
      user_id: user_id,
      role: role
    })
    |> Repo.insert()
  end

  @doc """
  Updates a member's role.

  Cannot change the owner's role.
  """
  def update_member_role(%WorkspaceMembership{role: "owner"}, _role) do
    {:error, :cannot_change_owner_role}
  end

  def update_member_role(%WorkspaceMembership{} = membership, role) do
    membership
    |> WorkspaceMembership.changeset(%{role: role})
    |> Repo.update()
  end

  @doc """
  Removes a member from a workspace.

  Cannot remove the owner.
  """
  def remove_member(%WorkspaceMembership{role: "owner"}) do
    {:error, :cannot_remove_owner}
  end

  def remove_member(%WorkspaceMembership{} = membership) do
    Repo.delete(membership)
  end

  ## Authorization

  @doc """
  Authorizes a user action on a workspace.

  Returns `{:ok, workspace, membership}` if authorized, `{:error, reason}` otherwise.

  ## Actions

  - `:manage_workspace` - update settings, delete workspace (owner only)
  - `:manage_members` - invite/remove members, change roles (owner, admin)
  - `:create_project` - create new projects (owner, admin, member)
  - `:view` - view workspace content (all roles)
  """
  def authorize(%Scope{user: user}, workspace_id, action) do
    with %Workspace{} = workspace <- Repo.get(Workspace, workspace_id),
         %WorkspaceMembership{role: role} = membership <- get_membership(workspace_id, user.id),
         true <- WorkspaceMembership.can?(role, action) do
      {:ok, workspace, membership}
    else
      nil -> {:error, :not_found}
      false -> {:error, :unauthorized}
    end
  end

  ## Slug Generation

  @doc """
  Generates a unique slug for a workspace name.
  """
  def generate_slug(name, suffix \\ nil) do
    base_slug =
      name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9\s-]/, "")
      |> String.replace(~r/\s+/, "-")
      |> String.replace(~r/-+/, "-")
      |> String.trim("-")

    slug = if suffix, do: "#{base_slug}-#{suffix}", else: base_slug

    if slug_available?(slug) do
      slug
    else
      generate_slug(name, generate_suffix())
    end
  end

  defp slug_available?(slug) do
    not Repo.exists?(from(w in Workspace, where: w.slug == ^slug))
  end

  defp generate_suffix do
    :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
  end

  ## Invitations

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

  # Maximum invitations per user per workspace per hour
  @invitation_rate_limit 10
  @invitation_rate_limit_ms 60_000 * 60

  @doc """
  Creates an invitation and sends the invitation email.

  Note: Email delivery is best-effort. If the email fails to send,
  the invitation still exists in the database. Consider implementing
  a "resend invitation" feature for failed deliveries.

  Returns `{:ok, invitation}` on success.
  Returns `{:error, :already_member}` if the email is already a member.
  Returns `{:error, :already_invited}` if a pending invitation exists.
  Returns `{:error, :rate_limited}` if too many invitations have been sent.
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

  defp check_invitation_rate_limit(workspace_id, user_id) do
    key = "workspace_invitation:#{workspace_id}:#{user_id}"

    case Hammer.check_rate(key, @invitation_rate_limit_ms, @invitation_rate_limit) do
      {:allow, _count} -> :ok
      {:deny, _limit} -> {:error, :rate_limited}
    end
  end

  defp member_exists?(workspace_id, email) do
    from(m in WorkspaceMembership,
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

  @doc """
  Gets an invitation by token.

  Returns `{:ok, invitation}` if valid, `{:error, :invalid_token}` otherwise.
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

  Returns `{:ok, membership}` on success.
  Returns `{:error, :email_mismatch}` if the user's email doesn't match.
  Returns `{:error, :already_member}` if the user is already a member.
  Returns `{:error, :already_accepted}` if the invitation was already accepted.
  Returns `{:error, :expired}` if the invitation has expired.
  """
  def accept_invitation(%WorkspaceInvitation{} = invitation, user) do
    cond do
      not is_nil(invitation.accepted_at) ->
        {:error, :already_accepted}

      DateTime.compare(invitation.expires_at, DateTime.utc_now()) == :lt ->
        {:error, :expired}

      String.downcase(user.email) != String.downcase(invitation.email) ->
        {:error, :email_mismatch}

      get_membership(invitation.workspace_id, user.id) != nil ->
        {:error, :already_member}

      true ->
        do_accept_invitation(invitation, user)
    end
  end

  defp do_accept_invitation(invitation, user) do
    Repo.transact(fn ->
      with {:ok, _invitation} <- mark_invitation_accepted(invitation),
           {:ok, membership} <-
             create_membership(invitation.workspace_id, user.id, invitation.role) do
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
end
