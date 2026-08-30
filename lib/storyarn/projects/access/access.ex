defmodule Storyarn.Projects.Access do
  @moduledoc false

  alias Storyarn.Projects.Access.Commands.TransferOwnership
  alias Storyarn.Projects.Access.RateLimits
  alias Storyarn.Projects.Invitations
  alias Storyarn.Projects.Memberships
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.ProjectMembership
  alias Storyarn.Projects.Validations
  alias Storyarn.Projects.WorkspaceAccess
  alias Storyarn.Repo

  defdelegate can?(role, action), to: ProjectMembership
  defdelegate effective_role(project_role, workspace_role), to: Memberships
  defdelegate list_project_members(project_id), to: Memberships
  defdelegate get_membership(project_id, user_id), to: Memberships
  defdelegate get_effective_membership(project_id, user_id, workspace_id), to: Memberships
  defdelegate create_membership(project_id, user_id, role), to: Memberships
  defdelegate update_member_role(scope, project_id, membership_id, role), to: Memberships
  defdelegate remove_member(scope, project_id, membership_id), to: Memberships
  defdelegate authorize(scope, project_id, action), to: Memberships
  defdelegate authorize_locked(scope, project_id, action), to: Memberships
  defdelegate authorize_locked(scope, project_id, action, lock_mode), to: Memberships

  def transfer_owner(scope, project_id, target_user_id) do
    if Repo.in_transaction?() do
      {:error, :ownership_transfer_requires_top_level_transaction}
    else
      case TransferOwnership.transfer(scope, project_id, target_user_id) do
        {:ok, %Project{} = project} = result ->
          maybe_broadcast_ownership_transfer(scope, project)
          result

        error ->
          error
      end
    end
  end

  def subscribe_ownership_changes(project_id) when is_integer(project_id) and project_id > 0 do
    Phoenix.PubSub.subscribe(Storyarn.PubSub, ownership_topic(project_id))
  end

  def subscribe_ownership_changes(_project_id), do: {:error, :invalid_project_id}

  defdelegate workspace_can?(role, action), to: WorkspaceAccess, as: :can?
  defdelegate authorize_workspace(scope, workspace_id, action), to: WorkspaceAccess, as: :authorize
  defdelegate get_workspace(scope, workspace_id), to: WorkspaceAccess

  defdelegate get_workspace_membership(workspace_id, user_id),
    to: WorkspaceAccess,
    as: :get_membership

  defdelegate list_pending_invitations(project_id), to: Invitations
  defdelegate create_invitation(scope, project_id, email, role \\ "editor"), to: Invitations
  defdelegate create_admin_invitation(project, email, role, opts \\ []), to: Invitations
  defdelegate deliver_invitation_email(token, opts \\ []), to: Invitations
  defdelegate cancel_invitation_delivery(token), to: Invitations
  defdelegate get_invitation_by_token(token), to: Invitations
  defdelegate accept_invitation(invitation, user), to: Invitations
  defdelegate revoke_invitation(scope, project_id, invitation_id), to: Invitations
  defdelegate get_pending_invitation(id), to: Invitations

  defdelegate check_invitation_rate(project_id, user_id),
    to: RateLimits,
    as: :check

  defdelegate validate_project_email_format(changeset),
    to: Validations,
    as: :validate_email_format

  defp maybe_broadcast_ownership_transfer(%{user: %{id: previous_owner_id}}, %Project{
         id: project_id,
         owner_id: new_owner_id
       })
       when is_integer(previous_owner_id) and previous_owner_id != new_owner_id do
    Phoenix.PubSub.broadcast(
      Storyarn.PubSub,
      ownership_topic(project_id),
      {:project_ownership_transferred,
       %{
         project_id: project_id,
         previous_owner_id: previous_owner_id,
         new_owner_id: new_owner_id
       }}
    )
  end

  defp maybe_broadcast_ownership_transfer(_scope, _project), do: :ok

  defp ownership_topic(project_id), do: "projects:#{project_id}:ownership"
end
