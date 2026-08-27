defmodule Storyarn.Projects.Access do
  @moduledoc false

  alias Storyarn.Projects.Access.RateLimits
  alias Storyarn.Projects.Invitations
  alias Storyarn.Projects.Memberships
  alias Storyarn.Projects.ProjectMembership
  alias Storyarn.Projects.Validations
  alias Storyarn.Projects.WorkspaceAccess

  defdelegate can?(role, action), to: ProjectMembership
  defdelegate effective_role(project_role, workspace_role), to: Memberships
  defdelegate list_project_members(project_id), to: Memberships
  defdelegate get_membership(project_id, user_id), to: Memberships
  defdelegate get_effective_membership(project_id, user_id, workspace_id), to: Memberships
  defdelegate create_membership(project_id, user_id, role), to: Memberships
  defdelegate update_member_role(membership, role), to: Memberships
  defdelegate remove_member(membership), to: Memberships
  defdelegate authorize(scope, project_id, action), to: Memberships
  defdelegate authorize_locked(scope, project_id, action), to: Memberships

  defdelegate workspace_can?(role, action), to: WorkspaceAccess, as: :can?
  defdelegate authorize_workspace(scope, workspace_id, action), to: WorkspaceAccess, as: :authorize
  defdelegate get_workspace(scope, workspace_id), to: WorkspaceAccess

  defdelegate get_workspace_membership(workspace_id, user_id),
    to: WorkspaceAccess,
    as: :get_membership

  defdelegate list_pending_invitations(project_id), to: Invitations
  defdelegate create_invitation(project, invited_by, email, role \\ "editor"), to: Invitations
  defdelegate create_admin_invitation(project, email, role, opts \\ []), to: Invitations
  defdelegate deliver_invitation_email(token, opts \\ []), to: Invitations
  defdelegate cancel_invitation_delivery(token), to: Invitations
  defdelegate get_invitation_by_token(token), to: Invitations
  defdelegate accept_invitation(invitation, user), to: Invitations
  defdelegate revoke_invitation(invitation), to: Invitations
  defdelegate get_pending_invitation(id), to: Invitations

  defdelegate check_invitation_rate(project_id, user_id),
    to: RateLimits,
    as: :check

  defdelegate validate_project_email_format(changeset),
    to: Validations,
    as: :validate_email_format
end
