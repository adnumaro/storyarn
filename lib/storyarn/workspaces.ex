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

  alias Storyarn.Workspaces.{Invitations, Memberships, SlugGenerator, WorkspaceCrud}

  # =============================================================================
  # Workspace CRUD
  # =============================================================================

  @doc """
  Lists all workspaces the user has access to.
  """
  defdelegate list_workspaces(scope), to: WorkspaceCrud

  @doc """
  Lists all workspaces for a user (simpler version for sidebar).
  """
  defdelegate list_workspaces_for_user(user), to: WorkspaceCrud

  @doc """
  Gets the user's default workspace.

  Priority: First owned workspace, then first workspace with membership.
  """
  defdelegate get_default_workspace(user), to: WorkspaceCrud

  @doc """
  Gets a workspace by ID with authorization check.

  Returns `{:ok, workspace, membership}` if the user has access,
  `{:error, :not_found}` if the workspace doesn't exist,
  `{:error, :unauthorized}` if the user doesn't have access.
  """
  defdelegate get_workspace(scope, id), to: WorkspaceCrud

  @doc """
  Gets a workspace by slug with authorization check.
  """
  defdelegate get_workspace_by_slug(scope, slug), to: WorkspaceCrud

  @doc """
  Gets a workspace by slug without authorization check.
  """
  defdelegate get_workspace_by_slug!(slug), to: WorkspaceCrud

  @doc """
  Gets a workspace by ID without authorization check.
  """
  defdelegate get_workspace!(id), to: WorkspaceCrud

  @doc """
  Creates a workspace and sets up the owner membership.

  The creating user becomes the owner of the workspace.
  """
  defdelegate create_workspace(scope, attrs), to: WorkspaceCrud

  @doc """
  Creates a workspace with owner membership (for internal use, e.g., registration).
  """
  defdelegate create_workspace_with_owner(user, attrs), to: WorkspaceCrud

  @doc """
  Returns a changeset for tracking workspace changes.
  """
  defdelegate change_workspace(workspace, attrs \\ %{}), to: WorkspaceCrud

  @doc """
  Updates a workspace.
  """
  defdelegate update_workspace(workspace, attrs), to: WorkspaceCrud

  @doc """
  Deletes a workspace.
  """
  defdelegate delete_workspace(workspace), to: WorkspaceCrud

  # =============================================================================
  # Memberships
  # =============================================================================

  @doc """
  Lists all members of a workspace.
  """
  defdelegate list_workspace_members(workspace_id), to: Memberships

  @doc """
  Gets a membership by workspace and user.

  Accepts either IDs or struct tuples.
  """
  defdelegate get_membership(workspace_or_id, user_or_id), to: Memberships

  @doc """
  Creates a membership.
  """
  defdelegate create_membership(workspace_id, user_id, role), to: Memberships

  @doc """
  Updates a member's role.

  Cannot change the owner's role.
  """
  defdelegate update_member_role(membership, role), to: Memberships

  @doc """
  Removes a member from a workspace.

  Cannot remove the owner.
  """
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
  defdelegate authorize(scope, workspace_id, action), to: Memberships

  # =============================================================================
  # Slug Generation
  # =============================================================================

  @doc """
  Generates a unique slug for a workspace name.
  """
  defdelegate generate_slug(name, suffix \\ nil), to: SlugGenerator

  # =============================================================================
  # Invitations
  # =============================================================================

  @doc """
  Lists pending invitations for a workspace.
  """
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
  defdelegate create_invitation(workspace, invited_by, email, role \\ "member"), to: Invitations

  @doc """
  Gets an invitation by token.

  Returns `{:ok, invitation}` if valid, `{:error, :invalid_token}` otherwise.
  """
  defdelegate get_invitation_by_token(token), to: Invitations

  @doc """
  Accepts an invitation and creates a membership for the user.

  Returns `{:ok, membership}` on success.
  Returns `{:error, :email_mismatch}` if the user's email doesn't match.
  Returns `{:error, :already_member}` if the user is already a member.
  Returns `{:error, :already_accepted}` if the invitation was already accepted.
  Returns `{:error, :expired}` if the invitation has expired.
  """
  defdelegate accept_invitation(invitation, user), to: Invitations

  @doc """
  Revokes a pending invitation.
  """
  defdelegate revoke_invitation(invitation), to: Invitations

  @doc """
  Gets a pending invitation by ID.
  """
  defdelegate get_pending_invitation(id), to: Invitations
end
