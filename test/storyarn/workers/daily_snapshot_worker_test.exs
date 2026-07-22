defmodule Storyarn.Workers.DailySnapshotWorkerTest do
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import Ecto.Query
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Repo
  alias Storyarn.Versioning
  alias Storyarn.Versioning.ProjectSnapshot
  alias Storyarn.Workers.DailySnapshotWorker

  setup do
    original_config = Application.get_env(:storyarn, DailySnapshotWorker)
    Application.put_env(:storyarn, DailySnapshotWorker, pruning_enabled: false)

    on_exit(fn ->
      if is_nil(original_config) do
        Application.delete_env(:storyarn, DailySnapshotWorker)
      else
        Application.put_env(:storyarn, DailySnapshotWorker, original_config)
      end
    end)

    :ok
  end

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
      assert Versioning.count_project_snapshots(project.id) == 0
    end

    test "skips when no changes since last snapshot" do
      project = project_fixture()
      _flow = flow_fixture(project)

      # Create a snapshot after the flow
      insert_snapshot(project.id)

      assert :ok = perform_job(DailySnapshotWorker, %{})

      # Should still have just 1 snapshot (no new one created)
      assert Versioning.count_project_snapshots(project.id) == 1
    end

    test "creates snapshot when project has changes and no recent snapshot" do
      project = project_fixture()
      # Create a flow so there's a real entity to change-detect
      _flow = flow_fixture(project)

      assert Versioning.count_project_snapshots(project.id) == 0

      assert :ok = perform_job(DailySnapshotWorker, %{})

      # Should have created exactly 1 auto snapshot
      assert Versioning.count_project_snapshots(project.id) == 1

      [snapshot] = Versioning.list_project_snapshots(project.id)
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
      assert Versioning.count_project_snapshots(project.id) == 1
    end

    test "keeps every automatic recovery point while pruning is disabled" do
      {project, snapshots} = project_at_snapshot_limit()

      assert :ok = perform_job(DailySnapshotWorker, %{})
      assert Versioning.count_project_snapshots(project.id) == 11

      snapshot_ids =
        project.id
        |> Versioning.list_project_snapshots()
        |> MapSet.new(& &1.id)

      assert Enum.all?(snapshots, &MapSet.member?(snapshot_ids, &1.id))
    end

    test "prunes only when explicitly enabled with literal true" do
      {project, snapshots} = project_at_snapshot_limit()
      oldest = Enum.min_by(snapshots, & &1.version_number)

      Application.put_env(:storyarn, DailySnapshotWorker, pruning_enabled: true)

      assert :ok = perform_job(DailySnapshotWorker, %{})
      assert Versioning.count_project_snapshots(project.id) == 10

      snapshot_ids =
        project.id
        |> Versioning.list_project_snapshots()
        |> MapSet.new(& &1.id)

      refute MapSet.member?(snapshot_ids, oldest.id)
    end

    test "fails closed when the oldest snapshot has a non-canonical persisted key" do
      {project, snapshots} = project_at_snapshot_limit()
      oldest = Enum.min_by(snapshots, & &1.version_number)

      Repo.update_all(
        from(snapshot in ProjectSnapshot, where: snapshot.id == ^oldest.id),
        set: [storage_key: "test/snapshot/corrupted.json.gz"]
      )

      Application.put_env(:storyarn, DailySnapshotWorker, pruning_enabled: true)

      assert :ok = perform_job(DailySnapshotWorker, %{})
      assert Versioning.count_project_snapshots(project.id) == 11
      assert Repo.get(ProjectSnapshot, oldest.id)
    end
  end

  defp project_at_snapshot_limit do
    project = project_fixture()

    snapshots =
      for _index <- 1..10 do
        insert_snapshot(project.id, is_auto: true)
      end

    past = DateTime.utc_now() |> DateTime.add(-86_400, :second) |> DateTime.truncate(:second)

    Repo.update_all(
      from(snapshot in ProjectSnapshot, where: snapshot.project_id == ^project.id),
      set: [inserted_at: past]
    )

    _flow = flow_fixture(project)
    {project, snapshots}
  end

  defp insert_snapshot(project_id, opts \\ []) do
    is_auto = Keyword.get(opts, :is_auto, false)

    {:ok, snapshot} =
      Versioning.create_project_snapshot(project_id, nil, is_auto: is_auto)

    snapshot
  end
end
