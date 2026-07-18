defmodule Storyarn.Workers.RecoverProjectWorkerTest do
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import Ecto.Query, warn: false
  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Projects
  alias Storyarn.Repo
  alias Storyarn.Versioning
  alias Storyarn.Versioning.RestorePolicy
  alias Storyarn.Versioning.SnapshotStorage
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

    test "rejects a coherently truncated blob whose canonical counts differ from the persisted record",
         %{
           user: user,
           project: project
         } do
      _sheet = sheet_fixture(project, %{name: "Must survive"})

      {:ok, snapshot} =
        Versioning.create_project_snapshot(project.id, user.id, title: "Trusted metadata")

      assert snapshot.entity_counts["sheets"] == 1
      assert {:ok, snapshot_data} = SnapshotStorage.load_snapshot(snapshot.storage_key)

      truncated_snapshot =
        snapshot_data
        |> Map.put("sheets", [])
        |> put_in(["tree", "sheets"], [])
        |> put_in(["entity_counts", "sheets"], 0)

      assert {:ok, _size} =
               SnapshotStorage.store_raw(snapshot.storage_key, truncated_snapshot)

      {:ok, _deleted_project} = Projects.delete_project(project, user.id)

      Phoenix.PubSub.subscribe(
        Storyarn.PubSub,
        "workspace:#{project.workspace_id}:recovery"
      )

      project_count = Repo.aggregate(Projects.Project, :count)

      assert {:error, {:persisted_project_snapshot_entity_count_mismatch, "sheets", 1, 0}} =
               perform_job(RecoverProjectWorker, %{
                 workspace_id: project.workspace_id,
                 snapshot_id: snapshot.id,
                 project_id: project.id,
                 user_id: user.id
               })

      assert Repo.aggregate(Projects.Project, :count) == project_count

      assert_received {:recovery_failed,
                       %{
                         reason: "{:persisted_project_snapshot_entity_count_mismatch, \"sheets\", 1, 0}"
                       }}
    end

    test "rejects an unsupported snapshot format before recovery", %{
      user: user,
      project: project
    } do
      {:ok, snapshot} =
        Versioning.create_project_snapshot(project.id, user.id, title: "Wrong format")

      assert {:ok, snapshot_data} = SnapshotStorage.load_snapshot(snapshot.storage_key)

      assert {:ok, _size} =
               SnapshotStorage.store_raw(
                 snapshot.storage_key,
                 Map.put(snapshot_data, "format_version", 999)
               )

      {:ok, _deleted_project} = Projects.delete_project(project, user.id)

      project_count = Repo.aggregate(Projects.Project, :count)

      assert {:error, {:unsupported_project_snapshot_format, 999}} =
               perform_job(RecoverProjectWorker, %{
                 workspace_id: project.workspace_id,
                 snapshot_id: snapshot.id,
                 project_id: project.id,
                 user_id: user.id
               })

      assert Repo.aggregate(Projects.Project, :count) == project_count
    end

    test "rejects same-cardinality blob tampering through its persisted checksum", %{
      user: user,
      project: project
    } do
      _sheet = sheet_fixture(project, %{name: "Untampered"})

      {:ok, snapshot} =
        Versioning.create_project_snapshot(project.id, user.id, title: "Cryptographically bound")

      assert {:ok, snapshot_data} =
               SnapshotStorage.load_snapshot(snapshot.storage_key)

      tampered_snapshot =
        put_in(
          snapshot_data,
          ["sheets", Access.at(0), "snapshot", "name"],
          "Tampered without changing a count"
        )

      assert {:ok, _size} =
               SnapshotStorage.store_raw(
                 snapshot.storage_key,
                 tampered_snapshot
               )

      {:ok, _deleted_project} = Projects.delete_project(project, user.id)
      project_count = Repo.aggregate(Projects.Project, :count)

      assert {:error, {:project_snapshot_checksum_mismatch, expected_checksum, actual_checksum}} =
               perform_job(RecoverProjectWorker, %{
                 workspace_id: project.workspace_id,
                 snapshot_id: snapshot.id,
                 project_id: project.id,
                 user_id: user.id
               })

      assert expected_checksum == snapshot.checksum
      refute actual_checksum == expected_checksum
      assert Repo.aggregate(Projects.Project, :count) == project_count
    end

    test "rejects snapshots without a cryptographic checksum", %{
      user: user,
      project: project
    } do
      _sheet = sheet_fixture(project, %{name: "Unbound snapshot"})

      {:ok, snapshot} =
        Versioning.create_project_snapshot(project.id, user.id, title: "Missing checksum")

      Repo.update_all(
        from(stored_snapshot in Storyarn.Versioning.ProjectSnapshot,
          where: stored_snapshot.id == ^snapshot.id
        ),
        set: [checksum: nil]
      )

      {:ok, _deleted_project} = Projects.delete_project(project, user.id)
      project_count = Repo.aggregate(Projects.Project, :count)

      assert {:error, :missing_project_snapshot_checksum} =
               perform_job(RecoverProjectWorker, %{
                 workspace_id: project.workspace_id,
                 snapshot_id: snapshot.id,
                 project_id: project.id,
                 user_id: user.id
               })

      assert Repo.aggregate(Projects.Project, :count) == project_count
    end

    test "rejects a malformed snapshot envelope before recovery", %{
      user: user,
      project: project
    } do
      {:ok, snapshot} =
        Versioning.create_project_snapshot(project.id, user.id, title: "Malformed")

      assert {:ok, snapshot_data} = SnapshotStorage.load_snapshot(snapshot.storage_key)

      assert {:ok, _size} =
               SnapshotStorage.store_raw(
                 snapshot.storage_key,
                 Map.delete(snapshot_data, "localization")
               )

      {:ok, _deleted_project} = Projects.delete_project(project, user.id)

      project_count = Repo.aggregate(Projects.Project, :count)

      assert {:error, :invalid_project_snapshot_envelope} =
               perform_job(RecoverProjectWorker, %{
                 workspace_id: project.workspace_id,
                 snapshot_id: snapshot.id,
                 project_id: project.id,
                 user_id: user.id
               })

      assert Repo.aggregate(Projects.Project, :count) == project_count
    end
  end
end
