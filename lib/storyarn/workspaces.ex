defmodule Storyarn.Workspaces do
  @moduledoc """
  The Workspaces context.

  Handles workspace management including CRUD operations, memberships,
  and invitations. Workspaces are containers for projects and support
  team collaboration.

  This module serves as a facade, delegating to specialized submodules:
  - `WorkspaceCrud` - Workspace CRUD operations
  - `Memberships` - Member management and authorization
  - `Invitations` - Invitation management
  - `SlugGenerator` - Unique slug generation
  """

  alias Storyarn.Accounts.{Scope, User}

  alias Storyarn.Workspaces.{
    Invitations,
    Memberships,
    SlugGenerator,
    Workspace,
    WorkspaceCrud,
    WorkspaceInvitation,
    WorkspaceMembership
  }

  # =============================================================================
  # Type Definitions
  # =============================================================================

  @type workspace :: Workspace.t()
  @type membership :: WorkspaceMembership.t()
  @type invitation :: WorkspaceInvitation.t()
  @type scope :: Scope.t()
  @type user :: User.t()
  @type changeset :: Ecto.Changeset.t()
  @type attrs :: map()
  @type role :: String.t()
  @type action :: :manage_workspace | :manage_members | :create_project | :view

  # =============================================================================
  # Workspace CRUD
  # =============================================================================

  @doc """
  Lists all workspaces the user has access to.
  """
  @spec list_workspaces(scope()) :: [workspace()]
  defdelegate list_workspaces(scope), to: WorkspaceCrud

  @doc """
  Lists all workspaces for a user (simpler version for sidebar).
  """
  @spec list_workspaces_for_user(user()) :: [workspace()]
  defdelegate list_workspaces_for_user(user), to: WorkspaceCrud

  @doc """
  Gets the user's default workspace.

  Priority: First owned workspace, then first workspace with membership.
  """
  @spec get_default_workspace(user()) :: workspace() | nil
  defdelegate get_default_workspace(user), to: WorkspaceCrud

  @doc """
  Gets a workspace by ID with authorization check.

  Returns `{:ok, workspace, membership}` if the user has access,
  `{:error, :not_found}` if the workspace doesn't exist,
  `{:error, :unauthorized}` if the user doesn't have access.
  """
  @spec get_workspace(scope(), integer()) ::
          {:ok, workspace(), membership()} | {:error, :not_found | :unauthorized}
  defdelegate get_workspace(scope, id), to: WorkspaceCrud

  @doc """
  Gets a workspace by slug with authorization check.
  """
  @spec get_workspace_by_slug(scope(), String.t()) ::
          {:ok, workspace(), membership()} | {:error, :not_found | :unauthorized}
  defdelegate get_workspace_by_slug(scope, slug), to: WorkspaceCrud

  @doc """
  Gets a workspace by slug without authorization check.
  """
  @spec get_workspace_by_slug!(String.t()) :: workspace()
  defdelegate get_workspace_by_slug!(slug), to: WorkspaceCrud

  @doc """
  Gets a workspace by ID without authorization check.
  """
  @spec get_workspace!(integer()) :: workspace()
  defdelegate get_workspace!(id), to: WorkspaceCrud

  @doc """
  Creates a workspace and sets up the owner membership.

  The creating user becomes the owner of the workspace.
  """
  @spec create_workspace(scope(), attrs()) :: {:ok, workspace()} | {:error, changeset()}
  defdelegate create_workspace(scope, attrs), to: WorkspaceCrud

  @doc """
  Creates a workspace with owner membership (for internal use, e.g., registration).
  """
  @spec create_workspace_with_owner(user(), attrs()) :: {:ok, workspace()} | {:error, changeset()}
  defdelegate create_workspace_with_owner(user, attrs), to: WorkspaceCrud

  @doc """
  Returns a changeset for tracking workspace changes.
  """
  @spec change_workspace(workspace(), attrs()) :: changeset()
  defdelegate change_workspace(workspace, attrs \\ %{}), to: WorkspaceCrud

  @doc """
  Updates a workspace.
  """
  @spec update_workspace(workspace(), attrs()) :: {:ok, workspace()} | {:error, changeset()}
  defdelegate update_workspace(workspace, attrs), to: WorkspaceCrud

  @doc """
  Deletes a workspace.
  """
  @spec delete_workspace(workspace()) :: {:ok, workspace()} | {:error, changeset()}
  defdelegate delete_workspace(workspace), to: WorkspaceCrud

  # =============================================================================
  # Memberships
  # =============================================================================

  @doc """
  Lists all members of a workspace.
  """
  @spec list_workspace_members(integer()) :: [membership()]
  defdelegate list_workspace_members(workspace_id), to: Memberships

  @doc """
  Gets a membership by workspace and user.

  Accepts either IDs or struct tuples.
  """
  @spec get_membership(workspace() | integer(), user() | integer()) :: membership() | nil
  defdelegate get_membership(workspace_or_id, user_or_id), to: Memberships

  @doc """
  Creates a membership.
  """
  @spec create_membership(integer(), integer(), role()) ::
          {:ok, membership()} | {:error, changeset()}
  defdelegate create_membership(workspace_id, user_id, role), to: Memberships

  @doc """
  Updates a member's role.

  Cannot change the owner's role.
  """
  @spec update_member_role(membership(), role()) ::
          {:ok, membership()} | {:error, changeset() | :cannot_change_owner_role}
  defdelegate update_member_role(membership, role), to: Memberships

  @doc """
  Removes a member from a workspace.

  Cannot remove the owner.
  """
  @spec remove_member(membership()) ::
          {:ok, membership()} | {:error, changeset() | :cannot_remove_owner}
  defdelegate remove_member(membership), to: Memberships

  @doc """
  Authorizes a user action on a workspace.

  Returns `{:ok, workspace, membership}` if authorized, `{:error, reason}` otherwise.

  ## Actions

  - `:manage_workspace` - update settings, delete workspace (owner only)
  - `:manage_members` - invite/remove members, change roles (owner, admin)
  - `:create_project` - create new projects (owner, admin, member)
  - `:view` - view workspace content (all roles)
  """
  @spec authorize(scope(), integer(), action()) ::
          {:ok, workspace(), membership()} | {:error, :not_found | :unauthorized}
  defdelegate authorize(scope, workspace_id, action), to: Memberships

  # =============================================================================
  # Slug Generation
  # =============================================================================

  @doc """
  Generates a unique slug for a workspace name.
  """
  @spec generate_slug(String.t(), String.t() | nil) :: String.t()
  defdelegate generate_slug(name, suffix \\ nil), to: SlugGenerator

  # =============================================================================
  # Invitations
  # =============================================================================

  @doc """
  Lists pending invitations for a workspace.
  """
  @spec list_pending_invitations(integer()) :: [invitation()]
  defdelegate list_pending_invitations(workspace_id), to: Invitations

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
  @spec create_invitation(workspace(), user(), String.t(), role()) ::
          {:ok, invitation()}
          | {:error, :already_member | :already_invited | :rate_limited | changeset()}
  defdelegate create_invitation(workspace, invited_by, email, role \\ "member"), to: Invitations

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
          | {:error,
             :email_mismatch | :already_member | :already_accepted | :expired | changeset()}
  defdelegate accept_invitation(invitation, user), to: Invitations

  @doc """
  Revokes a pending invitation.
  """
  @spec revoke_invitation(invitation()) :: {:ok, invitation()} | {:error, changeset()}
  defdelegate revoke_invitation(invitation), to: Invitations

  @doc """
  Gets a pending invitation by ID.
  """
  @spec get_pending_invitation(integer()) :: invitation() | nil
  defdelegate get_pending_invitation(id), to: Invitations
end
