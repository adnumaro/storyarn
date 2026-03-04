defmodule Storyarn.Projects.Invitations do
  @moduledoc false

  alias Storyarn.Projects.{
    Memberships,
    Project,
    ProjectInvitation,
    ProjectMembership,
    ProjectNotifier
  }

  alias Storyarn.Shared.InvitationOperations

  @config %{
    invitation_schema: ProjectInvitation,
    membership_schema: ProjectMembership,
    parent_key: :project_id,
    rate_limit_context: "project",
    notifier_module: ProjectNotifier,
    memberships_module: Memberships,
    preload_after_insert: [:project, :invited_by]
  }

  def list_pending_invitations(project_id),
    do: InvitationOperations.list_pending_invitations(@config, project_id)

  def create_invitation(%Project{} = project, invited_by, email, role \\ "editor"),
    do: InvitationOperations.create_invitation(@config, project, invited_by, email, role)

  def get_invitation_by_token(token),
    do: InvitationOperations.get_invitation_by_token(@config, token)

  def accept_invitation(%ProjectInvitation{} = invitation, user),
    do: InvitationOperations.accept_invitation(@config, invitation, user)

  def revoke_invitation(%ProjectInvitation{} = invitation),
    do: InvitationOperations.revoke_invitation(invitation)
end
