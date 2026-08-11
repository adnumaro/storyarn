defmodule Storyarn.Versioning.ProjectSnapshotBuildTest do
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.VersioningFixtures

  alias Storyarn.Assets
  alias Storyarn.Assets.BlobStore
  alias Storyarn.Assets.Storage
  alias Storyarn.Assets.Storage.Local
  alias Storyarn.Assets.StorageCleanupRequest
  alias Storyarn.Assets.StorageCompensation
  alias Storyarn.Billing
  alias Storyarn.Billing.StorageReservation
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Versioning
  alias Storyarn.Versioning.ProjectSnapshot
  alias Storyarn.Versioning.ProjectSnapshotBuild
  alias Storyarn.Versioning.ProjectSnapshotCapture
  alias Storyarn.Versioning.SnapshotArchiveStorage
  alias Storyarn.Versioning.SnapshotObjectPublicationClaim
  alias Storyarn.Workers.BuildProjectSnapshotWorker
  alias Storyarn.Workers.RetryStorageCleanupRequestsWorker

  describe "request_full_project_snapshot/3" do
    test "normalizes inserted lifecycle time to the database clock" do
      project = project_fixture(user_fixture())
      database_before = database_clock_now()
      future = DateTime.add(database_before, 300, :second)
      snapshot = pending_project_snapshot_fixture(project, %{state_updated_at: future})

      database_after = database_clock_now()
      assert DateTime.compare(snapshot.state_updated_at, database_before) in [:eq, :gt]
      assert DateTime.compare(snapshot.state_updated_at, database_after) in [:eq, :lt]
    end

    test "atomically queues a minimal lease and materializes exact capture in the worker" do
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
      assert snapshot.format_version == 2
      assert is_nil(snapshot.asset_count)
      assert is_nil(snapshot.blob_count)
      assert is_nil(snapshot.object_count)
      assert snapshot.archive_storage_key == snapshot.object_prefix <> "/snapshot.zip"
      assert snapshot.manifest_storage_key == snapshot.object_prefix <> "/manifest.json"
      assert is_nil(snapshot.archive_size_bytes)
      assert is_nil(snapshot.project_size_bytes)
      assert is_nil(snapshot.capture_digest)
      assert is_nil(snapshot.captured_at)
      assert is_nil(snapshot.total_size_bytes)
      assert snapshot.progress_bytes == 0
      assert snapshot.progress_total_bytes == 0
      assert is_integer(snapshot.storage_reservation_id)
      assert is_integer(snapshot.build_job_id)
      refute Repo.get(ProjectSnapshotCapture, snapshot.id)

      reservation = Repo.get!(StorageReservation, snapshot.storage_reservation_id)
      assert reservation.status == "active"
      assert reservation.kind == "snapshot_build"
      assert reservation.reserved_bytes == 1

      job = Repo.get!(Oban.Job, snapshot.build_job_id)
      assert job.queue == "snapshot_archives"
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

      captured = materialize_snapshot_capture!(snapshot)
      capture = Repo.get!(ProjectSnapshotCapture, snapshot.id)

      assert captured.asset_count == 1
      assert captured.blob_count == 1
      assert captured.object_count == 2
      assert captured.archive_size_bytes > 0
      assert captured.total_size_bytes == captured.archive_size_bytes + captured.manifest_size_bytes
      assert captured.progress_total_bytes == captured.total_size_bytes
      assert capture.capture_boundary == captured.capture_boundary
      assert capture.capture_digest == captured.capture_digest
      assert byte_size(capture.project_json) == captured.project_size_bytes
      assert byte_size(capture.manifest_json) == captured.manifest_size_bytes
      assert map_size(capture.source_keys) == 1
      assert capture.object_count == 3

      assert capture.total_size_bytes ==
               capture.project_size_bytes + capture.manifest_size_bytes + capture.asset_blob_size_bytes

      blob_key = protected_blob_key(project.id, asset)
      assert Map.values(capture.source_keys) == [blob_key]

      extended = Repo.get!(StorageReservation, snapshot.storage_reservation_id)
      assert extended.status == "active"
      assert extended.reserved_bytes == captured.total_size_bytes
      assert extended.generation == reservation.generation + 2
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
      snapshot = materialize_snapshot_capture!(snapshot)
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
      snapshot = materialize_snapshot_capture!(snapshot)

      assert_raise Postgrex.Error, ~r/project snapshot capture identity is immutable/, fn ->
        snapshot
        |> Ecto.Changeset.change(capture_digest: String.duplicate("f", 64))
        |> Repo.update!()
      end
    end

    test "heartbeat is fenced and lifecycle time stays monotonic under clock skew" do
      user = user_fixture()
      project = project_fixture(user)
      assert {:ok, requested} = request_snapshot(user, project)
      requested = materialize_snapshot_capture!(requested)
      now = TimeHelpers.now()

      building =
        requested
        |> ProjectSnapshot.build_state_changeset(%{
          lifecycle_state: "building",
          progress_phase: "copying",
          building_started_at: now,
          state_updated_at: now
        })
        |> Repo.update!()

      job =
        building.build_job_id
        |> then(&Repo.get!(Oban.Job, &1))
        |> Ecto.Changeset.change(
          state: "executing",
          attempted_at: %{now | microsecond: {0, 6}}
        )
        |> Repo.update!()

      reservation = Repo.get!(StorageReservation, building.storage_reservation_id)

      reservation
      |> Ecto.Changeset.change(
        accounting_measured_at: now,
        expires_at: DateTime.add(now, 24 * 60 * 60, :second)
      )
      |> Repo.update!()

      claim =
        building.object_prefix
        |> SnapshotObjectPublicationClaim.create_changeset(
          String.duplicate("a", 64),
          Ecto.UUID.generate(),
          DateTime.add(now, 1, :second),
          reservation.id,
          reservation.lease_token
        )
        |> Repo.insert!()

      building
      |> ProjectSnapshot.build_state_changeset(%{
        publication_claim_token: claim.claim_token,
        state_updated_at: now
      })
      |> Repo.update!()

      handler_id = "snapshot-build-heartbeat-#{System.unique_integer([:positive])}"
      parent = self()

      :ok =
        :telemetry.attach(
          handler_id,
          [:storyarn, :snapshot, :build, :heartbeat],
          fn _event, measurements, metadata, pid ->
            send(pid, {:snapshot_build_heartbeat, measurements, metadata})
          end,
          parent
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      database_before = database_clock_now()
      assert :ok = Versioning.heartbeat_project_snapshot_build(building.id, job.id)
      assert_receive {:snapshot_build_heartbeat, %{count: 1}, %{outcome: :renewed, snapshot_id: snapshot_id}}
      assert snapshot_id == building.id
      database_after = database_clock_now()
      heartbeat_at = Repo.get!(ProjectSnapshot, building.id).state_updated_at
      renewed_reservation = Repo.get!(StorageReservation, reservation.id)
      renewed_claim = Repo.get!(SnapshotObjectPublicationClaim, claim.object_prefix)
      assert DateTime.compare(heartbeat_at, building.state_updated_at) in [:eq, :gt]
      assert DateTime.compare(heartbeat_at, database_before) in [:eq, :gt]
      assert DateTime.compare(heartbeat_at, database_after) in [:eq, :lt]
      assert renewed_reservation.generation == reservation.generation + 1
      assert DateTime.after?(renewed_reservation.expires_at, database_after)
      assert DateTime.after?(renewed_claim.lease_expires_at, database_after)

      claim_lease_ttl = Versioning.project_snapshot_build_lease_ttl_seconds()

      assert DateTime.diff(renewed_claim.lease_expires_at, database_before, :second) in (claim_lease_ttl - 1)..(claim_lease_ttl +
                                                                                                                  1)

      assert DateTime.diff(
               renewed_reservation.expires_at,
               renewed_reservation.accounting_measured_at,
               :second
             ) == Versioning.project_snapshot_build_lease_ttl_seconds()

      renewed_reservation
      |> Ecto.Changeset.change(
        accounting_measured_at: DateTime.add(database_after, -120, :second),
        expires_at: DateTime.add(database_after, -60, :second)
      )
      |> Repo.update!()

      expired_claim_lease = DateTime.add(database_after, -60, :second)

      renewed_claim
      |> Ecto.Changeset.change(lease_expires_at: expired_claim_lease)
      |> Repo.update!()

      assert {:error, :snapshot_build_not_active} =
               Versioning.heartbeat_project_snapshot_build(building.id, job.id)

      assert_receive {:snapshot_build_heartbeat, %{count: 1}, %{outcome: :rejected, snapshot_id: snapshot_id}}
      assert snapshot_id == building.id
      unchanged_reservation = Repo.get!(StorageReservation, reservation.id)
      expired_claim = Repo.get!(SnapshotObjectPublicationClaim, claim.object_prefix)
      assert unchanged_reservation.generation == renewed_reservation.generation
      assert DateTime.before?(unchanged_reservation.expires_at, database_clock_now())
      assert expired_claim.lease_expires_at == expired_claim_lease
      assert DateTime.before?(expired_claim.lease_expires_at, database_clock_now())

      future = DateTime.add(database_after, 300, :second)
      skew_before = database_clock_now()
      normalized = building |> ProjectSnapshot.build_state_changeset(%{state_updated_at: future}) |> Repo.update!()
      skew_after = database_clock_now()
      assert DateTime.compare(normalized.state_updated_at, skew_before) in [:eq, :gt]
      assert DateTime.compare(normalized.state_updated_at, skew_after) in [:eq, :lt]
      assert DateTime.before?(normalized.state_updated_at, future)

      assert {:ok, caught_up} =
               normalized
               |> ProjectSnapshot.build_state_changeset(%{progress_bytes: 1, state_updated_at: database_after})
               |> Repo.update()

      assert DateTime.compare(caught_up.state_updated_at, normalized.state_updated_at) in [:eq, :gt]
      assert caught_up.progress_bytes == 1

      job |> Ecto.Changeset.change(queue: "default") |> Repo.update!()

      assert {:error, :snapshot_build_not_active} =
               Versioning.heartbeat_project_snapshot_build(building.id, job.id)

      assert_receive {:snapshot_build_heartbeat, %{count: 1}, %{outcome: :rejected, snapshot_id: snapshot_id}}
      assert snapshot_id == building.id

      job |> Ecto.Changeset.change(queue: "snapshot_archives") |> Repo.update!()
      caught_up |> ProjectSnapshot.cancel_request_changeset(TimeHelpers.now()) |> Repo.update!()

      assert {:error, :snapshot_build_not_active} =
               Versioning.heartbeat_project_snapshot_build(building.id, job.id)

      assert_receive {:snapshot_build_heartbeat, %{count: 1}, %{outcome: :rejected, snapshot_id: snapshot_id}}
      assert snapshot_id == building.id
    end
  end

  describe "perform_project_snapshot_build/2" do
    test "publishes only the immutable capture after current asset deletion" do
      user = user_fixture()
      project = project_fixture(user)
      asset = upload_asset!(project, user, "durable snapshot bytes")

      assert {:ok, requested} = request_snapshot(user, project)
      requested = materialize_snapshot_capture!(requested)
      assert {:ok, _deleted} = Assets.delete_asset(asset)
      assert :ok = Storage.delete(asset.key)

      assert :ok = perform_requested_job(requested)

      ready = Repo.get!(ProjectSnapshot, requested.id)
      assert ready.lifecycle_state == "ready"
      assert ready.integrity_state == "verified"
      assert ready.format_version == 2
      assert ready.object_count == 2
      assert ready.progress_phase == "complete"
      assert ready.progress_bytes == ready.total_size_bytes
      assert ready.ready_at

      assert %StorageReservation{status: "committed", actual_bytes: actual_bytes} =
               Repo.get!(StorageReservation, ready.storage_reservation_id)

      assert actual_bytes == ready.total_size_bytes

      assert {:ok, inspected} = SnapshotArchiveStorage.inspect_ready_archive(ready)
      assert inspected.verified_objects == 2
      assert inspected.verified_bytes == ready.total_size_bytes

      assert [%{"filename" => filename, "blob_path" => blob_path}] =
               inspected.manifest["assets"]

      assert filename == asset.filename
      assert {:ok, archive} = Storage.download(ready.archive_storage_key)
      assert {:ok, sidecar} = Storage.download(ready.manifest_storage_key)
      assert {:ok, entries} = :zip.extract(archive, [:memory])
      extracted = Map.new(entries, fn {path, bytes} -> {List.to_string(path), bytes} end)
      assert extracted[blob_path] == "durable snapshot bytes"
      assert extracted["manifest.json"] == sidecar
      refute Repo.get(ProjectSnapshotCapture, ready.id)

      assert {:ok, %{objects: ready_objects, cursor: nil}} =
               Storage.list_prefix(ready.object_prefix <> "/", limit: 10)

      assert Enum.map(ready_objects, & &1.key) ==
               Enum.sort([ready.archive_storage_key, ready.manifest_storage_key])

      assert :ok = perform_requested_job(ready)
      assert Repo.get!(ProjectSnapshot, ready.id).accounting_generation == 1
    end

    test "retries the published namespace when staging cleanup has no durable owner" do
      user = user_fixture()
      project = project_fixture(user)
      assert {:ok, requested} = request_snapshot(user, project)
      original_config = Application.get_env(:storyarn, SnapshotArchiveStorage, [])

      Application.put_env(
        :storyarn,
        SnapshotArchiveStorage,
        original_config
        |> Keyword.put(:cleanup_delete_fun, fn keys -> {:error, keys} end)
        |> Keyword.put(:cleanup_persist_fun, fn _keys -> {:error, :database_unavailable} end)
      )

      on_exit(fn -> Application.put_env(:storyarn, SnapshotArchiveStorage, original_config) end)

      assert {:snooze, 30} = perform_requested_job(requested)

      recovering = Repo.get!(ProjectSnapshot, requested.id)
      reservation = Repo.get!(StorageReservation, requested.storage_reservation_id)
      claim = Repo.get!(SnapshotObjectPublicationClaim, requested.object_prefix)

      assert recovering.lifecycle_state == "verifying"
      assert recovering.object_prefix == requested.object_prefix
      assert reservation.status == "active"
      assert claim.status == "published"
      assert Repo.get!(ProjectSnapshotCapture, requested.id)
      assert {:ok, _stat} = Storage.stat(requested.archive_storage_key)
      assert {:ok, _stat} = Storage.stat(requested.manifest_storage_key)

      Application.put_env(:storyarn, SnapshotArchiveStorage, original_config)

      assert :ok = perform_requested_job(recovering)
      assert Repo.get!(ProjectSnapshot, requested.id).lifecycle_state == "ready"
      refute Repo.get(ProjectSnapshotCapture, requested.id)
    end

    test "a discarded old writer cannot resume past its current object or publish a ready snapshot" do
      user = user_fixture()
      project = project_fixture(user)
      assert {:ok, requested} = request_snapshot(user, project)
      job = requested_job(requested)
      parent = self()
      release_ref = make_ref()
      original_storage_config = Application.get_env(:storyarn, :storage, [])

      Application.put_env(
        :storyarn,
        :storage,
        Keyword.put(original_storage_config, :put_if_absent_file_write, fn path, data ->
          send(parent, {:snapshot_stage_write_paused, self(), path})

          receive do
            {:resume_snapshot_stage_write, ^release_ref} -> File.write(path, data, [:binary, :exclusive])
          after
            5_000 -> {:error, :paused_snapshot_stage_write_timeout}
          end
        end)
      )

      on_exit(fn -> Application.put_env(:storyarn, :storage, original_storage_config) end)

      build_task = Task.async(fn -> BuildProjectSnapshotWorker.perform(job) end)
      assert_receive {:snapshot_stage_write_paused, writer, _path}, 2_000

      active_reservation = Repo.get!(StorageReservation, requested.storage_reservation_id)
      active_claim = Repo.get!(SnapshotObjectPublicationClaim, requested.object_prefix)
      expired_at = DateTime.add(database_clock_now(), -1, :second)

      active_reservation
      |> Ecto.Changeset.change(
        expires_at: expired_at,
        accounting_measured_at: DateTime.add(expired_at, -1, :second)
      )
      |> Repo.update!()

      active_claim
      |> SnapshotObjectPublicationClaim.status_changeset("staging", expired_at)
      |> Repo.update!()

      set_stale_build_heartbeat_seconds(0)

      assert %{failure_count: 0, orphaned_count: 1, settled_count: 0} =
               Versioning.reconcile_stale_project_snapshot_builds()

      assert {:error, :snapshot_build_job_not_executing} =
               Versioning.validate_project_snapshot_build_fence(
                 requested.id,
                 requested.lifecycle_generation
               )

      send(writer, {:resume_snapshot_stage_write, release_ref})
      assert {:discard, :snapshot_build_job_not_executing} = Task.await(build_task, 5_000)

      refute Repo.get!(ProjectSnapshot, requested.id).lifecycle_state == "ready"
      assert Repo.get!(Oban.Job, job.id).state == "discarded"
      assert {:error, _reason} = Storage.stat(requested.manifest_storage_key)

      staging_archive_key =
        String.replace(requested.archive_storage_key, "/ready/", "/staging/", global: false)

      assert {:ok, _stat} = Storage.stat(staging_archive_key)

      released = Repo.get!(StorageReservation, requested.storage_reservation_id)
      assert released.status == "released"
      assert released.cleanup_status == "owned"
      assert "storage_cleanup_request:" <> cleanup_request_id = released.cleanup_reference

      cleanup_request = Repo.get!(StorageCleanupRequest, String.to_integer(cleanup_request_id))
      assert staging_archive_key in cleanup_request.storage_keys
      assert requested.manifest_storage_key in cleanup_request.storage_keys
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
      refute Repo.get(ProjectSnapshotCapture, failed.id)
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
      refute Repo.get(ProjectSnapshotCapture, failed.id)
    end

    test "preserves source corruption when cleanup ownership retries exhaust" do
      user = user_fixture()
      project = project_fixture(user)
      asset = upload_asset!(project, user, "trusted source")

      assert {:ok, requested} = request_snapshot(user, project)
      assert {:ok, _url} = Local.upload(protected_blob_key(project.id, asset), "tampered bytes", "image/png")

      job = requested_job(requested)
      original_snapshot_config = Application.get_env(:storyarn, SnapshotArchiveStorage, [])

      Application.put_env(
        :storyarn,
        SnapshotArchiveStorage,
        Keyword.put(original_snapshot_config, :cleanup_persist_fun, fn _keys ->
          {:error, :database_unavailable}
        end)
      )

      on_exit(fn -> Application.put_env(:storyarn, SnapshotArchiveStorage, original_snapshot_config) end)

      assert {:retry, :cleanup_unowned} =
               Versioning.perform_project_snapshot_build(requested.id,
                 job_id: job.id,
                 attempt: 1,
                 max_attempts: 2
               )

      unsettled = Repo.get!(ProjectSnapshot, requested.id)
      assert unsettled.lifecycle_state == "building"
      assert unsettled.integrity_state == "corrupt"
      assert is_nil(unsettled.failure_code)
      assert Repo.get!(StorageReservation, requested.storage_reservation_id).status == "active"

      assert {:discard, :source_corrupt} =
               Versioning.perform_project_snapshot_build(requested.id,
                 job_id: job.id,
                 attempt: 2,
                 max_attempts: 2
               )

      failed = Repo.get!(ProjectSnapshot, requested.id)
      assert failed.lifecycle_state == "failed"
      assert failed.integrity_state == "corrupt"
      assert failed.failure_code == "source_corrupt"
      assert Repo.get!(StorageReservation, requested.storage_reservation_id).status == "active"
      refute Repo.get(ProjectSnapshotCapture, failed.id)
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

    test "cancellation after release fences retry allocation without creating another reservation" do
      user = user_fixture()
      project = project_fixture(user)
      scope = user_scope_fixture(user)
      _asset = upload_asset!(project, user, "cancel retry race source")
      assert {:ok, requested} = request_snapshot(user, project)
      job = requested_job(requested)
      original_storage_config = Application.get_env(:storyarn, :storage, [])
      handler_id = "snapshot-retry-cancel-race-#{System.unique_integer([:positive])}"
      parent = self()

      Application.put_env(
        :storyarn,
        :storage,
        Keyword.put(original_storage_config, :put_if_absent_file_write, fn _path, _data ->
          {:error, :eio}
        end)
      )

      :ok =
        :telemetry.attach(
          handler_id,
          [:storyarn, :storage, :accounting, :updated],
          fn _event, _measurements, metadata, _config ->
            if metadata.action == :released and metadata.workspace_id == project.workspace_id do
              before_cancel = Repo.get!(ProjectSnapshot, requested.id)

              assert {:ok, cancellation_requested} =
                       Versioning.cancel_project_snapshot(scope, project, requested.id)

              send(
                parent,
                {:retry_cancel_won, before_cancel.lifecycle_generation, cancellation_requested.lifecycle_generation}
              )
            end
          end,
          nil
        )

      on_exit(fn ->
        :telemetry.detach(handler_id)
        Application.put_env(:storyarn, :storage, original_storage_config)
      end)

      assert {:ok, %ProjectSnapshot{lifecycle_state: "cancelled"}} =
               Versioning.perform_project_snapshot_build(requested.id,
                 job_id: job.id,
                 attempt: 1,
                 max_attempts: 2
               )

      assert_receive {:retry_cancel_won, generation_before_cancel, generation_after_cancel}
      assert generation_after_cancel == generation_before_cancel + 1

      cancelled = Repo.get!(ProjectSnapshot, requested.id)
      assert cancelled.lifecycle_state == "cancelled"
      assert cancelled.lifecycle_generation == generation_after_cancel
      assert cancelled.cancel_requested_at
      assert cancelled.cancelled_at
      refute Repo.get(ProjectSnapshotCapture, cancelled.id)

      reservations =
        Repo.all(
          from(reservation in StorageReservation,
            where:
              reservation.project_snapshot_id_snapshot == ^requested.id and
                reservation.kind == "snapshot_build"
          )
        )

      assert [%StorageReservation{id: reservation_id, status: "released"}] = reservations
      assert reservation_id == requested.storage_reservation_id
      assert cancelled.storage_reservation_id == reservation_id
    end

    test "exhausts cleanup ownership retries and leaves exact recovery authority" do
      user = user_fixture()
      project = project_fixture(user)
      _asset = upload_asset!(project, user, "ambiguous cleanup source")
      assert {:ok, requested} = request_snapshot(user, project)
      job = requested_job(requested)
      original_storage_config = Application.get_env(:storyarn, :storage, [])
      original_snapshot_config = Application.get_env(:storyarn, SnapshotArchiveStorage, [])

      Application.put_env(
        :storyarn,
        :storage,
        Keyword.put(original_storage_config, :put_if_absent_file_write, fn _path, _data ->
          {:error, :eio}
        end)
      )

      Application.put_env(
        :storyarn,
        SnapshotArchiveStorage,
        Keyword.put(original_snapshot_config, :cleanup_persist_fun, fn _keys ->
          {:error, :database_unavailable}
        end)
      )

      on_exit(fn ->
        Application.put_env(:storyarn, :storage, original_storage_config)
        Application.put_env(:storyarn, SnapshotArchiveStorage, original_snapshot_config)
      end)

      assert {:retry, :cleanup_unowned} =
               Versioning.perform_project_snapshot_build(requested.id,
                 job_id: job.id,
                 attempt: 1,
                 max_attempts: 5
               )

      still_building = Repo.get!(ProjectSnapshot, requested.id)
      reservation = Repo.get!(StorageReservation, requested.storage_reservation_id)

      assert still_building.lifecycle_state == "building"
      assert is_nil(still_building.failure_code)
      assert still_building.build_attempt == 1
      assert still_building.storage_reservation_id == requested.storage_reservation_id
      assert reservation.status == "active"
      assert reservation.storage_started_at

      assert {:discard, :cleanup_unowned} =
               Versioning.perform_project_snapshot_build(requested.id,
                 job_id: job.id,
                 attempt: 5,
                 max_attempts: 5
               )

      failed = Repo.get!(ProjectSnapshot, requested.id)
      assert failed.lifecycle_state == "failed"
      assert failed.failure_code == "cleanup_unowned"
      assert Repo.get!(StorageReservation, reservation.id).status == "active"

      assert {:ok, intent} = recover_expired_build!(failed, reservation.id)
      assert intent.reason == "expired_build"
      refute Repo.get(ProjectSnapshot, failed.id)
      assert Repo.get!(StorageReservation, reservation.id).status == "released"
    end

    test "duplicate delivery snoozes for an active writer and resumes its empty namespace after lease expiry" do
      user = user_fixture()
      project = project_fixture(user)
      assert {:ok, requested} = request_snapshot(user, project)
      requested = materialize_snapshot_capture!(requested)
      reservation = Repo.get!(StorageReservation, requested.storage_reservation_id)
      capture = Repo.get!(ProjectSnapshotCapture, requested.id)
      job = requested_job(requested)

      inventory_digest =
        SnapshotObjectPublicationClaim.inventory_digest(%{
          format_version: requested.format_version,
          mode: requested.mode,
          object_prefix: requested.object_prefix,
          archive_storage_key: requested.archive_storage_key,
          archive_size_bytes: requested.archive_size_bytes,
          manifest_storage_key: requested.manifest_storage_key,
          manifest_size_bytes: requested.manifest_size_bytes,
          manifest_checksum: requested.manifest_checksum,
          project_size_bytes: requested.project_size_bytes,
          project_checksum: requested.project_checksum,
          total_size_bytes: requested.total_size_bytes,
          accounted_size_bytes: requested.total_size_bytes,
          asset_blob_size_bytes: capture.asset_blob_size_bytes,
          accounting_version: 1,
          object_count: requested.object_count,
          asset_count: requested.asset_count,
          blob_count: requested.blob_count,
          capture_digest: requested.capture_digest
        })

      claim =
        requested.object_prefix
        |> SnapshotObjectPublicationClaim.create_changeset(
          inventory_digest,
          Ecto.UUID.generate(),
          DateTime.add(TimeHelpers.now(), 3_600, :second),
          reservation.id,
          reservation.lease_token
        )
        |> Repo.insert!()

      assert {:snooze, 30} =
               Versioning.perform_project_snapshot_build(requested.id,
                 job_id: job.id,
                 attempt: 1,
                 max_attempts: 5
               )

      building = Repo.get!(ProjectSnapshot, requested.id)
      unchanged_reservation = Repo.get!(StorageReservation, reservation.id)

      assert building.lifecycle_state == "building"
      assert is_nil(building.failure_code)
      assert unchanged_reservation.status == "active"
      assert is_nil(unchanged_reservation.storage_started_at)
      assert Repo.get!(SnapshotObjectPublicationClaim, claim.object_prefix).status == "staging"

      expired_at = DateTime.add(TimeHelpers.now(), -1, :second)

      claim
      |> SnapshotObjectPublicationClaim.status_changeset("staging", expired_at)
      |> Repo.update!()

      assert {:ok, %ProjectSnapshot{lifecycle_state: "ready"} = ready} =
               Versioning.perform_project_snapshot_build(requested.id,
                 job_id: job.id,
                 attempt: 5,
                 max_attempts: 5
               )

      assert ready.id == requested.id
      assert ready.integrity_state == "verified"
      assert ready.progress_phase == "complete"
      assert Repo.get!(StorageReservation, reservation.id).status == "committed"
      assert Repo.get!(SnapshotObjectPublicationClaim, claim.object_prefix).status == "published"
    end

    test "retry recovers a complete staging pair after its publication lease expires" do
      user = user_fixture()
      project = project_fixture(user)
      _asset = upload_asset!(project, user, "started staging crash")
      assert {:ok, requested} = request_snapshot(user, project)
      requested = materialize_snapshot_capture!(requested)
      capture = Repo.get!(ProjectSnapshotCapture, requested.id)
      reservation = Repo.get!(StorageReservation, requested.storage_reservation_id)
      job = requested_job(requested)
      prepared = prepared_archive_capture(requested, capture)
      token = List.last(String.split(requested.object_prefix, "/"))

      assert {:ok, staged} =
               SnapshotArchiveStorage.stage_prepared(
                 requested.project_id,
                 prepared,
                 token: token,
                 storage_reservation: reservation,
                 before_stage: fn staged ->
                   assert {:ok, _snapshot} =
                            requested
                            |> ProjectSnapshot.build_state_changeset(%{
                              publication_claim_token: staged.publication_claim_token,
                              state_updated_at: TimeHelpers.now()
                            })
                            |> Repo.update()

                   current_reservation = Repo.get!(StorageReservation, reservation.id)

                   Billing.mark_storage_reservation_started(
                     current_reservation.id,
                     current_reservation.lease_token,
                     current_reservation.generation,
                     staged.cleanup
                   )
                 end
               )

      claim = Repo.get!(SnapshotObjectPublicationClaim, staged.object_prefix)
      Repo.delete!(claim)

      Repo.insert!(%SnapshotObjectPublicationClaim{
        object_prefix: claim.object_prefix,
        claim_token: claim.claim_token,
        inventory_digest: claim.inventory_digest,
        storage_reservation_id_snapshot: claim.storage_reservation_id_snapshot,
        storage_reservation_lease_token: claim.storage_reservation_lease_token,
        status: "staging",
        lease_expires_at: DateTime.add(TimeHelpers.now(), -1, :second)
      })

      assert {:ok, %ProjectSnapshot{lifecycle_state: "ready"} = ready} =
               Versioning.perform_project_snapshot_build(requested.id,
                 job_id: job.id,
                 attempt: 2,
                 max_attempts: 5
               )

      assert ready.integrity_state == "verified"
      assert ready.archive_checksum == staged.archive_checksum
      assert Repo.get!(StorageReservation, reservation.id).status == "committed"
      assert Repo.get!(SnapshotObjectPublicationClaim, claim.object_prefix).status == "published"
    end

    test "a foreign build-job delivery is discarded without touching its owner's reservation" do
      user = user_fixture()
      project = project_fixture(user)
      assert {:ok, requested} = request_snapshot(user, project)

      assert {:ok, foreign_job} =
               %{snapshot_id: requested.id, delivery: Ecto.UUID.generate()}
               |> BuildProjectSnapshotWorker.new(queue: :snapshot_archives)
               |> Oban.insert()

      assert {:discard, :snapshot_build_owned_by_another_job} =
               Versioning.perform_project_snapshot_build(requested.id,
                 job_id: foreign_job.id,
                 attempt: 1,
                 max_attempts: 5
               )

      assert Repo.get!(ProjectSnapshot, requested.id).build_job_id == requested.build_job_id
      assert Repo.get!(StorageReservation, requested.storage_reservation_id).status == "active"
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
      assert :ok = Versioning.subscribe_project_snapshots(project.id)

      cancelled = cancel_snapshot!(user, project, requested)

      assert_receive {:project_snapshot_updated, snapshot_id}
      assert snapshot_id == requested.id

      assert cancelled.lifecycle_state == "cancelled"
      assert cancelled.cancel_requested_at
      assert cancelled.cancelled_at
      assert Repo.get!(StorageReservation, cancelled.storage_reservation_id).status == "released"

      assert :ok = perform_requested_job(cancelled)
      assert Repo.get!(ProjectSnapshot, cancelled.id).lifecycle_state == "cancelled"
    end

    test "cancellation exhausts active-writer retries and becomes recoverable" do
      for claim_status <- ["staging", "publishing"] do
        user = user_fixture()
        project = project_fixture(user)
        assert {:ok, requested} = request_snapshot(user, project)

        {reservation, _cleanup_scope, claim, _capture} =
          start_snapshot_storage!(project, requested, claim_status)

        cancellation_requested = cancel_snapshot!(user, project, requested)

        assert {:error, :cleanup_unowned} = perform_requested_job(cancellation_requested)
        assert Repo.get!(SnapshotObjectPublicationClaim, claim.object_prefix).status == claim_status
        assert_active_cancellation_fence(requested.id, reservation.id)

        assert {:discard, :cleanup_unowned} = perform_requested_job(cancellation_requested, 5)

        failed = Repo.get!(ProjectSnapshot, requested.id)
        assert failed.lifecycle_state == "failed"
        assert failed.failure_code == "cleanup_unowned"
        assert Repo.get!(StorageReservation, reservation.id).status == "active"
        refute Repo.get(ProjectSnapshotCapture, failed.id)

        assert {:ok, intent} = recover_expired_build!(failed, reservation.id)
        assert intent.reason == "expired_build"
        refute Repo.get(ProjectSnapshot, failed.id)
        assert Repo.get!(StorageReservation, reservation.id).status == "released"
      end
    end

    test "cancellation after storage starts reconstructs and owns the exact cleanup inventory" do
      user = user_fixture()
      project = project_fixture(user)
      assert {:ok, requested} = request_snapshot(user, project)
      {reservation, cleanup_scope, _claim, _capture} = start_snapshot_storage!(project, requested)
      requested = Repo.get!(ProjectSnapshot, requested.id)

      assert cleanup_scope.estimated_cleanup_bytes ==
               2 * (requested.archive_size_bytes + requested.manifest_size_bytes)

      cancellation_requested = cancel_snapshot!(user, project, requested)

      assert cancellation_requested.lifecycle_state == "pending"
      assert cancellation_requested.cancel_requested_at

      handler_id = "snapshot-cancel-cleanup-#{System.unique_integer([:positive])}"
      parent = self()

      :ok =
        :telemetry.attach(
          handler_id,
          [:storyarn, :assets, :storage_compensation, :fallback_persisted],
          fn event, measurements, metadata, pid -> send(pid, {event, measurements, metadata}) end,
          parent
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      assert :ok = perform_requested_job(cancellation_requested)
      refute_receive {[:storyarn, :assets, :storage_compensation, :fallback_persisted], _, _}

      cancelled = Repo.get!(ProjectSnapshot, requested.id)
      released = Repo.get!(StorageReservation, reservation.id)
      claim = Repo.get!(SnapshotObjectPublicationClaim, requested.object_prefix)

      assert cancelled.lifecycle_state == "cancelled"
      assert cancelled.cancelled_at
      assert released.status == "released"
      assert released.cleanup_status == "owned"
      assert claim.status == "poisoned"
      refute Repo.get(ProjectSnapshotCapture, cancelled.id)

      assert "storage_cleanup_request:" <> cleanup_request_id = released.cleanup_reference
      cleanup_request = Repo.get!(StorageCleanupRequest, String.to_integer(cleanup_request_id))

      assert MapSet.equal?(
               MapSet.new(cleanup_request.storage_keys),
               MapSet.new(cleanup_scope.storage_keys)
             )
    end

    test "cancellation keeps its reservation active until cleanup ownership can be persisted" do
      user = user_fixture()
      project = project_fixture(user)
      assert {:ok, requested} = request_snapshot(user, project)
      {reservation, _cleanup_scope, _claim, _capture} = start_snapshot_storage!(project, requested)

      cancellation_requested = cancel_snapshot!(user, project, requested)

      original_config = Application.get_env(:storyarn, ProjectSnapshotBuild, [])

      Application.put_env(
        :storyarn,
        ProjectSnapshotBuild,
        Keyword.put(original_config, :cancel_cleanup_persist_fun, fn _keys ->
          {:error, :database_unavailable}
        end)
      )

      on_exit(fn -> Application.put_env(:storyarn, ProjectSnapshotBuild, original_config) end)

      assert {:error, :cleanup_unowned} = perform_requested_job(cancellation_requested)

      still_cancelling = Repo.get!(ProjectSnapshot, requested.id)
      active_reservation = Repo.get!(StorageReservation, reservation.id)
      poisoned_claim = Repo.get!(SnapshotObjectPublicationClaim, requested.object_prefix)

      assert still_cancelling.lifecycle_state == "building"
      assert still_cancelling.cancel_requested_at
      assert is_nil(still_cancelling.cancelled_at)
      assert active_reservation.status == "active"
      assert poisoned_claim.status == "poisoned"

      Application.put_env(:storyarn, ProjectSnapshotBuild, original_config)

      assert :ok = perform_requested_job(still_cancelling)

      cancelled = Repo.get!(ProjectSnapshot, requested.id)
      released = Repo.get!(StorageReservation, reservation.id)

      assert cancelled.lifecycle_state == "cancelled"
      assert cancelled.cancelled_at
      assert released.status == "released"
      assert released.cleanup_status == "owned"
    end

    test "cancellation reuses an immutable cleanup receipt after release fails and the cleanup remains consumable" do
      user = user_fixture()
      project = project_fixture(user)
      assert {:ok, requested} = request_snapshot(user, project)
      {reservation, cleanup_scope, _claim, _capture} = start_snapshot_storage!(project, requested)

      cancellation_requested = cancel_snapshot!(user, project, requested)

      original_config = Application.get_env(:storyarn, ProjectSnapshotBuild, [])
      parent = self()

      persist_once = fn storage_keys ->
        assert {:ok, cleanup_request} =
                 StorageCompensation.persist_planned_cleanup_request(storage_keys)

        send(parent, {:cleanup_persisted, cleanup_request.id})
        {:ok, %{id: cleanup_request.id + 1_000_000}}
      end

      Application.put_env(
        :storyarn,
        ProjectSnapshotBuild,
        Keyword.put(original_config, :cancel_cleanup_persist_fun, persist_once)
      )

      on_exit(fn -> Application.put_env(:storyarn, ProjectSnapshotBuild, original_config) end)

      assert {:error, :cleanup_unowned} = perform_requested_job(cancellation_requested)
      assert_receive {:cleanup_persisted, cleanup_request_id}
      assert Repo.get!(StorageReservation, reservation.id).status == "active"

      Application.put_env(
        :storyarn,
        ProjectSnapshotBuild,
        Keyword.put(original_config, :cancel_cleanup_persist_fun, fn _keys ->
          flunk("an immutable ownership receipt must prevent a duplicate cleanup request")
        end)
      )

      assert :ok = perform_requested_job(Repo.get!(ProjectSnapshot, requested.id))

      released = Repo.get!(StorageReservation, reservation.id)
      assert released.status == "released"
      assert released.cleanup_reference == "storage_cleanup_request:#{cleanup_request_id}"

      assert Repo.aggregate(
               from(request in StorageCleanupRequest,
                 where: request.storage_keys == ^Enum.sort(cleanup_scope.storage_keys)
               ),
               :count,
               :id
             ) == 1

      assert :ok =
               RetryStorageCleanupRequestsWorker.perform(%Oban.Job{
                 args: %{},
                 attempt: 1,
                 max_attempts: 5
               })

      assert %StorageCleanupRequest{
               multipart_quiescence_started_at: %DateTime{},
               multipart_quiescence_not_before: %DateTime{}
             } = Repo.get!(StorageCleanupRequest, cleanup_request_id)

      now = TimeHelpers.now()

      cleanup_request_id
      |> then(&Repo.get!(StorageCleanupRequest, &1))
      |> Ecto.Changeset.change(
        multipart_quiescence_started_at: DateTime.add(now, -2, :second),
        multipart_quiescence_not_before: DateTime.add(now, -1, :second)
      )
      |> Repo.update!()

      assert :ok =
               RetryStorageCleanupRequestsWorker.perform(%Oban.Job{
                 args: %{},
                 attempt: 1,
                 max_attempts: 5
               })

      refute Repo.get(StorageCleanupRequest, cleanup_request_id)
    end

    test "terminal persistence failure leaves a reconcilable release and emits accounting only once" do
      user = user_fixture()
      project = project_fixture(user)
      assert {:ok, requested} = request_snapshot(user, project)
      {reservation, _cleanup_scope, _claim, _capture} = start_snapshot_storage!(project, requested)

      cancellation_requested = cancel_snapshot!(user, project, requested)

      original_config = Application.get_env(:storyarn, ProjectSnapshotBuild, [])
      handler_id = "snapshot-terminal-persist-#{System.unique_integer([:positive])}"
      parent = self()

      :ok = Versioning.subscribe_project_snapshots(project.id)

      :ok =
        :telemetry.attach(
          handler_id,
          [:storyarn, :storage, :accounting, :updated],
          fn event, measurements, metadata, pid -> send(pid, {event, measurements, metadata}) end,
          parent
        )

      Application.put_env(
        :storyarn,
        ProjectSnapshotBuild,
        Keyword.put(original_config, :terminal_state_persist_fun, fn _changeset ->
          {:error, :database_unavailable}
        end)
      )

      on_exit(fn ->
        :telemetry.detach(handler_id)
        Application.put_env(:storyarn, ProjectSnapshotBuild, original_config)
      end)

      assert {:error, :snapshot_build_cancel_state_persist_failed} =
               perform_requested_job(cancellation_requested)

      assert %ProjectSnapshot{lifecycle_state: "building", cancelled_at: nil} =
               Repo.get!(ProjectSnapshot, requested.id)

      assert %StorageReservation{status: "released", cleanup_status: "owned"} =
               Repo.get!(StorageReservation, reservation.id)

      assert_receive {
        [:storyarn, :storage, :accounting, :updated],
        _measurements,
        %{workspace_id: workspace_id, action: :released}
      }

      assert workspace_id == project.workspace_id
      refute_receive {:project_snapshot_updated, _snapshot_id}

      Application.put_env(:storyarn, ProjectSnapshotBuild, original_config)

      requested.build_job_id
      |> then(&Repo.get!(Oban.Job, &1))
      |> Ecto.Changeset.change(
        state: "scheduled",
        scheduled_at: %{TimeHelpers.now() | microsecond: {0, 6}}
      )
      |> Repo.update!()

      assert %{failure_count: 0, orphaned_count: 0, settled_count: 1} =
               Versioning.reconcile_stale_project_snapshot_builds()

      assert %ProjectSnapshot{lifecycle_state: "cancelled", cancelled_at: %DateTime{}} =
               Repo.get!(ProjectSnapshot, requested.id)

      assert_receive {:project_snapshot_updated, snapshot_id}
      assert snapshot_id == requested.id
      refute_receive {[:storyarn, :storage, :accounting, :updated], _, _}
    end

    test "reconciliation terminalizes a pending build released before capture persistence" do
      user = user_fixture()
      project = project_fixture(user)
      assert {:ok, requested} = request_snapshot(user, project)

      reservation = Repo.get!(StorageReservation, requested.storage_reservation_id)

      assert {:ok, %StorageReservation{status: "released"}} =
               Billing.release_storage_reservation(
                 reservation.id,
                 reservation.lease_token,
                 reservation.generation,
                 %{
                   reason: "build_failed",
                   cleanup_status: "not_required",
                   cleanup_proof: %{
                     type: "storage_not_started",
                     storage_namespace: reservation.storage_namespace
                   }
                 }
               )

      requested.build_job_id
      |> then(&Repo.get!(Oban.Job, &1))
      |> Ecto.Changeset.change(
        state: "discarded",
        discarded_at: %{TimeHelpers.now() | microsecond: {0, 6}}
      )
      |> Repo.update!()

      assert %{failure_count: 0, orphaned_count: 0, settled_count: 1} =
               Versioning.reconcile_stale_project_snapshot_builds()

      assert %ProjectSnapshot{
               lifecycle_state: "failed",
               integrity_state: "incomplete",
               progress_phase: "failed",
               failure_code: "build_failed",
               failed_at: %DateTime{}
             } = Repo.get!(ProjectSnapshot, requested.id)

      refute Repo.get(ProjectSnapshotCapture, requested.id)
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
      requested = materialize_snapshot_capture!(requested)
      now = TimeHelpers.now()

      building =
        requested
        |> ProjectSnapshot.build_state_changeset(%{
          lifecycle_state: "building",
          progress_phase: "copying",
          building_started_at: now,
          state_updated_at: now
        })
        |> Repo.update!()

      finalizing =
        building
        |> ProjectSnapshot.build_state_changeset(%{
          lifecycle_state: "verifying",
          progress_phase: "finalizing",
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

    test "redelivering an accepted cancellation remains idempotent during finalizing" do
      user = user_fixture()
      project = project_fixture(user)
      assert {:ok, requested} = request_snapshot(user, project)
      requested = materialize_snapshot_capture!(requested)
      now = TimeHelpers.now()

      building =
        requested
        |> ProjectSnapshot.build_state_changeset(%{
          lifecycle_state: "building",
          progress_phase: "copying",
          building_started_at: now,
          state_updated_at: now
        })
        |> Repo.update!()

      cancellation_requested =
        building
        |> ProjectSnapshot.cancel_request_changeset(now)
        |> Repo.update!()

      finalizing =
        cancellation_requested
        |> ProjectSnapshot.build_state_changeset(%{
          lifecycle_state: "verifying",
          progress_phase: "finalizing",
          verifying_started_at: now,
          state_updated_at: now
        })
        |> Repo.update!()

      assert {:ok, idempotent} =
               Versioning.cancel_project_snapshot(user_scope_fixture(user), project, finalizing.id)

      assert idempotent.id == finalizing.id
      assert idempotent.cancel_requested_at == finalizing.cancel_requested_at
      assert idempotent.lifecycle_generation == finalizing.lifecycle_generation
    end
  end

  defp assert_active_cancellation_fence(snapshot_id, reservation_id) do
    snapshot = Repo.get!(ProjectSnapshot, snapshot_id)
    reservation = Repo.get!(StorageReservation, reservation_id)

    assert snapshot.lifecycle_state == "building"
    assert snapshot.cancel_requested_at
    assert is_nil(snapshot.cancelled_at)
    assert reservation.status == "active"
    assert is_nil(reservation.cleanup_status)
    assert is_nil(reservation.cleanup_reference)
  end

  defp start_snapshot_storage!(_project, snapshot, claim_status \\ "poisoned") do
    snapshot = materialize_snapshot_capture!(snapshot)
    reservation = Repo.get!(StorageReservation, snapshot.storage_reservation_id)
    capture = Repo.get!(ProjectSnapshotCapture, snapshot.id)

    assert {:ok, cleanup_scope} = SnapshotArchiveStorage.cleanup_scope_from_snapshot(snapshot)

    assert {:ok, started} =
             Billing.mark_storage_reservation_started(
               reservation.id,
               reservation.lease_token,
               reservation.generation,
               cleanup_scope
             )

    claim =
      snapshot.object_prefix
      |> SnapshotObjectPublicationClaim.create_changeset(
        String.duplicate("a", 64),
        Ecto.UUID.generate(),
        DateTime.add(TimeHelpers.now(), 3_600, :second),
        started.id,
        started.lease_token
      )
      |> Repo.insert!()

    claim = transition_publication_claim!(claim, claim_status)

    {started, cleanup_scope, claim, capture}
  end

  defp request_snapshot(user, project) do
    Versioning.request_full_project_snapshot(user_scope_fixture(user), project, %{
      idempotency_key: Ecto.UUID.generate()
    })
  end

  defp materialize_snapshot_capture!(snapshot) do
    job = requested_job(snapshot)

    assert {:ok, state} = ProjectSnapshotBuild.materialize_capture(snapshot.id, job.id)
    assert state in [:captured, :already_captured]

    Repo.get!(ProjectSnapshot, snapshot.id)
  end

  defp prepared_archive_capture(snapshot, capture) do
    %{
      capture_digest: capture.capture_digest,
      project_json: capture.project_json,
      manifest_json: capture.manifest_json,
      source_keys: capture.source_keys,
      project_size_bytes: capture.project_size_bytes,
      project_checksum: snapshot.project_checksum,
      manifest_size_bytes: capture.manifest_size_bytes,
      manifest_checksum: snapshot.manifest_checksum,
      total_size_bytes: capture.total_size_bytes,
      asset_blob_size_bytes: capture.asset_blob_size_bytes,
      object_count: capture.object_count,
      asset_count: capture.asset_count,
      blob_count: capture.blob_count
    }
  end

  defp cancel_snapshot!(user, project, snapshot) do
    assert {:ok, cancelled} =
             Versioning.cancel_project_snapshot(user_scope_fixture(user), project, snapshot.id)

    cancelled
  end

  defp transition_publication_claim!(claim, "staging"), do: claim

  defp transition_publication_claim!(claim, "publishing") do
    claim
    |> SnapshotObjectPublicationClaim.status_changeset("staged")
    |> Repo.update!()
    |> SnapshotObjectPublicationClaim.status_changeset(
      "publishing",
      DateTime.add(TimeHelpers.now(), 3_600, :second)
    )
    |> Repo.update!()
  end

  defp transition_publication_claim!(claim, status) do
    claim
    |> SnapshotObjectPublicationClaim.status_changeset(status)
    |> Repo.update!()
  end

  defp perform_requested_job(snapshot, attempt \\ 1) do
    snapshot
    |> requested_job()
    |> Map.put(:attempt, attempt)
    |> BuildProjectSnapshotWorker.perform()
  end

  defp recover_expired_build!(snapshot, reservation_id) do
    now = TimeHelpers.now()
    expired_at = DateTime.add(now, -1, :second)

    quiesced_at =
      now
      |> DateTime.add(-Versioning.project_snapshot_build_recovery_quarantine_seconds() - 1, :second)
      |> Map.put(:microsecond, {0, 6})

    reservation_id
    |> then(&Repo.get!(StorageReservation, &1))
    |> Ecto.Changeset.change(
      expires_at: expired_at,
      accounting_measured_at: DateTime.add(expired_at, -1, :second)
    )
    |> Repo.update!()

    snapshot.build_job_id
    |> then(&Repo.get!(Oban.Job, &1))
    |> Ecto.Changeset.change(state: "discarded", discarded_at: quiesced_at)
    |> Repo.update!()

    assert [candidate] = Versioning.list_expired_project_snapshot_build_candidates(now)
    Versioning.delete_expired_project_snapshot_build_candidate(candidate)
  end

  defp requested_job(snapshot) do
    snapshot.build_job_id
    |> then(&Repo.get!(Oban.Job, &1))
    |> case do
      %Oban.Job{state: "executing"} = job ->
        job

      %Oban.Job{} = job ->
        job
        |> Ecto.Changeset.change(
          state: "executing",
          attempt: max(job.attempt, 1),
          attempted_at: %{TimeHelpers.now() | microsecond: {0, 6}}
        )
        |> Repo.update!()
    end
  end

  defp database_clock_now do
    %Postgrex.Result{rows: [[now]]} = Repo.query!("SELECT clock_timestamp()")
    DateTime.truncate(now, :second)
  end

  defp set_stale_build_heartbeat_seconds(seconds) do
    original = Application.fetch_env!(:storyarn, :snapshot_lifecycle)

    Application.put_env(
      :storyarn,
      :snapshot_lifecycle,
      Keyword.put(original, :stale_build_heartbeat_seconds, seconds)
    )

    on_exit(fn -> Application.put_env(:storyarn, :snapshot_lifecycle, original) end)
  end

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
