defmodule Storyarn.Projects.Invitations do
  @moduledoc false

  alias Storyarn.Projects.Memberships
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.ProjectInvitation
  alias Storyarn.Projects.ProjectMembership
  alias Storyarn.Shared.InvitationOperations

  @config %{
    invitation_schema: ProjectInvitation,
    membership_schema: ProjectMembership,
    parent_key: :project_id,
    parent_assoc: :project,
    rate_limit_context: "project",
    template: :project_invitation,
    invitation_path_prefix: "/projects/invitations",
    memberships_module: Memberships,
    preload_after_insert: [:project, :invited_by]
  }

  def list_pending_invitations(project_id), do: InvitationOperations.list_pending_invitations(@config, project_id)

  def create_invitation(%Project{} = project, invited_by, email, role \\ "editor"),
    do: InvitationOperations.create_invitation(@config, project, invited_by, email, role)

  def create_admin_invitation(%Project{} = project, email, role, opts \\ []),
    do: InvitationOperations.create_admin_invitation(@config, project, email, role, opts)

  @doc false
  def deliver_invitation_email(token, opts \\ []), do: InvitationOperations.deliver_invitation_email(@config, token, opts)

  @doc false
  def cancel_invitation_delivery(token), do: InvitationOperations.cancel_invitation_delivery(@config, token)

  def get_invitation_by_token(token), do: InvitationOperations.get_invitation_by_token(@config, token)

  def accept_invitation(%ProjectInvitation{} = invitation, user),
    do: InvitationOperations.accept_invitation(@config, invitation, user)

  def revoke_invitation(%ProjectInvitation{} = invitation), do: InvitationOperations.revoke_invitation(invitation)

  def get_pending_invitation(id), do: InvitationOperations.get_pending_invitation(@config, id)
end
