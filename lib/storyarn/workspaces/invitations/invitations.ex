defmodule Storyarn.Workspaces.Invitations do
  @moduledoc """
  Public capability boundary for workspace invitations.

  The workspace context delegates invitation lifecycle operations here while
  commands, queries, rules, token issuance, and delivery remain private to the
  capability.
  """

  alias Storyarn.Workspaces.Invitations.Commands.Accept
  alias Storyarn.Workspaces.Invitations.Commands.Create
  alias Storyarn.Workspaces.Invitations.Commands.Revoke
  alias Storyarn.Workspaces.Invitations.Delivery.Handler
  alias Storyarn.Workspaces.Invitations.Queries.ByToken
  alias Storyarn.Workspaces.Invitations.Queries.Pending
  alias Storyarn.Workspaces.WorkspaceInvitation

  defdelegate validate_email_format(changeset), to: WorkspaceInvitation

  defdelegate list_pending_invitations(workspace_id), to: Pending, as: :list

  def create_invitation(workspace, invited_by, email, role \\ "member") do
    Create.execute(workspace, invited_by, email, role)
  end

  def create_admin_invitation(workspace, email, role, opts \\ []) do
    Create.execute_admin(workspace, email, role, opts)
  end

  defdelegate get_invitation_by_token(token), to: ByToken, as: :get
  defdelegate accept_invitation(invitation, user), to: Accept, as: :execute
  defdelegate revoke_invitation(invitation), to: Revoke, as: :execute

  def deliver_invitation_email(encoded_token, opts \\ []) do
    Handler.deliver(encoded_token, opts)
  end

  defdelegate cancel_invitation_delivery(encoded_token), to: Handler, as: :cancel
  defdelegate get_pending_invitation(id), to: Pending, as: :get
end
