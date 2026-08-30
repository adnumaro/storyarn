defmodule Storyarn.Workspaces.Memberships.Commands.TransferOwnershipTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Accounts.User
  alias Storyarn.Commercial.Billing
  alias Storyarn.Repo
  alias Storyarn.Workspaces
  alias Storyarn.Workspaces.Memberships
  alias Storyarn.Workspaces.Memberships.Commands.TransferOwnership
  alias Storyarn.Workspaces.Workspace

  @outside_pg_bigint 9_223_372_036_854_775_808

  test "transfers ownership atomically and preserves the workspace subscription" do
    owner = user_fixture()
    owner_scope = user_scope_fixture(owner)
    workspace = workspace_fixture(owner)
    receiver = user_without_workspace()
    _receiver_membership = workspace_membership_fixture(workspace, receiver, "member")
    subscription_before = Billing.get_subscription(workspace.id)
    workspace_id = workspace.id
    owner_id = owner.id
    receiver_id = receiver.id
    :ok = Workspaces.subscribe_workspace_ownership_changes(workspace.id)

    assert {:ok,
            %{
              workspace_id: ^workspace_id,
              previous_owner_id: ^owner_id,
              new_owner_id: ^receiver_id,
              changed?: true
            }} = Memberships.transfer_owner(owner_scope, workspace.id, receiver.id)

    assert %{owner_id: ^receiver_id} = Repo.get!(Workspace, workspace.id)
    assert %{role: "admin"} = Memberships.get_membership(workspace.id, owner.id)
    assert %{role: "owner"} = Memberships.get_membership(workspace.id, receiver.id)

    subscription_after = Billing.get_subscription(workspace.id)
    assert subscription_after.id == subscription_before.id
    assert subscription_after.plan == subscription_before.plan
    assert subscription_after.status == subscription_before.status

    assert_receive {:workspace_ownership_transferred,
                    %{
                      workspace_id: ^workspace_id,
                      previous_owner_id: ^owner_id,
                      new_owner_id: ^receiver_id,
                      changed?: true
                    }}
  end

  test "transferring to the current owner is idempotent and does not consume capacity" do
    owner = user_fixture()
    owner_scope = user_scope_fixture(owner)
    workspace = workspace_fixture(owner)
    workspace_id = workspace.id
    owner_id = owner.id
    :ok = Workspaces.subscribe_workspace_ownership_changes(workspace.id)

    assert {:error, :limit_reached, _details} = Billing.can_receive_workspace?(owner)

    assert {:ok,
            %{
              workspace_id: ^workspace_id,
              previous_owner_id: ^owner_id,
              new_owner_id: ^owner_id,
              changed?: false
            }} = Memberships.transfer_owner(owner_scope, workspace.id, owner.id)

    assert %{owner_id: ^owner_id} = Repo.get!(Workspace, workspace.id)
    assert %{role: "owner"} = Memberships.get_membership(workspace.id, owner.id)
    refute_receive {:workspace_ownership_transferred, _receipt}, 50
  end

  test "requires the target to be a direct workspace member" do
    owner = user_fixture()
    owner_scope = user_scope_fixture(owner)
    workspace = workspace_fixture(owner)
    receiver = user_without_workspace()
    :ok = Workspaces.subscribe_workspace_ownership_changes(workspace.id)

    assert {:error, :target_not_member} =
             Memberships.transfer_owner(owner_scope, workspace.id, receiver.id)

    assert_unchanged_owner(workspace.id, owner.id)
    refute_receive {:workspace_ownership_transferred, _receipt}, 50
  end

  test "rejects ids outside PostgreSQL bigint range before querying" do
    owner = user_fixture()
    owner_scope = user_scope_fixture(owner)
    workspace = workspace_fixture(owner)

    assert {:error, :not_found} =
             Memberships.transfer_owner(owner_scope, workspace.id, @outside_pg_bigint)

    assert {:error, :not_found} =
             Memberships.transfer_owner(owner_scope, @outside_pg_bigint, owner.id)

    assert_unchanged_owner(workspace.id, owner.id)
  end

  test "rejects a receiver whose ownership capacity is exhausted" do
    owner = user_fixture()
    owner_scope = user_scope_fixture(owner)
    workspace = workspace_fixture(owner)
    receiver = user_fixture()
    receiver_membership = workspace_membership_fixture(workspace, receiver, "viewer")

    assert {:error, :limit_reached, %{resource: :workspaces_per_user, used: 1, limit: 1}} =
             Memberships.transfer_owner(owner_scope, workspace.id, receiver.id)

    assert_unchanged_owner(workspace.id, owner.id)
    assert %{role: "viewer"} = Repo.reload!(receiver_membership)
  end

  test "reauthorizes the current owner inside the transaction" do
    owner = user_fixture()
    workspace = workspace_fixture(owner)
    member = user_without_workspace()
    receiver = user_without_workspace()
    _member = workspace_membership_fixture(workspace, member, "admin")
    _receiver = workspace_membership_fixture(workspace, receiver, "member")

    assert {:error, :unauthorized} =
             Memberships.transfer_owner(user_scope_fixture(member), workspace.id, receiver.id)

    assert_unchanged_owner(workspace.id, owner.id)
  end

  test "rolls every write back when the internal seam fails after owner demotion" do
    owner = user_fixture()
    owner_scope = user_scope_fixture(owner)
    workspace = workspace_fixture(owner)
    receiver = user_without_workspace()
    receiver_membership = workspace_membership_fixture(workspace, receiver, "member")

    assert {:error, :forced_rollback} =
             TransferOwnership.transfer(owner_scope, workspace.id, receiver.id,
               after_owner_demotion: fn -> {:error, :forced_rollback} end
             )

    assert_unchanged_owner(workspace.id, owner.id)
    assert %{role: "member"} = Repo.reload!(receiver_membership)
  end

  test "rejects an enclosing transaction before writing or publishing" do
    owner = user_fixture()
    workspace = workspace_fixture(owner)
    receiver = user_without_workspace()
    _receiver_membership = workspace_membership_fixture(workspace, receiver, "member")
    :ok = Workspaces.subscribe_workspace_ownership_changes(workspace.id)

    assert {:ok, :outer_committed} =
             Repo.transact(fn ->
               assert {:error, :ownership_transfer_requires_top_level_transaction} =
                        Memberships.transfer_owner(user_scope_fixture(owner), workspace.id, receiver.id)

               {:ok, :outer_committed}
             end)

    assert_unchanged_owner(workspace.id, owner.id)
    refute_receive {:workspace_ownership_transferred, _receipt}, 50
  end

  test "an enclosing rollback cannot hide a partial ownership transfer" do
    owner = user_fixture()
    workspace = workspace_fixture(owner)
    receiver = user_without_workspace()
    _receiver_membership = workspace_membership_fixture(workspace, receiver, "member")
    :ok = Workspaces.subscribe_workspace_ownership_changes(workspace.id)

    assert {:error, :forced_outer_rollback} =
             Repo.transact(fn ->
               assert {:error, :ownership_transfer_requires_top_level_transaction} =
                        Memberships.transfer_owner(user_scope_fixture(owner), workspace.id, receiver.id)

               Repo.rollback(:forced_outer_rollback)
             end)

    assert_unchanged_owner(workspace.id, owner.id)
    refute_receive {:workspace_ownership_transferred, _receipt}, 50
  end

  test "fails closed when persisted ownership is already ambiguous" do
    owner = user_fixture()
    owner_scope = user_scope_fixture(owner)
    workspace = workspace_fixture(owner)
    receiver = user_without_workspace()
    _second_owner = workspace_membership_fixture(workspace, receiver, "owner")

    assert {:error, :ownership_invariant_violation} =
             Memberships.transfer_owner(owner_scope, workspace.id, receiver.id)

    assert Repo.get!(Workspace, workspace.id).owner_id == owner.id
  end

  defp user_without_workspace do
    %User{}
    |> User.email_changeset(%{email: unique_user_email()})
    |> User.confirm_changeset()
    |> Repo.insert!()
  end

  defp assert_unchanged_owner(workspace_id, owner_id) do
    assert Repo.get!(Workspace, workspace_id).owner_id == owner_id
    assert %{role: "owner"} = Memberships.get_membership(workspace_id, owner_id)
  end
end
