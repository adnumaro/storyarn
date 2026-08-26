defmodule Storyarn.Projects.SnapshotAccountingTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Projects

  test "composes the accounting view for managers and rejects viewers" do
    owner = user_fixture()
    project = project_fixture(owner)
    viewer = user_fixture()
    _membership = membership_fixture(project, viewer, "viewer")

    assert {:ok, accounting} =
             Projects.project_snapshot_accounting(user_scope_fixture(owner), project.id)

    assert accounting.snapshots == []
    assert accounting.snapshot_slots_used == 0
    assert accounting.storage_usage.accounted_bytes == 0

    assert {:error, :unauthorized} =
             Projects.project_snapshot_accounting(user_scope_fixture(viewer), project.id)
  end
end
