defmodule Storyarn.Workspaces.Memberships.Commands.ActorAwareMembershipTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Accounts.User
  alias Storyarn.Repo
  alias Storyarn.Workspaces.Memberships

  @outside_pg_bigint 9_223_372_036_854_775_808

  setup do
    owner = user_fixture()
    workspace = workspace_fixture(owner)
    member = user_without_workspace()
    membership = workspace_membership_fixture(workspace, member, "member")

    %{
      owner: owner,
      owner_scope: user_scope_fixture(owner),
      workspace: workspace,
      member: member,
      membership: membership
    }
  end

  test "the current owner can update a locked current membership", context do
    assert {:ok, %{role: "admin"}} =
             Memberships.update_member_role(
               context.owner_scope,
               context.workspace.id,
               context.membership.id,
               "admin"
             )
  end

  test "a non-owner cannot update another membership", context do
    assert {:error, :unauthorized} =
             Memberships.update_member_role(
               user_scope_fixture(context.member),
               context.workspace.id,
               context.membership.id,
               "viewer"
             )

    assert %{role: "member"} = Repo.reload!(context.membership)
  end

  test "role changes re-read the target and protect a newly promoted owner", context do
    assert {:ok, _receipt} =
             Memberships.transfer_owner(
               context.owner_scope,
               context.workspace.id,
               context.member.id
             )

    assert {:error, :cannot_change_owner_role} =
             Memberships.update_member_role(
               user_scope_fixture(context.member),
               context.workspace.id,
               context.membership.id,
               "viewer"
             )

    assert %{role: "owner"} = Memberships.get_membership(context.workspace.id, context.member.id)
  end

  test "the current owner can remove a locked current membership", context do
    assert {:ok, _membership} =
             Memberships.remove_member(
               context.owner_scope,
               context.workspace.id,
               context.membership.id
             )

    assert Memberships.get_membership(context.workspace.id, context.member.id) == nil
  end

  test "a non-owner cannot remove another membership", context do
    assert {:error, :unauthorized} =
             Memberships.remove_member(
               user_scope_fixture(context.member),
               context.workspace.id,
               context.membership.id
             )

    assert Repo.reload!(context.membership)
  end

  test "removal re-reads the target and protects a newly promoted owner", context do
    assert {:ok, _receipt} =
             Memberships.transfer_owner(
               context.owner_scope,
               context.workspace.id,
               context.member.id
             )

    assert {:error, :cannot_remove_owner} =
             Memberships.remove_member(
               user_scope_fixture(context.member),
               context.workspace.id,
               context.membership.id
             )

    assert %{role: "owner"} = Memberships.get_membership(context.workspace.id, context.member.id)
  end

  test "cross-workspace membership ids fail without touching another workspace", context do
    other_owner = user_fixture()
    other_workspace = workspace_fixture(other_owner)
    other_member = user_without_workspace()
    other_membership = workspace_membership_fixture(other_workspace, other_member, "member")

    assert {:error, :not_found} =
             Memberships.remove_member(
               context.owner_scope,
               context.workspace.id,
               other_membership.id
             )

    assert Repo.reload!(context.membership)
    assert Repo.reload!(other_membership)
  end

  test "actor-aware membership writes reject ids outside PostgreSQL bigint", context do
    assert {:error, :not_found} =
             Memberships.update_member_role(
               context.owner_scope,
               context.workspace.id,
               @outside_pg_bigint,
               "viewer"
             )

    assert {:error, :not_found} =
             Memberships.remove_member(
               context.owner_scope,
               context.workspace.id,
               @outside_pg_bigint
             )

    assert {:error, :not_found} =
             Memberships.remove_member(context.owner_scope, @outside_pg_bigint, 1)
  end

  defp user_without_workspace do
    %User{}
    |> User.email_changeset(%{email: unique_user_email()})
    |> User.confirm_changeset()
    |> Repo.insert!()
  end
end
