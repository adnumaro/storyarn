defmodule Storyarn.Workspaces.ReadOnlyTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.CommercialFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Workspaces

  setup do
    owner = user_fixture()
    workspace = workspace_fixture(owner)
    member = user_fixture()
    viewer = user_fixture()
    member_membership = workspace_membership_fixture(workspace, member, "member")
    viewer_membership = workspace_membership_fixture(workspace, viewer, "viewer")
    extra = lock_account!(owner)

    %{
      owner_user: owner,
      owner: user_scope_fixture(owner),
      member: user_scope_fixture(member),
      workspace: workspace,
      extra: extra,
      member_membership: member_membership,
      viewer_membership: viewer_membership
    }
  end

  test "authorization refuses changes and keeps reading", ctx do
    for action <- [:manage_workspace, :manage_members, :create_project, :use_ai] do
      assert {:error, :read_only} = Workspaces.authorize(ctx.owner, ctx.workspace.id, action), inspect(action)
    end

    for action <- [:view, :view_workspace_usage, :access_workspace_settings, :delete_workspace, :remove_members] do
      assert {:ok, _workspace, _membership} = Workspaces.authorize(ctx.owner, ctx.workspace.id, action),
             inspect(action)
    end

    assert {:error, :read_only} = Workspaces.authorize(ctx.member, ctx.workspace.id, :create_project)
    assert {:ok, _workspace, _membership} = Workspaces.authorize(ctx.member, ctx.workspace.id, :view)
  end

  test "settings, roles and invitations stay as they are", ctx do
    assert {:error, :read_only} = Workspaces.update_workspace(ctx.owner, ctx.workspace.id, %{name: "Renamed"})

    assert {:error, :read_only} =
             Workspaces.update_member_role(ctx.owner, ctx.workspace.id, ctx.viewer_membership.id, "member")

    assert {:error, :read_only} =
             Workspaces.create_invitation(ctx.owner, ctx.workspace.id, unique_user_email(), "viewer")
  end

  test "the owner can still remove members, revoke invitations and delete the workspace", ctx do
    {_token, pending} = workspace_invitation_fixture(ctx.workspace, ctx.owner_user, unique_user_email(), "viewer")

    assert {:ok, _revoked} = Workspaces.revoke_invitation(ctx.owner, ctx.workspace.id, pending.id)
    assert {:ok, _removed} = Workspaces.remove_member(ctx.owner, ctx.workspace.id, ctx.member_membership.id)
    assert {:ok, _deleted} = Workspaces.delete_workspace(ctx.owner, ctx.workspace.id)
  end

  test "an invitation sent before the lock cannot be accepted", ctx do
    invitee = user_fixture()
    {_token, invitation} = workspace_invitation_fixture(ctx.workspace, ctx.owner_user, invitee.email, "viewer")

    assert {:error, :read_only} = Workspaces.accept_invitation(invitation, invitee)
  end

  test "the account cannot add workspaces", ctx do
    assert {:error, :read_only} =
             Workspaces.create_workspace(ctx.owner, %{
               name: "Third saga",
               slug: "third-saga-#{System.unique_integer([:positive])}"
             })
  end

  test "everything unlocks once the account is back within its limits", ctx do
    unlock_account!(ctx.extra)

    assert {:ok, _workspace, _membership} = Workspaces.authorize(ctx.owner, ctx.workspace.id, :manage_workspace)
    assert {:ok, _workspace} = Workspaces.update_workspace(ctx.owner, ctx.workspace.id, %{name: "Renamed"})
  end
end
