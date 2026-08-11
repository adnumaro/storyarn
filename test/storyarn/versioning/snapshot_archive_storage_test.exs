defmodule Storyarn.Versioning.SnapshotArchiveStorageTest do
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Assets
  alias Storyarn.Assets.BlobStore
  alias Storyarn.Assets.Storage
  alias Storyarn.Assets.Storage.Local
  alias Storyarn.Assets.StorageCleanupRequest
  alias Storyarn.Billing
  alias Storyarn.Billing.StorageReservation
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.SnapshotReadSwitchStorage
  alias Storyarn.Versioning
  alias Storyarn.Versioning.ProjectSnapshot
  alias Storyarn.Versioning.ProjectSnapshotBuild
  alias Storyarn.Versioning.ProjectSnapshotCapture
  alias Storyarn.Versioning.SnapshotArchiveStorage
  alias Storyarn.Versioning.SnapshotObjectPublicationClaim

  test "owns the exact paired archive namespace and validates ready keys purely" do
    project_id = 42
    token = "AAAAAAAAAAAAAAAA"
    staging = SnapshotArchiveStorage.staging_prefix(project_id, token)
    ready = SnapshotArchiveStorage.ready_prefix(project_id, token)

    assert staging == "projects/42/snapshots/archives/v2/staging/AAAAAAAAAAAAAAAA"
    assert ready == "projects/42/snapshots/archives/v2/ready/AAAAAAAAAAAAAAAA"
    assert SnapshotArchiveStorage.archive_key(ready) == ready <> "/snapshot.zip"
    assert SnapshotArchiveStorage.manifest_key(ready) == ready <> "/manifest.json"
    assert SnapshotArchiveStorage.ready_prefix_for_project?(project_id, ready)
    assert SnapshotArchiveStorage.ready_archive_key?(project_id, ready, ready <> "/snapshot.zip")
    refute SnapshotArchiveStorage.ready_archive_key?(project_id + 1, ready, ready <> "/snapshot.zip")

    assert {:ok, scope} = SnapshotArchiveStorage.cleanup_scope(project_id, ready)

    assert scope.storage_keys ==
             Enum.sort([
               staging <> "/snapshot.zip",
               staging <> "/manifest.json",
               ready <> "/snapshot.zip",
               ready <> "/manifest.json"
             ])
  end

  test "rejects malformed option lists before preparing or staging" do
    malformed_opts = [:not_a_keyword]

    assert {:error, :invalid_snapshot_archive_options} =
             SnapshotArchiveStorage.prepare(42, %{"format_version" => 2}, [], malformed_opts)

    assert {:error, :invalid_snapshot_archive_options} =
             SnapshotArchiveStorage.stage_prepared(42, %{}, malformed_opts)
  end

  test "derives an empty canonical cleanup scope only for a wholly uncaptured v2 snapshot" do
    project_id = 42
    object_prefix = SnapshotArchiveStorage.ready_prefix(project_id, "BBBBBBBBBBBBBBBB")

    assert {:ok, scope} =
             SnapshotArchiveStorage.cleanup_scope_from_snapshot(%{
               format_version: 2,
               capture_digest: nil,
               project_id: project_id,
               object_prefix: object_prefix,
               archive_size_bytes: nil,
               manifest_size_bytes: nil
             })

    assert scope.estimated_cleanup_bytes == 0
    assert length(scope.storage_keys) == 4

    assert Enum.sort(scope.storage_keys) ==
             Enum.sort([
               SnapshotArchiveStorage.archive_key(scope.staging_prefix),
               SnapshotArchiveStorage.manifest_key(scope.staging_prefix),
               SnapshotArchiveStorage.archive_key(scope.ready_prefix),
               SnapshotArchiveStorage.manifest_key(scope.ready_prefix)
             ])

    assert {:error, :invalid_snapshot_archive_cleanup_scope} =
             SnapshotArchiveStorage.cleanup_scope_from_snapshot(%{
               format_version: 2,
               capture_digest: nil,
               project_id: project_id,
               object_prefix: object_prefix,
               archive_size_bytes: 1,
               manifest_size_bytes: nil
             })
  end

  test "stages one deterministic ZIP, publishes manifest last, and reuses a published claim" do
    fixture = request_fixture(:binary.copy("archive-source-", 90_000))
    install_read_switch()
    SnapshotReadSwitchStorage.reset_counts()
    parent = self()

    SnapshotReadSwitchStorage.observe_io(fn operation, key ->
      send(parent, {:provider_io, operation, key})
    end)

    progress = fn bytes ->
      send(parent, {:progress, bytes})
      :ok
    end

    assert {:ok, staged} =
             SnapshotArchiveStorage.stage_prepared(
               fixture.project.id,
               fixture.prepared,
               token: fixture.token,
               storage_reservation: fixture.reservation,
               before_stage: before_stage_callback(),
               on_progress: progress
             )

    assert staged.object_count == 2
    assert staged.total_size_bytes == staged.archive_size_bytes + staged.manifest_size_bytes
    assert length(staged.cleanup.storage_keys) == 4
    assert SnapshotReadSwitchStorage.stream_count(fixture.source_key) == 1
    assert {:ok, _stat} = Storage.stat(staged.archive_staging_key)
    assert {:ok, _stat} = Storage.stat(staged.manifest_staging_key)
    assert {:error, :enoent} = Storage.stat(staged.archive_storage_key)
    assert {:error, :enoent} = Storage.stat(staged.manifest_storage_key)

    messages = drain_messages([])

    assert callback_during_archive_verification?(
             messages,
             staged.archive_staging_key
           )

    assert {:ok, stored} =
             SnapshotArchiveStorage.publish(
               staged,
               before_publish_callback(),
               on_progress: progress
             )

    publish_messages = drain_messages([])

    ready_mutations =
      for {:provider_io, operation, key} <- publish_messages,
          operation in [:copy_if_absent, :upload_stream, :put_if_absent],
          String.starts_with?(key, stored.object_prefix <> "/"),
          do: {operation, key}

    assert ready_mutations == [
             {:copy_if_absent, stored.archive_storage_key},
             {:copy_if_absent, stored.manifest_storage_key}
           ]

    assert List.last(ready_mutations) == {:copy_if_absent, stored.manifest_storage_key}

    assert stored.format_version == 2
    assert stored.object_count == 2
    assert stored.total_size_bytes == stored.archive_size_bytes + stored.manifest_size_bytes
    assert stored.archive_checksum == staged.archive_checksum

    assert {:ok, archive} = Storage.download(stored.archive_storage_key)
    assert {:ok, sidecar} = Storage.download(stored.manifest_storage_key)
    assert {:ok, extracted} = :zip.extract(archive, [:memory])
    extracted = Map.new(extracted, fn {name, bytes} -> {List.to_string(name), bytes} end)
    assert extracted["manifest.json"] == sidecar
    assert sidecar == fixture.prepared.manifest_json

    inspection_metadata = Map.put(stored, :project_id, fixture.project.id)
    assert {:ok, manifest} = SnapshotArchiveStorage.inspect_ready_manifest(inspection_metadata)
    assert manifest == Jason.decode!(sidecar)

    assert {:error, :enoent} = Storage.stat(staged.archive_staging_key)
    assert {:error, :enoent} = Storage.stat(staged.manifest_staging_key)

    assert {:ok, reused} =
             SnapshotArchiveStorage.stage_prepared(
               fixture.project.id,
               fixture.prepared,
               token: fixture.token,
               storage_reservation: Repo.get!(StorageReservation, fixture.reservation.id),
               before_stage: fn _staged -> flunk("published retry must not authorize staging") end,
               on_progress: progress
             )

    assert reused.archive_checksum == stored.archive_checksum

    assert :ok = Local.delete(stored.manifest_storage_key)

    assert {:error,
            {:snapshot_inspection_object_failed,
             %{
               failed_index: 1,
               object_count: 2,
               path: "manifest.json",
               reason: :enoent,
               verified_objects: 0,
               verified_bytes: 0
             }}} = SnapshotArchiveStorage.inspect_ready_manifest(inspection_metadata)

    invalid_manifest =
      manifest
      |> update_in(["payload_size_bytes"], &(&1 + 1))
      |> Jason.encode!()

    invalid_checksum =
      invalid_manifest
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    assert {:ok, _url} =
             Local.upload(stored.manifest_storage_key, invalid_manifest, "application/json")

    invalid_metadata = %{
      inspection_metadata
      | manifest_size_bytes: byte_size(invalid_manifest),
        manifest_checksum: invalid_checksum,
        total_size_bytes: stored.archive_size_bytes + byte_size(invalid_manifest)
    }

    assert {:error,
            {:snapshot_inspection_object_failed,
             %{
               failed_index: 1,
               reason: {:snapshot_manifest_validation_failed, {:snapshot_payload_size_mismatch, _actual, _declared}},
               verified_objects: 0,
               verified_bytes: 0
             }}} = SnapshotArchiveStorage.inspect_ready_manifest(invalid_metadata)

    assert {:error, {:snapshot_manifest_validation_failed, {:snapshot_payload_size_mismatch, _actual, _declared}}} =
             SnapshotArchiveStorage.inspect_ready_archive(invalid_metadata)
  end

  test "feeds storage only bounded archive chunks for a payload above five MiB" do
    fixture = request_fixture(:binary.copy("x", 6 * 1024 * 1024))
    install_read_switch()
    parent = self()

    SnapshotReadSwitchStorage.observe_io(fn operation, key ->
      send(parent, {:provider_io, operation, key})
    end)

    assert {:ok, staged} =
             SnapshotArchiveStorage.stage_prepared(
               fixture.project.id,
               fixture.prepared,
               token: fixture.token,
               storage_reservation: fixture.reservation,
               before_stage: before_stage_callback()
             )

    chunk_sizes =
      for {:provider_io, {:upload_stream_chunk, size}, key} <- drain_messages([]),
          key == staged.archive_staging_key,
          do: size

    assert length(chunk_sizes) > 5
    assert Enum.all?(chunk_sizes, &(&1 <= SnapshotArchiveStorage.upload_chunk_size()))
  end

  test "new publication claims use the heartbeat-backed build lease TTL" do
    fixture = request_fixture("short publication claim lease")
    parent = self()
    authorize = before_stage_callback()
    before_stage = TimeHelpers.now()

    assert {:ok, _staged} =
             SnapshotArchiveStorage.stage_prepared(
               fixture.project.id,
               fixture.prepared,
               token: fixture.token,
               storage_reservation: fixture.reservation,
               before_stage: fn staged ->
                 claim = Repo.get!(SnapshotObjectPublicationClaim, staged.object_prefix)
                 send(parent, {:claim_lease_expires_at, claim.lease_expires_at})
                 authorize.(staged)
               end
             )

    assert_receive {:claim_lease_expires_at, lease_expires_at}

    lease_ttl = Versioning.project_snapshot_build_lease_ttl_seconds()
    assert DateTime.diff(lease_expires_at, before_stage, :second) in (lease_ttl - 1)..(lease_ttl + 1)
  end

  test "does not take over an active complete ready pair and recovers it once expired" do
    fixture = request_fixture(:binary.copy("publication-recovery-", 100_000))
    install_read_switch()
    parent = self()

    SnapshotReadSwitchStorage.observe_io(fn operation, key ->
      send(parent, {:provider_io, operation, key})
    end)

    progress = fn bytes ->
      send(parent, {:progress, bytes})
      :ok
    end

    assert {:ok, staged} =
             SnapshotArchiveStorage.stage_prepared(
               fixture.project.id,
               fixture.prepared,
               token: fixture.token,
               storage_reservation: fixture.reservation,
               before_stage: before_stage_callback(),
               on_progress: progress
             )

    claim = Repo.get!(SnapshotObjectPublicationClaim, staged.object_prefix)

    claim
    |> SnapshotObjectPublicationClaim.status_changeset(
      "publishing",
      DateTime.utc_now() |> DateTime.add(3_600, :second) |> DateTime.truncate(:second)
    )
    |> Repo.update!()

    assert {:ok, true} =
             Storage.copy_if_absent(staged.archive_staging_key, staged.archive_storage_key)

    assert {:ok, true} =
             Storage.copy_if_absent(staged.manifest_staging_key, staged.manifest_storage_key)

    _messages_before_active_retry = drain_messages([])

    assert {:error, :snapshot_object_publication_in_progress} =
             SnapshotArchiveStorage.stage_prepared(
               fixture.project.id,
               fixture.prepared,
               token: fixture.token,
               storage_reservation: Repo.get!(StorageReservation, fixture.reservation.id),
               before_stage: fn _staged -> flunk("an active publishing claim must not authorize staging") end,
               on_progress: progress
             )

    assert drain_messages([]) == []

    claim
    |> Ecto.Changeset.change(lease_expires_at: DateTime.add(TimeHelpers.now(), -1, :second))
    |> Repo.update!()

    assert {:ok, recovered_stage} =
             SnapshotArchiveStorage.stage_prepared(
               fixture.project.id,
               fixture.prepared,
               token: fixture.token,
               storage_reservation: Repo.get!(StorageReservation, fixture.reservation.id),
               before_stage: fn _staged -> flunk("publishing recovery must not authorize staging") end,
               on_progress: progress
             )

    assert is_binary(recovered_stage.archive_checksum)
    _stage_messages = drain_messages([])

    assert {:ok, stored} =
             SnapshotArchiveStorage.publish(recovered_stage, before_publish_callback(), on_progress: progress)

    publish_messages = drain_messages([])

    assert callback_during_archive_verification?(
             publish_messages,
             recovered_stage.archive_storage_key
           )

    assert stored.archive_checksum == recovered_stage.archive_checksum
    assert Repo.get!(SnapshotObjectPublicationClaim, staged.object_prefix).status == "published"
  end

  test "takes over an expired staging claim only after verifying its complete staging pair" do
    fixture = request_fixture("staging crash")

    assert {:ok, staged} =
             SnapshotArchiveStorage.stage_prepared(
               fixture.project.id,
               fixture.prepared,
               token: fixture.token,
               storage_reservation: fixture.reservation,
               before_stage: before_stage_callback()
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
      lease_expires_at: DateTime.add(TimeHelpers.now(), 3_600, :second)
    })

    assert {:error, :snapshot_object_namespace_in_progress} =
             SnapshotArchiveStorage.stage_prepared(
               fixture.project.id,
               fixture.prepared,
               token: fixture.token,
               storage_reservation: Repo.get!(StorageReservation, fixture.reservation.id),
               before_stage: fn _staged -> flunk("an active claim must not be taken over") end
             )

    claim = Repo.get!(SnapshotObjectPublicationClaim, staged.object_prefix)

    claim
    |> Ecto.Changeset.change(lease_expires_at: DateTime.add(TimeHelpers.now(), -1, :second))
    |> Repo.update!()

    assert {:ok, recovered} =
             SnapshotArchiveStorage.stage_prepared(
               fixture.project.id,
               fixture.prepared,
               token: fixture.token,
               storage_reservation: Repo.get!(StorageReservation, fixture.reservation.id),
               before_stage: fn _staged -> flunk("staging recovery must not rewrite provider objects") end
             )

    assert recovered.archive_checksum == staged.archive_checksum

    assert %SnapshotObjectPublicationClaim{status: "staged", lease_expires_at: nil} =
             Repo.get!(SnapshotObjectPublicationClaim, staged.object_prefix)
  end

  test "poisons an expired staging claim when its same-size archive is not the canonical capture" do
    fixture = request_fixture("same-size staging corruption")

    assert {:ok, staged} =
             SnapshotArchiveStorage.stage_prepared(
               fixture.project.id,
               fixture.prepared,
               token: fixture.token,
               storage_reservation: fixture.reservation,
               before_stage: before_stage_callback()
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

    assert {:ok, archive} = Storage.download(staged.archive_staging_key)
    <<first, rest::binary>> = archive
    corrupted_archive = <<Bitwise.bxor(first, 1), rest::binary>>

    assert byte_size(corrupted_archive) == staged.archive_size_bytes

    assert {:ok, _url} =
             Local.upload(staged.archive_staging_key, corrupted_archive, "application/zip")

    assert {:error, {:snapshot_archive_failed, failure}} =
             SnapshotArchiveStorage.stage_prepared(
               fixture.project.id,
               fixture.prepared,
               token: fixture.token,
               storage_reservation: Repo.get!(StorageReservation, fixture.reservation.id),
               before_stage: fn _staged -> flunk("corrupt recovery must not rewrite provider objects") end
             )

    assert %{
             phase: :stage_recovery,
             reason: {:snapshot_archive_recovery_checksum_mismatch, :staging},
             cleanup: %{cleanup_request_id: cleanup_request_id}
           } = failure

    assert is_integer(cleanup_request_id)
    assert Repo.get!(SnapshotObjectPublicationClaim, staged.object_prefix).status == "poisoned"
    assert %StorageCleanupRequest{} = Repo.get!(StorageCleanupRequest, cleanup_request_id)
  end

  test "takes over an expired pre-write claim only after proving its namespace is empty" do
    fixture = request_fixture("pre-write staging crash")

    assert {:ok, staged} =
             SnapshotArchiveStorage.stage_prepared(
               fixture.project.id,
               fixture.prepared,
               token: fixture.token,
               storage_reservation: fixture.reservation,
               before_stage: before_stage_callback()
             )

    Enum.each(staged.cleanup.storage_keys, &Local.delete/1)

    StorageReservation
    |> Repo.get!(fixture.reservation.id)
    |> Ecto.Changeset.change(
      storage_started_at: nil,
      cleanup_inventory_digest: nil,
      cleanup_inventory_count: nil
    )
    |> Repo.update!()

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

    install_read_switch()
    parent = self()

    SnapshotReadSwitchStorage.observe_io(fn operation, key ->
      send(parent, {:provider_io, operation, key})
    end)

    assert {:ok, recovered} =
             SnapshotArchiveStorage.stage_prepared(
               fixture.project.id,
               fixture.prepared,
               token: fixture.token,
               storage_reservation: Repo.get!(StorageReservation, fixture.reservation.id),
               before_stage: before_stage_callback()
             )

    stat_keys =
      for {:provider_io, :stat, key} <- drain_messages([]),
          do: key,
          into: MapSet.new()

    assert MapSet.subset?(MapSet.new(recovered.cleanup.storage_keys), stat_keys)
    assert %StorageReservation{storage_started_at: %DateTime{}} = Repo.get!(StorageReservation, fixture.reservation.id)

    assert %SnapshotObjectPublicationClaim{status: "staged", lease_expires_at: nil} =
             Repo.get!(SnapshotObjectPublicationClaim, staged.object_prefix)
  end

  test "resumes manifest-last publication after a crash left only the ready archive" do
    fixture = request_fixture("manifest-last crash")
    install_read_switch()
    parent = self()

    SnapshotReadSwitchStorage.observe_io(fn operation, key ->
      send(parent, {:provider_io, operation, key})
    end)

    assert {:ok, staged} =
             SnapshotArchiveStorage.stage_prepared(
               fixture.project.id,
               fixture.prepared,
               token: fixture.token,
               storage_reservation: fixture.reservation,
               before_stage: before_stage_callback()
             )

    claim = Repo.get!(SnapshotObjectPublicationClaim, staged.object_prefix)

    claim
    |> SnapshotObjectPublicationClaim.status_changeset(
      "publishing",
      DateTime.add(TimeHelpers.now(), -1, :second)
    )
    |> Repo.update!()

    assert {:ok, true} =
             Storage.copy_if_absent(staged.archive_staging_key, staged.archive_storage_key)

    assert {:error, :enoent} = Storage.stat(staged.manifest_storage_key)

    assert {:ok, recovered_stage} =
             SnapshotArchiveStorage.stage_prepared(
               fixture.project.id,
               fixture.prepared,
               token: fixture.token,
               storage_reservation: Repo.get!(StorageReservation, fixture.reservation.id),
               before_stage: fn _staged -> flunk("publishing recovery must not restage") end
             )

    _messages_before_publish = drain_messages([])

    assert {:ok, stored} =
             SnapshotArchiveStorage.publish(recovered_stage, before_publish_callback())

    ready_mutations =
      for {:provider_io, :copy_if_absent, key} <- drain_messages([]),
          String.starts_with?(key, stored.object_prefix <> "/"),
          do: key

    assert ready_mutations == [stored.manifest_storage_key]
    assert {:ok, sidecar} = Storage.download(stored.manifest_storage_key)
    assert sidecar == fixture.prepared.manifest_json
    assert Repo.get!(SnapshotObjectPublicationClaim, staged.object_prefix).status == "published"
  end

  test "poisons and hands off an expired publishing claim with no exact recoverable pair" do
    fixture = request_fixture("unrecoverable publishing crash")

    assert {:ok, staged} =
             SnapshotArchiveStorage.stage_prepared(
               fixture.project.id,
               fixture.prepared,
               token: fixture.token,
               storage_reservation: fixture.reservation,
               before_stage: before_stage_callback()
             )

    claim = Repo.get!(SnapshotObjectPublicationClaim, staged.object_prefix)

    claim
    |> SnapshotObjectPublicationClaim.status_changeset(
      "publishing",
      DateTime.add(TimeHelpers.now(), -1, :second)
    )
    |> Repo.update!()

    assert :ok = Local.delete(staged.manifest_staging_key)

    assert {:error, {:snapshot_archive_failed, failure}} =
             SnapshotArchiveStorage.stage_prepared(
               fixture.project.id,
               fixture.prepared,
               token: fixture.token,
               storage_reservation: Repo.get!(StorageReservation, fixture.reservation.id),
               before_stage: fn _staged -> flunk("unrecoverable publishing must not restage") end
             )

    assert %{phase: :publish_recovery, cleanup: %{cleanup_request_id: cleanup_request_id}} = failure
    assert is_integer(cleanup_request_id)
    assert Repo.get!(SnapshotObjectPublicationClaim, staged.object_prefix).status == "poisoned"
    assert %StorageCleanupRequest{} = Repo.get!(StorageCleanupRequest, cleanup_request_id)
  end

  test "an active publishing claim is neither inspected nor taken over" do
    fixture = request_fixture(:binary.copy("truncated-ready-archive-", 80_000))

    assert {:ok, staged} =
             SnapshotArchiveStorage.stage_prepared(
               fixture.project.id,
               fixture.prepared,
               token: fixture.token,
               storage_reservation: fixture.reservation,
               before_stage: before_stage_callback()
             )

    claim = Repo.get!(SnapshotObjectPublicationClaim, staged.object_prefix)

    claim
    |> SnapshotObjectPublicationClaim.status_changeset(
      "publishing",
      DateTime.utc_now() |> DateTime.add(3_600, :second) |> DateTime.truncate(:second)
    )
    |> Repo.update!()

    assert {:ok, true} =
             Storage.copy_if_absent(staged.archive_staging_key, staged.archive_storage_key)

    assert {:ok, true} =
             Storage.copy_if_absent(staged.manifest_staging_key, staged.manifest_storage_key)

    assert {:ok, archive} = Storage.download(staged.archive_storage_key)
    truncated = binary_part(archive, 0, byte_size(archive) - 1)
    install_read_switch(%{staged.archive_storage_key => truncated})

    assert {:error, :snapshot_object_publication_in_progress} =
             SnapshotArchiveStorage.stage_prepared(
               fixture.project.id,
               fixture.prepared,
               token: fixture.token,
               storage_reservation: Repo.get!(StorageReservation, fixture.reservation.id),
               before_stage: fn _staged -> flunk("publishing recovery must not authorize staging") end
             )

    assert SnapshotReadSwitchStorage.stream_count(staged.archive_storage_key) == 0
    assert Repo.get!(SnapshotObjectPublicationClaim, staged.object_prefix).status == "publishing"
  end

  test "failure after archive upload poisons the claim and hands off all four keys" do
    fixture = request_fixture("manifest failure")
    original_storage = Application.fetch_env!(:storyarn, :storage)

    Application.put_env(
      :storyarn,
      :storage,
      Keyword.put(original_storage, :put_if_absent_file_write, fn _path, _bytes -> {:error, :eacces} end)
    )

    on_exit(fn -> Application.put_env(:storyarn, :storage, original_storage) end)

    assert {:error, {:snapshot_archive_failed, %{cleanup: cleanup, phase: :stage}}} =
             SnapshotArchiveStorage.stage_prepared(
               fixture.project.id,
               fixture.prepared,
               token: fixture.token,
               storage_reservation: fixture.reservation,
               before_stage: before_stage_callback()
             )

    assert length(cleanup.storage_keys) == 4
    assert is_integer(cleanup.cleanup_request_id)
    request = Repo.get!(StorageCleanupRequest, cleanup.cleanup_request_id)
    assert request.storage_keys == Enum.sort(cleanup.storage_keys)

    claim = Repo.get!(SnapshotObjectPublicationClaim, fixture.snapshot.object_prefix)
    assert claim.status == "poisoned"
  end

  test "conditional-copy temporary cleanup is compensated before publication failure escapes" do
    fixture = request_fixture("copy cleanup")

    assert {:ok, staged} =
             SnapshotArchiveStorage.stage_prepared(
               fixture.project.id,
               fixture.prepared,
               token: fixture.token,
               storage_reservation: fixture.reservation,
               before_stage: before_stage_callback()
             )

    original_storage = Application.fetch_env!(:storyarn, :storage)
    parent = self()

    Application.put_env(
      :storyarn,
      :storage,
      Keyword.put(original_storage, :conditional_copy_file_rm, fn _path -> {:error, :eacces} end)
    )

    Application.put_env(
      :storyarn,
      SnapshotArchiveStorage,
      compensation_delete_fun: fn targets ->
        send(parent, {:compensated, targets})

        Enum.each(targets, fn target ->
          target
          |> String.replace_prefix("__storyarn_force_delete__:", "")
          |> Local.delete()
        end)

        :ok
      end
    )

    on_exit(fn ->
      Application.put_env(:storyarn, :storage, original_storage)
      Application.delete_env(:storyarn, SnapshotArchiveStorage)
    end)

    assert {:error, {:snapshot_archive_failed, %{phase: :publish}}} =
             SnapshotArchiveStorage.publish(staged, before_publish_callback())

    assert_receive {:compensated, targets}
    assert targets == Enum.uniq(targets)
    assert Enum.any?(targets, &String.contains?(&1, ".storyarn-copy"))
    assert Enum.any?(targets, &String.ends_with?(&1, "/snapshot.zip"))
  end

  defp request_fixture(contents) do
    user = user_fixture()
    project = project_fixture(user)

    assert {:ok, asset} =
             Assets.upload_binary_and_create_asset(
               contents,
               %{filename: "snapshot.png", content_type: "image/png"},
               project,
               user
             )

    assert {:ok, snapshot} =
             Versioning.request_full_project_snapshot(user_scope_fixture(user), project, %{
               idempotency_key: Ecto.UUID.generate()
             })

    snapshot.build_job_id
    |> then(&Repo.get!(Oban.Job, &1))
    |> Ecto.Changeset.change(
      state: "executing",
      attempt: 1,
      attempted_at: %{TimeHelpers.now() | microsecond: {0, 6}}
    )
    |> Repo.update!()

    assert {:ok, :captured} = ProjectSnapshotBuild.materialize_capture(snapshot.id, snapshot.build_job_id)

    snapshot = Repo.get!(ProjectSnapshot, snapshot.id)
    capture = Repo.get!(ProjectSnapshotCapture, snapshot.id)
    reservation = Repo.get!(StorageReservation, snapshot.storage_reservation_id)
    source_key = BlobStore.blob_key(project.id, asset.blob_hash, "png")

    prepared = %{
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

    on_exit(fn ->
      Local.delete(source_key)

      Enum.each(
        [
          SnapshotArchiveStorage.staging_prefix(project.id, List.last(String.split(snapshot.object_prefix, "/"))),
          snapshot.object_prefix
        ],
        fn prefix ->
          Local.delete(SnapshotArchiveStorage.archive_key(prefix))
          Local.delete(SnapshotArchiveStorage.manifest_key(prefix))
        end
      )
    end)

    %{
      user: user,
      project: project,
      snapshot: snapshot,
      token: List.last(String.split(snapshot.object_prefix, "/")),
      capture: capture,
      reservation: reservation,
      prepared: prepared,
      source_key: source_key
    }
  end

  defp before_stage_callback do
    fn staged ->
      reservation = Repo.get!(StorageReservation, staged.storage_reservation_id)

      Billing.mark_storage_reservation_started(
        reservation.id,
        reservation.lease_token,
        reservation.generation,
        staged.cleanup
      )
    end
  end

  defp before_publish_callback do
    fn staged ->
      reservation = Repo.get!(StorageReservation, staged.storage_reservation_id)

      Billing.extend_storage_reservation(
        reservation.id,
        reservation.lease_token,
        reservation.generation,
        staged.total_size_bytes
      )
    end
  end

  defp install_read_switch(replacements \\ %{}) do
    original_storage = Application.fetch_env!(:storyarn, :storage)
    {:ok, _pid} = SnapshotReadSwitchStorage.start_link(replacements)
    Application.put_env(:storyarn, :storage, Keyword.put(original_storage, :adapter, SnapshotReadSwitchStorage))

    on_exit(fn ->
      Application.put_env(:storyarn, :storage, original_storage)
      stop_read_switch()
    end)
  end

  defp stop_read_switch do
    if Process.whereis(SnapshotReadSwitchStorage), do: Agent.stop(SnapshotReadSwitchStorage)
  catch
    :exit, _reason -> :ok
  end

  defp drain_messages(messages) do
    receive do
      message -> drain_messages([message | messages])
    after
      0 -> Enum.reverse(messages)
    end
  end

  defp callback_during_archive_verification?(messages, archive_key) do
    messages
    |> Enum.with_index()
    |> Enum.any?(fn
      {{:provider_io, :stream_chunk, ^archive_key}, index} ->
        messages |> Enum.drop(index + 1) |> Enum.any?(&match?({:progress, _bytes}, &1))

      _other ->
        false
    end)
  end
end
