defmodule Storyarn.Projects do
  @moduledoc """
  The Projects context.

  Handles project management including CRUD operations, memberships,
  invitations, and authorization.

  This module serves as a facade, delegating to specialized submodules:
  - `ProjectCrud` - Project CRUD operations
  - `Memberships` - Member management and authorization
  - `Invitations` - Invitation management
  """

  alias Storyarn.Accounts.{Scope, User}

  alias Storyarn.Projects.{
    Invitations,
    Memberships,
    Project,
    ProjectCrud,
    ProjectInvitation,
    ProjectMembership
  }

  # =============================================================================
  # Type Definitions
  # =============================================================================

  @type project :: Project.t()
  @type membership :: ProjectMembership.t()
  @type invitation :: ProjectInvitation.t()
  @type scope :: Scope.t()
  @type user :: User.t()
  @type changeset :: Ecto.Changeset.t()
  @type attrs :: map()
  @type role :: String.t()
  @type action :: :manage_project | :manage_members | :edit_content | :view

  # =============================================================================
  # Project CRUD
  # =============================================================================

  @doc """
  Lists all projects the user has access to (owned or as a member).
  """
  @spec list_projects(scope()) :: [project()]
  defdelegate list_projects(scope), to: ProjectCrud

  @doc """
  Lists all projects in a workspace that the user has access to.

  Access is determined by:
  1. Direct project membership, OR
  2. Workspace membership (inherited access)
  """
  @spec list_projects_for_workspace(integer(), scope()) :: [project()]
  defdelegate list_projects_for_workspace(workspace_id, scope), to: ProjectCrud

  @doc """
  Gets a single project by ID with authorization check.

  Returns `{:ok, project, membership}` if the user has access,
  `{:error, :not_found}` if the project doesn't exist,
  `{:error, :unauthorized}` if the user doesn't have access.
  """
  @spec get_project(scope(), integer()) ::
          {:ok, project(), membership()} | {:error, :not_found | :unauthorized}
  defdelegate get_project(scope, id), to: ProjectCrud

  @doc """
  Gets a project without authorization check.
  """
  @spec get_project!(integer()) :: project()
  defdelegate get_project!(id), to: ProjectCrud

  @doc """
  Gets a project by workspace slug and project slug with authorization check.

  Returns `{:ok, project, membership}` if the user has access,
  `{:error, :not_found}` if the project doesn't exist or user doesn't have access.
  """
  @spec get_project_by_slugs(scope(), String.t(), String.t()) ::
          {:ok, project(), membership()} | {:error, :not_found}
  defdelegate get_project_by_slugs(scope, workspace_slug, project_slug), to: ProjectCrud

  @doc """
  Creates a project and sets up the owner membership.

  The creating user becomes the owner of the project.
  """
  @spec create_project(scope(), attrs()) :: {:ok, project()} | {:error, changeset()}
  defdelegate create_project(scope, attrs), to: ProjectCrud

  @doc """
  Returns a changeset for tracking project changes.
  """
  @spec change_project(project(), attrs()) :: changeset()
  defdelegate change_project(project, attrs \\ %{}), to: ProjectCrud

  @doc """
  Updates a project.
  """
  @spec update_project(project(), attrs()) :: {:ok, project()} | {:error, changeset()}
  defdelegate update_project(project, attrs), to: ProjectCrud

  @doc """
  Deletes a project.
  """
  @spec delete_project(project()) :: {:ok, project()} | {:error, changeset()}
  defdelegate delete_project(project), to: ProjectCrud

  # =============================================================================
  # Memberships
  # =============================================================================

  @doc """
  Lists all members of a project.
  """
  @spec list_project_members(integer()) :: [membership()]
  defdelegate list_project_members(project_id), to: Memberships

  @doc """
  Gets a membership by project and user.
  """
  @spec get_membership(integer(), integer()) :: membership() | nil
  defdelegate get_membership(project_id, user_id), to: Memberships

  @doc """
  Creates a membership.
  """
  @spec create_membership(integer(), integer(), role()) ::
          {:ok, membership()} | {:error, changeset()}
  defdelegate create_membership(project_id, user_id, role), to: Memberships

  @doc """
  Updates a member's role.

  Cannot change the owner's role.
  """
  @spec update_member_role(membership(), role()) ::
          {:ok, membership()} | {:error, changeset() | :cannot_change_owner}
  defdelegate update_member_role(membership, role), to: Memberships

  @doc """
  Removes a member from a project.

  Cannot remove the owner.
  """
  @spec remove_member(membership()) ::
          {:ok, membership()} | {:error, changeset() | :cannot_remove_owner}
  defdelegate remove_member(membership), to: Memberships

  @doc """
  Authorizes a user action on a project.

  Returns `{:ok, project, membership}` if authorized, `{:error, reason}` otherwise.

  ## Actions

  - `:manage_project` - update settings, delete project (owner only)
  - `:manage_members` - invite/remove members, change roles (owner only)
  - `:edit_content` - edit flows, entities (owner, editor)
  - `:view` - view project content (all roles)
  """
  @spec authorize(scope(), integer(), action()) ::
          {:ok, project(), membership()} | {:error, :not_found | :unauthorized}
  defdelegate authorize(scope, project_id, action), to: Memberships

  # =============================================================================
  # Invitations
  # =============================================================================

  @doc """
  Lists pending invitations for a project.
  """
  @spec list_pending_invitations(integer()) :: [invitation()]
  defdelegate list_pending_invitations(project_id), to: Invitations

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
  @spec create_invitation(project(), user(), String.t(), role()) ::
          {:ok, invitation()} | {:error, :already_member | :already_invited | :rate_limited}
  defdelegate create_invitation(project, invited_by, email, role \\ "editor"), to: Invitations

  @doc """
  Gets an invitation by token.

  Returns `{:ok, invitation}` if valid, `{:error, :invalid_token}` otherwise.
  """
  @spec get_invitation_by_token(String.t()) :: {:ok, invitation()} | {:error, :invalid_token}
  defdelegate get_invitation_by_token(token), to: Invitations

  @doc """
  Accepts an invitation and creates a membership for the user.

  Returns `{:ok, membership}` on success.
  Returns `{:error, :email_mismatch}` if the user's email doesn't match.
  Returns `{:error, :already_member}` if the user is already a member.
  Returns `{:error, :already_accepted}` if the invitation was already accepted.
  Returns `{:error, :expired}` if the invitation has expired.
  """
  @spec accept_invitation(invitation(), user()) ::
          {:ok, membership()}
          | {:error, :email_mismatch | :already_member | :already_accepted | :expired}
  defdelegate accept_invitation(invitation, user), to: Invitations

  @doc """
  Revokes a pending invitation.
  """
  @spec revoke_invitation(invitation()) :: {:ok, invitation()} | {:error, changeset()}
  defdelegate revoke_invitation(invitation), to: Invitations
end
