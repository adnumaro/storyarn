defmodule Storyarn.Workers.RecoverProjectWorkerTest do
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import Ecto.Query, warn: false
  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Assets.Storage
  alias Storyarn.Projects
  alias Storyarn.Repo
  alias Storyarn.Versioning
  alias Storyarn.Versioning.ProjectSnapshot
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

      assert {:ok, size_bytes, checksum} =
               SnapshotStorage.store_raw_with_checksum(
                 snapshot.storage_key,
                 truncated_snapshot
               )

      Repo.update_all(
        from(stored_snapshot in ProjectSnapshot,
          where: stored_snapshot.id == ^snapshot.id
        ),
        set: [snapshot_size_bytes: size_bytes, checksum: checksum]
      )

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

      assert {:ok, size_bytes, checksum} =
               SnapshotStorage.store_raw_with_checksum(
                 snapshot.storage_key,
                 Map.put(snapshot_data, "format_version", 999)
               )

      Repo.update_all(
        from(stored_snapshot in ProjectSnapshot,
          where: stored_snapshot.id == ^snapshot.id
        ),
        set: [snapshot_size_bytes: size_bytes, checksum: checksum]
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

      assert {:ok, compressed_snapshot} = Storage.download(snapshot.storage_key)
      <<first_byte, rest::binary>> = compressed_snapshot
      tampered_snapshot = <<Bitwise.bxor(first_byte, 1), rest::binary>>
      assert byte_size(tampered_snapshot) == snapshot.snapshot_size_bytes

      assert {:ok, _url} =
               Storage.upload(
                 snapshot.storage_key,
                 tampered_snapshot,
                 "application/gzip"
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
        from(stored_snapshot in ProjectSnapshot,
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

      assert {:ok, size_bytes, checksum} =
               SnapshotStorage.store_raw_with_checksum(
                 snapshot.storage_key,
                 Map.delete(snapshot_data, "localization")
               )

      Repo.update_all(
        from(stored_snapshot in ProjectSnapshot,
          where: stored_snapshot.id == ^snapshot.id
        ),
        set: [snapshot_size_bytes: size_bytes, checksum: checksum]
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

    test "rejects a persisted storage key from another project before loading it", %{
      user: user,
      project: project
    } do
      other_user = user_fixture()
      other_project = project_fixture(other_user)

      {:ok, snapshot} =
        Versioning.create_project_snapshot(project.id, user.id, title: "Source")

      {:ok, other_snapshot} =
        Versioning.create_project_snapshot(
          other_project.id,
          other_user.id,
          title: "Unrelated"
        )

      Repo.update_all(
        from(stored_snapshot in ProjectSnapshot,
          where: stored_snapshot.id == ^snapshot.id
        ),
        set: [storage_key: other_snapshot.storage_key]
      )

      {:ok, _deleted_project} = Projects.delete_project(project, user.id)
      project_count = Repo.aggregate(Projects.Project, :count)

      assert {:error, :project_snapshot_storage_key_mismatch} =
               perform_job(RecoverProjectWorker, %{
                 workspace_id: project.workspace_id,
                 snapshot_id: snapshot.id,
                 project_id: project.id,
                 user_id: user.id
               })

      assert Repo.aggregate(Projects.Project, :count) == project_count

      assert {:ok, _snapshot} =
               SnapshotStorage.load_snapshot(other_snapshot.storage_key)
    end

    test "rejects a persisted compressed size mismatch before decoding", %{
      user: user,
      project: project
    } do
      {:ok, snapshot} =
        Versioning.create_project_snapshot(project.id, user.id, title: "Sized")

      expected_size = snapshot.snapshot_size_bytes + 1

      Repo.update_all(
        from(stored_snapshot in ProjectSnapshot,
          where: stored_snapshot.id == ^snapshot.id
        ),
        set: [snapshot_size_bytes: expected_size]
      )

      {:ok, _deleted_project} = Projects.delete_project(project, user.id)
      project_count = Repo.aggregate(Projects.Project, :count)

      assert {:error, {:compressed_size_mismatch, ^expected_size, actual_size}} =
               perform_job(RecoverProjectWorker, %{
                 workspace_id: project.workspace_id,
                 snapshot_id: snapshot.id,
                 project_id: project.id,
                 user_id: user.id
               })

      assert actual_size == snapshot.snapshot_size_bytes
      assert Repo.aggregate(Projects.Project, :count) == project_count
    end
  end
end
