defmodule Storyarn.Workspaces.Memberships do
  @moduledoc false

  alias Storyarn.Repo
  alias Storyarn.Workspaces.Memberships.Commands.ChangeMemberRole
  alias Storyarn.Workspaces.Memberships.Commands.CreateMembership
  alias Storyarn.Workspaces.Memberships.Commands.ManageMembersAuthority
  alias Storyarn.Workspaces.Memberships.Commands.OwnerAuthority
  alias Storyarn.Workspaces.Memberships.Commands.RemoveMember
  alias Storyarn.Workspaces.Memberships.Commands.TransferOwnership
  alias Storyarn.Workspaces.Memberships.Queries.Authorize
  alias Storyarn.Workspaces.Memberships.Queries.Members
  alias Storyarn.Workspaces.Memberships.Queries.WorkspaceAccess
  alias Storyarn.Workspaces.Memberships.Rules.Permissions

  defdelegate list_workspaces(scope), to: WorkspaceAccess, as: :list
  defdelegate list_workspaces_for_user(user), to: WorkspaceAccess, as: :list_for_user
  defdelegate get_default_workspace(user), to: WorkspaceAccess, as: :default_for
  defdelegate get_workspace(scope, id), to: WorkspaceAccess, as: :get
  defdelegate get_workspace_by_slug(scope, slug), to: WorkspaceAccess, as: :get_by_slug

  defdelegate list_workspace_members(workspace_id), to: Members, as: :list
  defdelegate get_membership(workspace_or_id, user_or_id), to: Members, as: :get
  defdelegate create_membership(workspace_id, user_id, role), to: CreateMembership, as: :create

  def update_member_role(scope, workspace_id, membership_id, role) do
    change_membership(workspace_id, fn -> ChangeMemberRole.change(scope, workspace_id, membership_id, role) end)
  end

  def remove_member(scope, workspace_id, membership_id) do
    change_membership(workspace_id, fn -> RemoveMember.remove(scope, workspace_id, membership_id) end)
  end

  def transfer_owner(scope, workspace_id, target_user_id) do
    if Repo.in_transaction?() do
      {:error, :ownership_transfer_requires_top_level_transaction}
    else
      case TransferOwnership.transfer(scope, workspace_id, target_user_id) do
        {:ok, %{changed?: true} = receipt} = result ->
          Phoenix.PubSub.broadcast(
            Storyarn.PubSub,
            ownership_topic(receipt.workspace_id),
            {:workspace_ownership_transferred, receipt}
          )

          result

        result ->
          result
      end
    end
  end

  def subscribe_ownership_changes(workspace_id) when is_integer(workspace_id) and workspace_id > 0 do
    Phoenix.PubSub.subscribe(Storyarn.PubSub, ownership_topic(workspace_id))
  end

  def subscribe_ownership_changes(_workspace_id), do: {:error, :invalid_workspace_id}

  def subscribe_membership_changes(workspace_id) when is_integer(workspace_id) and workspace_id > 0 do
    Phoenix.PubSub.subscribe(Storyarn.PubSub, membership_topic(workspace_id))
  end

  def subscribe_membership_changes(_workspace_id), do: {:error, :invalid_workspace_id}

  def unsubscribe_ownership_changes(workspace_id) when is_integer(workspace_id) and workspace_id > 0 do
    Phoenix.PubSub.unsubscribe(Storyarn.PubSub, ownership_topic(workspace_id))
  end

  def unsubscribe_ownership_changes(_workspace_id), do: {:error, :invalid_workspace_id}

  def unsubscribe_membership_changes(workspace_id) when is_integer(workspace_id) and workspace_id > 0 do
    Phoenix.PubSub.unsubscribe(Storyarn.PubSub, membership_topic(workspace_id))
  end

  def unsubscribe_membership_changes(_workspace_id), do: {:error, :invalid_workspace_id}

  @doc false
  defdelegate transact_as_owner(scope, workspace_id, operation), to: OwnerAuthority

  @doc false
  defdelegate transact_manage_members(scope, workspace_id, operation),
    to: ManageMembersAuthority,
    as: :transact

  defdelegate authorize(scope, workspace_id, action), to: Authorize, as: :call
  defdelegate can?(role, action), to: Permissions, as: :allowed?

  defp change_membership(workspace_id, operation) do
    if Repo.in_transaction?() do
      {:error, :membership_change_requires_top_level_transaction}
    else
      case operation.() do
        {:ok, membership} = result ->
          Phoenix.PubSub.broadcast(
            Storyarn.PubSub,
            membership_topic(workspace_id),
            {:workspace_membership_changed, %{workspace_id: workspace_id, user_id: membership.user_id}}
          )

          result

        error ->
          error
      end
    end
  end

  defp ownership_topic(workspace_id), do: "workspaces:#{workspace_id}:ownership"
  defp membership_topic(workspace_id), do: "workspaces:#{workspace_id}:memberships"
end
