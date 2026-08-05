defmodule Storyarn.Versioning.ProjectSnapshotBuildTest do
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Assets
  alias Storyarn.Assets.BlobStore
  alias Storyarn.Assets.Storage
  alias Storyarn.Assets.Storage.Local
  alias Storyarn.Billing.StorageReservation
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Versioning
  alias Storyarn.Versioning.ProjectSnapshot
  alias Storyarn.Versioning.ProjectSnapshotCapture
  alias Storyarn.Workers.BuildProjectSnapshotWorker

  describe "request_full_project_snapshot/3" do
    test "atomically persists an exact capture, capacity reservation, and unique job" do
      user = user_fixture()
      project = project_fixture(user)
      scope = user_scope_fixture(user)
      asset = upload_asset!(project, user, "capture bytes")
      idempotency_key = Ecto.UUID.generate()

      assert {:ok, snapshot} =
               Versioning.request_full_project_snapshot(scope, project, %{
                 idempotency_key: idempotency_key,
                 title: "Milestone"
               })

      assert snapshot.lifecycle_state == "pending"
      assert snapshot.mode == "full"
      assert snapshot.idempotency_key == idempotency_key
      assert snapshot.asset_count == 1
      assert snapshot.blob_count == 1
      assert snapshot.object_count == 3
      assert snapshot.progress_bytes == 0
      assert snapshot.progress_total_bytes == snapshot.total_size_bytes
      assert is_integer(snapshot.storage_reservation_id)
      assert is_integer(snapshot.build_job_id)

      capture = Repo.get!(ProjectSnapshotCapture, snapshot.id)
      assert capture.capture_boundary == snapshot.capture_boundary
      assert capture.capture_digest == snapshot.capture_digest
      assert byte_size(capture.project_json) == snapshot.project_size_bytes
      assert byte_size(capture.manifest_json) == snapshot.manifest_size_bytes
      assert map_size(capture.source_keys) == 1

      blob_key = protected_blob_key(project.id, asset)
      assert Map.values(capture.source_keys) == [blob_key]

      reservation = Repo.get!(StorageReservation, snapshot.storage_reservation_id)
      assert reservation.status == "active"
      assert reservation.kind == "snapshot_build"
      assert reservation.reserved_bytes == snapshot.total_size_bytes

      job = Repo.get!(Oban.Job, snapshot.build_job_id)
      assert job.queue == "snapshots"
      assert job.args == %{"snapshot_id" => snapshot.id}

      assert {:ok, replayed} =
               Versioning.request_full_project_snapshot(scope, project, %{
                 idempotency_key: idempotency_key,
                 title: "Ignored replay title"
               })

      assert replayed.id == snapshot.id

      assert Repo.aggregate(
               from(snapshot in ProjectSnapshot, where: snapshot.project_id == ^project.id),
               :count
             ) == 1

      assert Repo.aggregate(
               from(job in Oban.Job,
                 where:
                   job.worker == ^inspect(BuildProjectSnapshotWorker) and
                     fragment("?->>'snapshot_id'", job.args) == ^to_string(snapshot.id)
               ),
               :count,
               :id
             ) == 1
    end

    test "rejects linked mode instead of silently degrading" do
      user = user_fixture()
      project = project_fixture(user)

      assert {:error, :invalid_snapshot_request} =
               Versioning.request_full_project_snapshot(user_scope_fixture(user), project, %{
                 idempotency_key: Ecto.UUID.generate(),
                 mode: "linked"
               })

      assert Repo.aggregate(
               from(snapshot in ProjectSnapshot, where: snapshot.project_id == ^project.id),
               :count
             ) == 0
    end

    test "rejects callers without project management permission before capture" do
      owner = user_fixture()
      unauthorized_user = user_fixture()
      project = project_fixture(owner)

      assert {:error, :unauthorized} =
               Versioning.request_full_project_snapshot(
                 user_scope_fixture(unauthorized_user),
                 project,
                 %{idempotency_key: Ecto.UUID.generate()}
               )

      refute Repo.exists?(from(snapshot in ProjectSnapshot, where: snapshot.project_id == ^project.id))
    end

    test "database rejects mutation of immutable capture bytes" do
      user = user_fixture()
      project = project_fixture(user)
      assert {:ok, snapshot} = request_snapshot(user, project)
      capture = Repo.get!(ProjectSnapshotCapture, snapshot.id)

      assert_raise Postgrex.Error, ~r/project snapshot captures are immutable/, fn ->
        capture
        |> Ecto.Changeset.change(project_json: ~s({"tampered":true}))
        |> Repo.update!()
      end
    end

    test "database rejects mutation of snapshot capture identity" do
      user = user_fixture()
      project = project_fixture(user)
      assert {:ok, snapshot} = request_snapshot(user, project)

      assert_raise Postgrex.Error, ~r/project snapshot capture identity is immutable/, fn ->
        snapshot
        |> Ecto.Changeset.change(capture_digest: String.duplicate("f", 64))
        |> Repo.update!()
      end
    end
  end

  describe "perform_project_snapshot_build/2" do
    test "publishes only the immutable capture after current asset deletion" do
      user = user_fixture()
      project = project_fixture(user)
      asset = upload_asset!(project, user, "durable snapshot bytes")

      assert {:ok, requested} = request_snapshot(user, project)
      assert {:ok, _deleted} = Assets.delete_asset(asset)
      assert :ok = Storage.delete(asset.key)

      assert :ok = perform_requested_job(requested)

      ready = Repo.get!(ProjectSnapshot, requested.id)
      assert ready.lifecycle_state == "ready"
      assert ready.integrity_state == "verified"
      assert ready.progress_phase == "complete"
      assert ready.progress_bytes == ready.total_size_bytes
      assert ready.ready_at

      assert %StorageReservation{status: "committed", actual_bytes: actual_bytes} =
               Repo.get!(StorageReservation, ready.storage_reservation_id)

      assert actual_bytes == ready.total_size_bytes

      assert {:ok, loaded} =
               Versioning.load_snapshot_object_set(
                 ready.manifest_storage_key,
                 ready.manifest_checksum,
                 ready.manifest_size_bytes
               )

      assert [%{"filename" => filename, "blob_path" => blob_path}] = loaded.manifest["assets"]
      assert filename == asset.filename
      assert {:ok, "durable snapshot bytes"} = Storage.download(ready.object_prefix <> "/" <> blob_path)

      assert :ok = perform_requested_job(ready)
      assert Repo.get!(ProjectSnapshot, ready.id).accounting_generation == 1
    end

    test "fails closed when a protected source blob is missing" do
      user = user_fixture()
      project = project_fixture(user)
      asset = upload_asset!(project, user, "missing source")

      assert {:ok, requested} = request_snapshot(user, project)
      assert :ok = Local.delete(protected_blob_key(project.id, asset))

      job = requested_job(requested)

      assert {:discard, :source_missing} =
               Versioning.perform_project_snapshot_build(requested.id,
                 job_id: job.id,
                 attempt: 1,
                 max_attempts: 1
               )

      failed = Repo.get!(ProjectSnapshot, requested.id)
      assert failed.lifecycle_state == "failed"
      assert failed.integrity_state == "missing"
      assert failed.failure_code == "source_missing"
      assert failed.failed_at
      assert {:error, _reason} = Storage.stat(failed.manifest_storage_key)
      assert Repo.get!(StorageReservation, failed.storage_reservation_id).status == "released"
    end

    test "fails closed when protected source bytes do not match their captured digest" do
      user = user_fixture()
      project = project_fixture(user)
      asset = upload_asset!(project, user, "trusted source")

      assert {:ok, requested} = request_snapshot(user, project)
      assert {:ok, _url} = Local.upload(protected_blob_key(project.id, asset), "tampered bytes", "image/png")

      job = requested_job(requested)

      assert {:discard, :source_corrupt} =
               Versioning.perform_project_snapshot_build(requested.id,
                 job_id: job.id,
                 attempt: 1,
                 max_attempts: 1
               )

      failed = Repo.get!(ProjectSnapshot, requested.id)
      assert failed.lifecycle_state == "failed"
      assert failed.integrity_state == "corrupt"
      assert failed.failure_code == "source_corrupt"
      assert {:error, _reason} = Storage.stat(failed.manifest_storage_key)
      assert Repo.get!(StorageReservation, failed.storage_reservation_id).status == "released"
    end

    test "allocates a fresh owned namespace and reservation before retrying" do
      user = user_fixture()
      project = project_fixture(user)
      _asset = upload_asset!(project, user, "retryable source")
      assert {:ok, requested} = request_snapshot(user, project)
      job = requested_job(requested)
      original_storage_config = Application.get_env(:storyarn, :storage, [])

      Application.put_env(
        :storyarn,
        :storage,
        Keyword.put(original_storage_config, :put_if_absent_file_write, fn _path, _data ->
          {:error, :eio}
        end)
      )

      on_exit(fn -> Application.put_env(:storyarn, :storage, original_storage_config) end)

      assert {:retry, :build_failed} =
               Versioning.perform_project_snapshot_build(requested.id,
                 job_id: job.id,
                 attempt: 1,
                 max_attempts: 2
               )

      retrying = Repo.get!(ProjectSnapshot, requested.id)
      assert retrying.lifecycle_state == "pending"
      assert retrying.progress_phase == "retrying"
      assert retrying.object_prefix != requested.object_prefix
      assert retrying.storage_reservation_id != requested.storage_reservation_id
      assert Repo.get!(StorageReservation, requested.storage_reservation_id).status == "released"
      assert Repo.get!(StorageReservation, retrying.storage_reservation_id).status == "active"

      Application.put_env(:storyarn, :storage, original_storage_config)

      assert {:ok, %ProjectSnapshot{lifecycle_state: "ready"}} =
               Versioning.perform_project_snapshot_build(retrying.id,
                 job_id: job.id,
                 attempt: 2,
                 max_attempts: 2
               )

      ready = Repo.get!(ProjectSnapshot, requested.id)
      assert ready.lifecycle_state == "ready"
      assert ready.integrity_state == "verified"
      assert ready.object_prefix == retrying.object_prefix
      assert Repo.get!(StorageReservation, ready.storage_reservation_id).status == "committed"
    end

    test "releases an unstarted orphan reservation when its project is deleted before claim" do
      user = user_fixture()
      project = project_fixture(user)
      assert {:ok, requested} = request_snapshot(user, project)
      job = requested_job(requested)

      Repo.delete!(project)

      assert {:discard, :project_snapshot_not_found} =
               Versioning.perform_project_snapshot_build(requested.id,
                 job_id: job.id,
                 attempt: 1,
                 max_attempts: 1
               )

      refute Repo.get(ProjectSnapshot, requested.id)

      orphaned = Repo.get!(StorageReservation, requested.storage_reservation_id)
      assert orphaned.status == "released"
      assert orphaned.cleanup_status == "not_required"
      assert orphaned.workspace_id
      assert is_nil(orphaned.project_id)
      assert is_nil(orphaned.project_snapshot_id)
    end
  end

  describe "cancel_project_snapshot/3" do
    test "atomically cancels an unstarted build and releases its reservation" do
      user = user_fixture()
      project = project_fixture(user)
      assert {:ok, requested} = request_snapshot(user, project)

      assert {:ok, cancelled} =
               Versioning.cancel_project_snapshot(user_scope_fixture(user), project, requested.id)

      assert cancelled.lifecycle_state == "cancelled"
      assert cancelled.cancel_requested_at
      assert cancelled.cancelled_at
      assert Repo.get!(StorageReservation, cancelled.storage_reservation_id).status == "released"

      assert :ok = perform_requested_job(cancelled)
      assert Repo.get!(ProjectSnapshot, cancelled.id).lifecycle_state == "cancelled"
    end

    test "rejects callers without project management permission" do
      owner = user_fixture()
      unauthorized_user = user_fixture()
      project = project_fixture(owner)
      assert {:ok, requested} = request_snapshot(owner, project)

      assert {:error, :unauthorized} =
               Versioning.cancel_project_snapshot(
                 user_scope_fixture(unauthorized_user),
                 project,
                 requested.id
               )

      unchanged = Repo.get!(ProjectSnapshot, requested.id)
      assert unchanged.lifecycle_state == "pending"
      assert is_nil(unchanged.cancel_requested_at)
      assert Repo.get!(StorageReservation, unchanged.storage_reservation_id).status == "active"
    end

    test "rejects cancellation after final publication authorization" do
      user = user_fixture()
      project = project_fixture(user)
      assert {:ok, requested} = request_snapshot(user, project)
      now = TimeHelpers.now()

      finalizing =
        requested
        |> ProjectSnapshot.build_state_changeset(%{
          lifecycle_state: "verifying",
          progress_phase: "finalizing",
          building_started_at: now,
          verifying_started_at: now,
          state_updated_at: now
        })
        |> Repo.update!()

      assert {:error, :snapshot_finalization_in_progress} =
               Versioning.cancel_project_snapshot(user_scope_fixture(user), project, finalizing.id)

      unchanged = Repo.get!(ProjectSnapshot, finalizing.id)
      assert unchanged.progress_phase == "finalizing"
      assert is_nil(unchanged.cancel_requested_at)
      assert Repo.get!(StorageReservation, unchanged.storage_reservation_id).status == "active"
    end
  end

  defp request_snapshot(user, project) do
    Versioning.request_full_project_snapshot(user_scope_fixture(user), project, %{
      idempotency_key: Ecto.UUID.generate()
    })
  end

  defp perform_requested_job(snapshot) do
    snapshot
    |> requested_job()
    |> Map.put(:attempt, 1)
    |> BuildProjectSnapshotWorker.perform()
  end

  defp requested_job(snapshot), do: Repo.get!(Oban.Job, snapshot.build_job_id)

  defp upload_asset!(project, user, contents) do
    assert {:ok, asset} =
             Assets.upload_binary_and_create_asset(
               contents,
               %{filename: "snapshot.png", content_type: "image/png"},
               project,
               user
             )

    asset
  end

  defp protected_blob_key(project_id, asset) do
    BlobStore.blob_key(project_id, asset.blob_hash, BlobStore.ext_from_content_type(asset.content_type))
  end
end
