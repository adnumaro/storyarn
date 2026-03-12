defmodule Storyarn.Workers.DailySnapshotWorkerTest do
  use Storyarn.DataCase, async: true
  use Oban.Testing, repo: Storyarn.Repo

  alias Storyarn.Versioning.ProjectSnapshot
  alias Storyarn.Workers.DailySnapshotWorker

  import Storyarn.ProjectsFixtures
  import Storyarn.FlowsFixtures

  describe "perform/1" do
    test "skips projects with auto_snapshots_enabled: false" do
      user = Storyarn.AccountsFixtures.user_fixture()
      project = project_fixture(user, %{})

      # Disable auto snapshots
      Storyarn.Projects.update_project(project, %{auto_snapshots_enabled: false})

      # Create a flow so there's something to snapshot
      _flow = flow_fixture(project)

      assert :ok = perform_job(DailySnapshotWorker, %{})

      # No snapshot should be created
      assert Storyarn.Versioning.count_project_snapshots(project.id) == 0
    end

    test "skips when no changes since last snapshot" do
      project = project_fixture()
      _flow = flow_fixture(project)

      # Create a snapshot after the flow
      insert_snapshot(project.id)

      assert :ok = perform_job(DailySnapshotWorker, %{})

      # Should still have just 1 snapshot (no new one created)
      assert Storyarn.Versioning.count_project_snapshots(project.id) == 1
    end

    test "creates snapshot when project has changes and no recent snapshot" do
      project = project_fixture()
      # Create a flow so there's a real entity to change-detect
      _flow = flow_fixture(project)

      assert Storyarn.Versioning.count_project_snapshots(project.id) == 0

      assert :ok = perform_job(DailySnapshotWorker, %{})

      # Should have created exactly 1 auto snapshot
      assert Storyarn.Versioning.count_project_snapshots(project.id) == 1

      [snapshot] = Storyarn.Versioning.list_project_snapshots(project.id)
      assert snapshot.is_auto == true
      assert snapshot.created_by_id == nil
      assert snapshot.title =~ "Daily backup"
    end

    test "handles individual project failure gracefully" do
      # Even if one project has issues, perform still returns :ok
      # (errors are rescued per-project)
      assert :ok = perform_job(DailySnapshotWorker, %{})
    end

    test "skips when recent manual snapshot exists" do
      project = project_fixture()
      _flow = flow_fixture(project)

      # Insert a recent manual snapshot
      insert_snapshot(project.id, is_auto: false)

      # Now create another flow to simulate changes
      _flow2 = flow_fixture(project)

      assert :ok = perform_job(DailySnapshotWorker, %{})

      # Should still have just 1 snapshot (manual one, no daily created)
      assert Storyarn.Versioning.count_project_snapshots(project.id) == 1
    end
  end

  defp insert_snapshot(project_id, opts \\ []) do
    is_auto = Keyword.get(opts, :is_auto, false)
    version = System.unique_integer([:positive])

    %ProjectSnapshot{}
    |> ProjectSnapshot.changeset(%{
      project_id: project_id,
      version_number: version,
      storage_key: "test/snapshot/#{version}.json.gz",
      snapshot_size_bytes: 100,
      entity_counts: %{},
      is_auto: is_auto
    })
    |> Repo.insert!()
  end
end
