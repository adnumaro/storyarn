defmodule Storyarn.Workers.RecoverProjectWorkerTest do
  use Storyarn.DataCase, async: true
  use Oban.Testing, repo: Storyarn.Repo

  alias Storyarn.Versioning
  alias Storyarn.Workers.RecoverProjectWorker

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  setup do
    user = user_fixture()
    project = project_fixture(user)

    %{user: user, project: project}
  end

  describe "perform/1" do
    test "recovers project from snapshot", %{user: user, project: project} do
      _sheet = sheet_fixture(project, %{name: "Test Sheet"})
      _flow = flow_fixture(project, %{name: "Test Flow"})

      {:ok, snapshot} = Versioning.create_project_snapshot(project.id, user.id, title: "Backup")

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
  end
end
