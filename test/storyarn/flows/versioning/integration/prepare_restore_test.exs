defmodule Storyarn.Flows.VersioningPrepareRestoreTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Flows
  alias Storyarn.Flows.Versioning
  alias Storyarn.Flows.Versioning.EntityVersionRecord
  alias Storyarn.Flows.Versioning.SnapshotStorage

  setup do
    user = user_fixture()
    project = project_fixture(user)
    flow = flow_fixture(project)

    %{flow: flow, project: project, user: user}
  end

  describe "prepare_restore/2" do
    test "treats a Flow without a latest version as unsaved", %{flow: flow} do
      assert {:ok, :unsaved_changes} =
               Versioning.prepare_restore(flow, %EntityVersionRecord{})
    end

    test "treats an unreadable latest snapshot as unsaved", %{flow: flow, user: user} do
      latest = create_version!(flow, user)
      assert :ok = SnapshotStorage.delete(latest.storage_key)

      assert {:ok, :unsaved_changes} = Versioning.prepare_restore(flow, latest)
    end

    test "treats current Flow changes after the latest version as unsaved", %{
      flow: flow,
      user: user
    } do
      latest = create_version!(flow, user)
      assert {:ok, changed} = Flows.update_flow(flow, %{name: "Changed after snapshot"})

      assert {:ok, :unsaved_changes} = Versioning.prepare_restore(changed, latest)
    end

    test "returns a conflict report when current state matches the latest version", %{
      flow: flow,
      user: user
    } do
      target = create_version!(flow, user)
      assert {:ok, current} = Flows.update_flow(flow, %{name: "Current saved state"})
      _latest = create_version!(current, user)

      assert {:ok, {:ready, report}} = Versioning.prepare_restore(current, target)
      assert report.has_conflicts == false
      assert report.conflicts == []
      assert report.shortcut_collision == false
    end

    test "fails closed when a clean Flow targets an unreadable snapshot", %{
      flow: flow,
      user: user
    } do
      target = create_version!(flow, user)
      assert {:ok, current} = Flows.update_flow(flow, %{name: "Current saved state"})
      _latest = create_version!(current, user)
      assert :ok = SnapshotStorage.delete(target.storage_key)

      assert {:error, :target_snapshot_unreadable} =
               Versioning.prepare_restore(current, target)
    end

    test "fails closed when a clean Flow targets another Flow's version", %{
      flow: flow,
      project: project,
      user: user
    } do
      _latest = create_version!(flow, user)
      other_flow = flow_fixture(project)
      foreign_target = create_version!(other_flow, user)

      assert {:error, :target_snapshot_unreadable} =
               Versioning.prepare_restore(flow, foreign_target)
    end
  end

  describe "prepare_restore_conflicts/2" do
    test "returns the Flow-owned conflict report for a readable in-scope target", %{
      flow: flow,
      user: user
    } do
      target = create_version!(flow, user)

      assert {:ok, report} = Versioning.prepare_restore_conflicts(flow, target)
      assert report.has_conflicts == false
      assert report.conflicts == []
    end

    test "rejects a corrupt target snapshot", %{flow: flow, user: user} do
      target = create_version!(flow, user)
      assert :ok = SnapshotStorage.delete(target.storage_key)

      assert {:error, :target_snapshot_unreadable} =
               Versioning.prepare_restore_conflicts(flow, target)
    end

    test "rejects a target owned by another Flow", %{
      flow: flow,
      project: project,
      user: user
    } do
      other_flow = flow_fixture(project)
      foreign_target = create_version!(other_flow, user)

      assert {:error, :target_snapshot_unreadable} =
               Versioning.prepare_restore_conflicts(flow, foreign_target)
    end
  end

  defp create_version!(flow, user) do
    assert {:ok, version} = Versioning.create_version(flow, user.id, skip_diff: true)
    on_exit(fn -> SnapshotStorage.delete(version.storage_key) end)
    version
  end
end
