defmodule Storyarn.Projects.Invitations do
  @moduledoc false

  alias Storyarn.Emails.Templates
  alias Storyarn.Projects.{Memberships, Project, ProjectInvitation, ProjectMembership}
  alias Storyarn.Shared.InvitationOperations

  @config %{
    invitation_schema: ProjectInvitation,
    membership_schema: ProjectMembership,
    parent_key: :project_id,
    parent_assoc: :project,
    rate_limit_context: "project",
    template_fn: &Templates.project_invitation/6,
    invitation_path_prefix: "/projects/invitations",
    memberships_module: Memberships,
    preload_after_insert: [:project, :invited_by]
  }

  def list_pending_invitations(project_id),
    do: InvitationOperations.list_pending_invitations(@config, project_id)

  def create_invitation(%Project{} = project, invited_by, email, role \\ "editor"),
    do: InvitationOperations.create_invitation(@config, project, invited_by, email, role)

  def create_admin_invitation(%Project{} = project, email, role, opts \\ []),
    do: InvitationOperations.create_admin_invitation(@config, project, email, role, opts)

  def get_invitation_by_token(token),
    do: InvitationOperations.get_invitation_by_token(@config, token)

  def accept_invitation(%ProjectInvitation{} = invitation, user),
    do: InvitationOperations.accept_invitation(@config, invitation, user)

  def revoke_invitation(%ProjectInvitation{} = invitation),
    do: InvitationOperations.revoke_invitation(invitation)
end
