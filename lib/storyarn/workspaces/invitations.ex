defmodule Storyarn.Workspaces.Invitations do
  @moduledoc false

  alias Storyarn.Shared.InvitationOperations

  alias Storyarn.Workspaces.{
    Memberships,
    Workspace,
    WorkspaceInvitation,
    WorkspaceMembership,
    WorkspaceNotifier
  }

  @config %{
    invitation_schema: WorkspaceInvitation,
    membership_schema: WorkspaceMembership,
    parent_key: :workspace_id,
    rate_limit_context: "workspace",
    notifier_module: WorkspaceNotifier,
    memberships_module: Memberships,
    preload_after_insert: [:workspace, :invited_by]
  }

  def list_pending_invitations(workspace_id),
    do: InvitationOperations.list_pending_invitations(@config, workspace_id)

  def create_invitation(%Workspace{} = workspace, invited_by, email, role \\ "member"),
    do: InvitationOperations.create_invitation(@config, workspace, invited_by, email, role)

  def create_admin_invitation(%Workspace{} = workspace, email, role, opts \\ []),
    do: InvitationOperations.create_admin_invitation(@config, workspace, email, role, opts)

  def get_invitation_by_token(token),
    do: InvitationOperations.get_invitation_by_token(@config, token)

  def accept_invitation(%WorkspaceInvitation{} = invitation, user),
    do: InvitationOperations.accept_invitation(@config, invitation, user)

  def revoke_invitation(%WorkspaceInvitation{} = invitation),
    do: InvitationOperations.revoke_invitation(invitation)

  def get_pending_invitation(id),
    do: InvitationOperations.get_pending_invitation(@config, id)
end
