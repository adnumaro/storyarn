defmodule Storyarn.Projects do
  @moduledoc """
  The Projects context.

  Handles project management including CRUD operations, memberships,
  invitations, and authorization.
  """

  import Ecto.Query, warn: false
  alias Storyarn.Repo

  alias Storyarn.Accounts.Scope
  alias Storyarn.Projects.{Project, ProjectInvitation, ProjectMembership, ProjectNotifier}

  ## Projects

  @doc """
  Lists all projects the user has access to (owned or as a member).
  """
  def list_projects(%Scope{user: user}) do
    Project
    |> join(:inner, [p], m in ProjectMembership,
      on: m.project_id == p.id and m.user_id == ^user.id
    )
    |> select([p, m], %{project: p, role: m.role})
    |> order_by([p], desc: p.updated_at)
    |> Repo.all()
  end

  @doc """
  Gets a single project by ID with authorization check.

  Returns `{:ok, project, membership}` if the user has access,
  `{:error, :not_found}` if the project doesn't exist,
  `{:error, :unauthorized}` if the user doesn't have access.
  """
  def get_project(%Scope{user: user}, id) do
    with %Project{} = project <- Repo.get(Project, id),
         %ProjectMembership{} = membership <- get_membership(project.id, user.id) do
      {:ok, project, membership}
    else
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Gets a project without authorization check.
  """
  def get_project!(id), do: Repo.get!(Project, id)

  @doc """
  Creates a project and sets up the owner membership.

  The creating user becomes the owner of the project.
  """
  def create_project(%Scope{user: user}, attrs) do
    Repo.transact(fn ->
      with {:ok, project} <- insert_project(user, attrs),
           {:ok, _membership} <- create_owner_membership(project, user) do
        {:ok, project}
      end
    end)
  end

  defp insert_project(user, attrs) do
    %Project{owner_id: user.id}
    |> Project.create_changeset(attrs)
    |> Repo.insert()
  end

  defp create_owner_membership(project, user) do
    %ProjectMembership{}
    |> ProjectMembership.changeset(%{project_id: project.id, user_id: user.id, role: "owner"})
    |> Repo.insert()
  end

  @doc """
  Returns a changeset for tracking project changes.
  """
  def change_project(%Project{} = project, attrs \\ %{}) do
    Project.update_changeset(project, attrs)
  end

  @doc """
  Updates a project.
  """
  def update_project(%Project{} = project, attrs) do
    project
    |> Project.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a project.
  """
  def delete_project(%Project{} = project) do
    Repo.delete(project)
  end

  ## Memberships

  @doc """
  Lists all members of a project.
  """
  def list_project_members(project_id) do
    ProjectMembership
    |> where(project_id: ^project_id)
    |> preload(:user)
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a membership by project and user.
  """
  def get_membership(project_id, user_id) do
    Repo.get_by(ProjectMembership, project_id: project_id, user_id: user_id)
  end

  @doc """
  Updates a member's role.

  Cannot change the owner's role.
  """
  def update_member_role(%ProjectMembership{role: "owner"}, _role) do
    {:error, :cannot_change_owner_role}
  end

  def update_member_role(%ProjectMembership{} = membership, role) do
    membership
    |> ProjectMembership.changeset(%{role: role})
    |> Repo.update()
  end

  @doc """
  Removes a member from a project.

  Cannot remove the owner.
  """
  def remove_member(%ProjectMembership{role: "owner"}) do
    {:error, :cannot_remove_owner}
  end

  def remove_member(%ProjectMembership{} = membership) do
    Repo.delete(membership)
  end

  ## Invitations

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

  # Maximum invitations per user per project per hour
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

  defp check_invitation_rate_limit(project_id, user_id) do
    key = "invitation:#{project_id}:#{user_id}"

    case Hammer.check_rate(key, @invitation_rate_limit_ms, @invitation_rate_limit) do
      {:allow, _count} -> :ok
      {:deny, _limit} -> {:error, :rate_limited}
    end
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

  @doc """
  Gets an invitation by token.

  Returns `{:ok, invitation}` if valid, `{:error, :invalid_token}` otherwise.
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

  Returns `{:ok, membership}` on success.
  Returns `{:error, :email_mismatch}` if the user's email doesn't match.
  Returns `{:error, :already_member}` if the user is already a member.
  Returns `{:error, :already_accepted}` if the invitation was already accepted.
  Returns `{:error, :expired}` if the invitation has expired.
  """
  def accept_invitation(%ProjectInvitation{} = invitation, user) do
    cond do
      not is_nil(invitation.accepted_at) ->
        {:error, :already_accepted}

      DateTime.compare(invitation.expires_at, DateTime.utc_now()) == :lt ->
        {:error, :expired}

      String.downcase(user.email) != String.downcase(invitation.email) ->
        {:error, :email_mismatch}

      get_membership(invitation.project_id, user.id) != nil ->
        {:error, :already_member}

      true ->
        do_accept_invitation(invitation, user)
    end
  end

  defp do_accept_invitation(invitation, user) do
    Repo.transact(fn ->
      with {:ok, _invitation} <- mark_invitation_accepted(invitation),
           {:ok, membership} <- create_membership(invitation.project_id, user.id, invitation.role) do
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

  defp create_membership(project_id, user_id, role) do
    %ProjectMembership{}
    |> ProjectMembership.changeset(%{project_id: project_id, user_id: user_id, role: role})
    |> Repo.insert()
  end

  @doc """
  Revokes a pending invitation.
  """
  def revoke_invitation(%ProjectInvitation{} = invitation) do
    Repo.delete(invitation)
  end

  ## Authorization

  @doc """
  Authorizes a user action on a project.

  Returns `{:ok, project, membership}` if authorized, `{:error, reason}` otherwise.

  ## Actions

  - `:manage_project` - update settings, delete project (owner only)
  - `:manage_members` - invite/remove members, change roles (owner only)
  - `:edit_content` - edit flows, entities (owner, editor)
  - `:view` - view project content (all roles)
  """
  def authorize(%Scope{user: user}, project_id, action) do
    with %Project{} = project <- Repo.get(Project, project_id),
         %ProjectMembership{role: role} = membership <- get_membership(project_id, user.id),
         true <- ProjectMembership.can?(role, action) do
      {:ok, project, membership}
    else
      nil -> {:error, :not_found}
      false -> {:error, :unauthorized}
    end
  end
end
