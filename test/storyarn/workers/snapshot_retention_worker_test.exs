defmodule Storyarn.Workers.SnapshotRetentionWorkerTest do
  use Storyarn.DataCase, async: true
  use Oban.Testing, repo: Storyarn.Repo

  alias Storyarn.Projects
  alias Storyarn.Repo
  alias Storyarn.Versioning
  alias Storyarn.Workers.SnapshotRetentionWorker

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  setup do
    user = user_fixture()
    project = project_fixture(user)

    %{user: user, project: project}
  end

  describe "perform/1" do
    test "prunes expired auto snapshots from deleted projects", %{user: user, project: project} do
      _flow = flow_fixture(project, %{name: "Test Flow"})

      # Create an auto snapshot
      {:ok, snapshot} =
        Versioning.create_project_snapshot(project.id, nil, title: "Daily backup", is_auto: true)

      # Backdate the snapshot to 60 days ago (beyond free plan's 30-day retention)
      past = DateTime.add(DateTime.utc_now(), -60 * 86_400, :second) |> DateTime.truncate(:second)

      Repo.query!("UPDATE project_snapshots SET inserted_at = $1 WHERE id = $2", [
        past,
        snapshot.id
      ])

      # Soft-delete the project
      {:ok, _} = Projects.delete_project(project, user.id)

      # Run retention worker
      assert :ok = perform_job(SnapshotRetentionWorker, %{})

      # Snapshot should be pruned
      assert Versioning.count_project_snapshots(project.id) == 0
    end

    test "does not prune manual snapshots", %{user: user, project: project} do
      _flow = flow_fixture(project, %{name: "Test Flow"})

      # Create a manual snapshot (is_auto: false)
      {:ok, snapshot} =
        Versioning.create_project_snapshot(project.id, user.id, title: "Gold Master")

      # Backdate beyond retention
      past = DateTime.add(DateTime.utc_now(), -60 * 86_400, :second) |> DateTime.truncate(:second)

      Repo.query!("UPDATE project_snapshots SET inserted_at = $1 WHERE id = $2", [
        past,
        snapshot.id
      ])

      # Soft-delete the project
      {:ok, _} = Projects.delete_project(project, user.id)

      # Run retention worker
      assert :ok = perform_job(SnapshotRetentionWorker, %{})

      # Manual snapshot should survive
      assert Versioning.count_project_snapshots(project.id) == 1
    end

    test "does not prune snapshots within retention period", %{user: user, project: project} do
      _flow = flow_fixture(project, %{name: "Test Flow"})

      # Create a recent auto snapshot
      {:ok, _snapshot} =
        Versioning.create_project_snapshot(project.id, nil, title: "Daily backup", is_auto: true)

      # Soft-delete the project
      {:ok, _} = Projects.delete_project(project, user.id)

      # Run retention worker
      assert :ok = perform_job(SnapshotRetentionWorker, %{})

      # Recent snapshot should survive
      assert Versioning.count_project_snapshots(project.id) == 1
    end

    test "permanently deletes project when no snapshots remain", %{
      user: user,
      project: project
    } do
      # Soft-delete the project (no snapshots exist)
      {:ok, _} = Projects.delete_project(project, user.id)

      # Run retention worker
      assert :ok = perform_job(SnapshotRetentionWorker, %{})

      # Project should be permanently deleted
      assert Repo.get(Projects.Project, project.id) == nil
    end

    test "does not affect non-deleted projects", %{project: project} do
      _flow = flow_fixture(project, %{name: "Test Flow"})

      {:ok, _snapshot} =
        Versioning.create_project_snapshot(project.id, nil, title: "Daily backup", is_auto: true)

      # Don't delete the project — run retention worker
      assert :ok = perform_job(SnapshotRetentionWorker, %{})

      # Snapshot should still exist
      assert Versioning.count_project_snapshots(project.id) == 1
    end
  end
end
