defmodule Storyarn.Projects.Access.Commands.TransferOwnershipTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Projects
  alias Storyarn.Projects.Access.Commands.TransferOwnership
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.ProjectMembership
  alias Storyarn.Repo
  alias Storyarn.Workspaces.Workspace

  @outside_pg_bigint 9_223_372_036_854_775_808

  test "transfers canonical ownership to an existing direct member" do
    owner = user_fixture()
    owner_scope = user_scope_fixture(owner)
    project = project_fixture(owner)
    receiver = user_fixture()
    receiver_membership = membership_fixture(project, receiver, "viewer")
    :ok = Projects.subscribe_project_ownership_changes(project.id)

    assert {:ok, %Project{owner_id: receiver_id}} =
             Projects.transfer_owner(owner_scope, project.id, receiver.id)

    assert receiver_id == receiver.id
    assert %{role: "editor"} = Projects.get_membership(project.id, owner.id)
    assert %{role: "owner"} = Repo.reload!(receiver_membership)
    assert Repo.get!(Project, project.id).owner_id == receiver.id
    assert Repo.get!(Workspace, project.workspace_id).owner_id == owner.id

    assert_receive {:project_ownership_transferred,
                    %{
                      project_id: project_id,
                      previous_owner_id: previous_owner_id,
                      new_owner_id: new_owner_id
                    }}

    assert project_id == project.id
    assert previous_owner_id == owner.id
    assert new_owner_id == receiver.id
  end

  test "transferring to the canonical owner is idempotent after validating the invariant" do
    owner = user_fixture()
    project = project_fixture(owner)
    :ok = Projects.subscribe_project_ownership_changes(project.id)

    assert {:ok, %Project{owner_id: owner_id}} =
             Projects.transfer_owner(user_scope_fixture(owner), project.id, owner.id)

    assert owner_id == owner.id
    assert [%{user_id: owner_id, role: "owner"}] = Projects.list_project_members(project.id)
    assert owner_id == owner.id
    refute_receive {:project_ownership_transferred, _receipt}, 50
  end

  test "requires the receiver to be a direct project member" do
    owner = user_fixture()
    project = project_fixture(owner)
    receiver = user_fixture()
    _inherited_access = workspace_membership_fixture(%{id: project.workspace_id}, receiver, "admin")
    :ok = Projects.subscribe_project_ownership_changes(project.id)

    assert {:error, :target_not_member} =
             Projects.transfer_owner(user_scope_fixture(owner), project.id, receiver.id)

    assert_unchanged_owner(project.id, owner.id)
    refute_receive {:project_ownership_transferred, _receipt}, 50
  end

  test "requires the actor to remain the canonical owner" do
    owner = user_fixture()
    project = project_fixture(owner)
    editor = user_fixture()
    receiver = user_fixture()
    _editor_membership = membership_fixture(project, editor, "editor")
    _receiver_membership = membership_fixture(project, receiver, "viewer")

    assert {:error, :unauthorized} =
             Projects.transfer_owner(user_scope_fixture(editor), project.id, receiver.id)

    assert_unchanged_owner(project.id, owner.id)
  end

  test "fails closed when persisted ownership is ambiguous" do
    owner = user_fixture()
    project = project_fixture(owner)
    receiver = user_fixture()
    _second_owner = membership_fixture(project, receiver, "owner")

    assert {:error, :ownership_invariant_violation} =
             Projects.transfer_owner(user_scope_fixture(owner), project.id, receiver.id)

    assert Repo.get!(Project, project.id).owner_id == owner.id
  end

  test "fails closed when the canonical owner membership is missing" do
    owner = user_fixture()
    project = project_fixture(owner)
    receiver = user_fixture()
    _receiver_membership = membership_fixture(project, receiver, "editor")

    project.id
    |> Projects.get_membership(owner.id)
    |> Ecto.Changeset.change(role: "editor")
    |> Repo.update!()

    assert {:error, :ownership_invariant_violation} =
             Projects.transfer_owner(user_scope_fixture(owner), project.id, receiver.id)

    assert Repo.get!(Project, project.id).owner_id == owner.id
  end

  test "self-transfer still fails closed when a second owner exists" do
    owner = user_fixture()
    project = project_fixture(owner)
    second_owner = user_fixture()
    _second_owner_membership = membership_fixture(project, second_owner, "owner")

    assert {:error, :ownership_invariant_violation} =
             Projects.transfer_owner(user_scope_fixture(owner), project.id, owner.id)
  end

  test "returns not_found for a soft-deleted project" do
    owner = user_fixture()
    owner_scope = user_scope_fixture(owner)
    project = project_fixture(owner)
    receiver = user_fixture()
    _receiver_membership = membership_fixture(project, receiver, "editor")

    assert {:ok, _deleted} = Projects.delete_project(owner_scope, project.id)
    assert {:error, :not_found} = Projects.transfer_owner(owner_scope, project.id, receiver.id)
  end

  test "rejects ids outside PostgreSQL bigint range before querying" do
    owner = user_fixture()
    owner_scope = user_scope_fixture(owner)
    project = project_fixture(owner)

    assert {:error, :not_found} =
             Projects.transfer_owner(owner_scope, project.id, @outside_pg_bigint)

    assert {:error, :not_found} =
             Projects.transfer_owner(owner_scope, @outside_pg_bigint, owner.id)

    assert_unchanged_owner(project.id, owner.id)
  end

  test "rolls every write back when the internal seam fails after owner demotion" do
    owner = user_fixture()
    project = project_fixture(owner)
    receiver = user_fixture()
    receiver_membership = membership_fixture(project, receiver, "editor")

    assert {:error, :forced_rollback} =
             TransferOwnership.transfer(user_scope_fixture(owner), project.id, receiver.id,
               after_owner_demotion: fn -> {:error, :forced_rollback} end
             )

    assert_unchanged_owner(project.id, owner.id)
    assert %{role: "editor"} = Repo.reload!(receiver_membership)
  end

  test "turns an unexpected internal seam result into a named error and rolls every write back" do
    owner = user_fixture()
    project = project_fixture(owner)
    receiver = user_fixture()
    receiver_membership = membership_fixture(project, receiver, "editor")

    assert {:error, :ownership_transfer_failed} =
             TransferOwnership.transfer(user_scope_fixture(owner), project.id, receiver.id,
               after_owner_demotion: fn -> :unexpected_result end
             )

    assert_unchanged_owner(project.id, owner.id)
    assert %{role: "editor"} = Repo.reload!(receiver_membership)
  end

  test "rejects an enclosing transaction before writing or publishing" do
    owner = user_fixture()
    project = project_fixture(owner)
    receiver = user_fixture()
    _receiver_membership = membership_fixture(project, receiver, "editor")
    :ok = Projects.subscribe_project_ownership_changes(project.id)

    assert {:ok, :outer_committed} =
             Repo.transact(fn ->
               assert {:error, :ownership_transfer_requires_top_level_transaction} =
                        Projects.transfer_owner(user_scope_fixture(owner), project.id, receiver.id)

               {:ok, :outer_committed}
             end)

    assert_unchanged_owner(project.id, owner.id)
    refute_receive {:project_ownership_transferred, _receipt}, 50
  end

  test "an enclosing rollback cannot hide a partial ownership transfer" do
    owner = user_fixture()
    project = project_fixture(owner)
    receiver = user_fixture()
    _receiver_membership = membership_fixture(project, receiver, "editor")
    :ok = Projects.subscribe_project_ownership_changes(project.id)

    assert {:error, :forced_outer_rollback} =
             Repo.transact(fn ->
               assert {:error, :ownership_transfer_requires_top_level_transaction} =
                        Projects.transfer_owner(user_scope_fixture(owner), project.id, receiver.id)

               Repo.rollback(:forced_outer_rollback)
             end)

    assert_unchanged_owner(project.id, owner.id)
    refute_receive {:project_ownership_transferred, _receipt}, 50
  end

  test "owner-only writes reject an ambiguous owner state" do
    owner = user_fixture()
    project = project_fixture(owner)
    second_owner = user_fixture()
    _second_owner_membership = membership_fixture(project, second_owner, "owner")

    assert {:error, :ownership_invariant_violation} =
             Projects.update_project(user_scope_fixture(owner), project.id, %{name: "Must not persist"})

    assert Repo.get!(Project, project.id).name == project.name
  end

  test "a non-canonical owner role cannot perform owner-only writes" do
    owner = user_fixture()
    project = project_fixture(owner)
    corrupt_owner = user_fixture()
    corrupt_membership = membership_fixture(project, corrupt_owner, "owner")

    assert {:error, :unauthorized} =
             Projects.remove_member(
               user_scope_fixture(corrupt_owner),
               project.id,
               corrupt_membership.id
             )

    assert Repo.get!(ProjectMembership, corrupt_membership.id)
  end

  defp assert_unchanged_owner(project_id, owner_id) do
    assert Repo.get!(Project, project_id).owner_id == owner_id
    assert %{role: "owner"} = Projects.get_membership(project_id, owner_id)
  end
end
