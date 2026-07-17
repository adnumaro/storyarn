defmodule Storyarn.Workers.RecoverProjectWorkerTest do
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Projects
  alias Storyarn.Repo
  alias Storyarn.Versioning
  alias Storyarn.Versioning.RestorePolicy
  alias Storyarn.Workers.RecoverProjectWorker

  setup do
    restore_policy =
      Application.get_env(:storyarn, RestorePolicy, [])

    on_exit(fn ->
      Application.put_env(
        :storyarn,
        RestorePolicy,
        restore_policy
      )
    end)

    user = user_fixture()
    project = project_fixture(user)

    %{user: user, project: project}
  end

  describe "perform/1" do
    test "recovers project from snapshot", %{user: user, project: project} do
      _sheet = sheet_fixture(project, %{name: "Test Sheet"})
      _flow = flow_fixture(project, %{name: "Test Flow"})

      {:ok, snapshot} = Versioning.create_project_snapshot(project.id, user.id, title: "Backup")
      {:ok, _deleted_project} = Projects.delete_project(project, user.id)

      # Subscribe to recovery broadcasts
      Phoenix.PubSub.subscribe(
        Storyarn.PubSub,
        "workspace:#{project.workspace_id}:recovery"
      )

      assert :ok =
               perform_job(RecoverProjectWorker, %{
                 workspace_id: project.workspace_id,
                 snapshot_id: snapshot.id,
                 project_id: project.id,
                 user_id: user.id
               })

      assert_received {:recovery_completed, %{project_name: name}}
      assert name =~ "(Recovered)"
    end

    test "broadcasts failure for missing snapshot", %{user: user, project: project} do
      {:ok, _deleted_project} = Projects.delete_project(project, user.id)

      Phoenix.PubSub.subscribe(
        Storyarn.PubSub,
        "workspace:#{project.workspace_id}:recovery"
      )

      assert {:error, :snapshot_not_found} =
               perform_job(RecoverProjectWorker, %{
                 workspace_id: project.workspace_id,
                 snapshot_id: 999_999,
                 project_id: project.id,
                 user_id: user.id
               })

      assert_received {:recovery_failed, %{reason: "Snapshot not found"}}
    end

    test "rejects an already queued recovery when containment is active", %{
      user: user,
      project: project
    } do
      {:ok, snapshot} =
        Versioning.create_project_snapshot(project.id, user.id, title: "Blocked")

      {:ok, _deleted_project} = Projects.delete_project(project, user.id)

      Phoenix.PubSub.subscribe(
        Storyarn.PubSub,
        "workspace:#{project.workspace_id}:recovery"
      )

      policy =
        Application.get_env(:storyarn, RestorePolicy, [])

      Application.put_env(
        :storyarn,
        RestorePolicy,
        Keyword.put(policy, :deleted_project_recovery, false)
      )

      project_count = Repo.aggregate(Projects.Project, :count)

      assert {:error, :restore_temporarily_disabled} =
               perform_job(RecoverProjectWorker, %{
                 workspace_id: project.workspace_id,
                 snapshot_id: snapshot.id,
                 project_id: project.id,
                 user_id: user.id
               })

      assert Repo.aggregate(Projects.Project, :count) == project_count
      assert_received {:recovery_failed, %{reason: "Recovery temporarily unavailable"}}
    end

    test "rejects a snapshot from a different workspace", %{
      user: user,
      project: destination_project
    } do
      source_user = user_fixture()
      source_project = project_fixture(source_user)

      {:ok, snapshot} =
        Versioning.create_project_snapshot(source_project.id, source_user.id, title: "Private")

      {:ok, _deleted_project} =
        Projects.delete_project(source_project, source_user.id)

      Phoenix.PubSub.subscribe(
        Storyarn.PubSub,
        "workspace:#{destination_project.workspace_id}:recovery"
      )

      project_count = Repo.aggregate(Projects.Project, :count)

      assert {:error, :snapshot_not_found} =
               perform_job(RecoverProjectWorker, %{
                 workspace_id: destination_project.workspace_id,
                 snapshot_id: snapshot.id,
                 project_id: source_project.id,
                 user_id: user.id
               })

      assert Repo.aggregate(Projects.Project, :count) == project_count
      assert_received {:recovery_failed, %{reason: "Snapshot not found"}}
    end
  end
end
