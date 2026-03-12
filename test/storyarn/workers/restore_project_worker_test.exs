defmodule Storyarn.Workers.RestoreProjectWorkerTest do
  use Storyarn.DataCase, async: true
  use Oban.Testing, repo: Storyarn.Repo

  alias Storyarn.Collaboration
  alias Storyarn.Projects
  alias Storyarn.Versioning
  alias Storyarn.Workers.RestoreProjectWorker

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  setup do
    user = user_fixture()
    project = project_fixture(user)
    %{user: user, project: project}
  end

  describe "perform/1" do
    test "restores snapshot and releases lock on success", %{project: project, user: user} do
      # Create a snapshot to restore
      {:ok, snapshot} = Versioning.create_project_snapshot(project.id, user.id, title: "Test")

      # Acquire lock
      {:ok, _} = Projects.acquire_restoration_lock(project.id, user.id)

      # Subscribe to restoration and dashboard events
      Collaboration.subscribe_restoration(project.id)
      Collaboration.subscribe_dashboard(project.id)

      # Run worker
      assert :ok =
               perform_job(RestoreProjectWorker, %{
                 project_id: project.id,
                 snapshot_id: snapshot.id,
                 user_id: user.id
               })

      # Lock should be released
      assert Projects.restoration_in_progress?(project.id) == false

      # Should have received completion broadcast
      assert_received {:project_restoration_completed, payload}
      assert payload.snapshot_title == "Test"

      # Should have invalidated dashboard cache
      assert_received {:dashboard_invalidate, :all}
    end

    test "releases lock on failure (snapshot not found)", %{project: project, user: user} do
      # Acquire lock
      {:ok, _} = Projects.acquire_restoration_lock(project.id, user.id)

      # Subscribe to restoration events
      Collaboration.subscribe_restoration(project.id)

      # Run worker with non-existent snapshot
      assert {:error, :snapshot_not_found} =
               perform_job(RestoreProjectWorker, %{
                 project_id: project.id,
                 snapshot_id: -1,
                 user_id: user.id
               })

      # Lock should be released even on failure
      assert Projects.restoration_in_progress?(project.id) == false

      # Should have received failure broadcast
      assert_received {:project_restoration_failed, %{reason: "Snapshot not found"}}
    end
  end
end
