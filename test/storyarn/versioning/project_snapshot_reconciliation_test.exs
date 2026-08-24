defmodule Storyarn.Versioning.ProjectSnapshotReconciliationTest do
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Assets
  alias Storyarn.Assets.Storage
  alias Storyarn.Assets.StorageCompensation
  alias Storyarn.Billing
  alias Storyarn.Billing.StorageReservation
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo
  alias Storyarn.SnapshotReadSwitchStorage
  alias Storyarn.Versioning
  alias Storyarn.Versioning.ProjectSnapshot
  alias Storyarn.Versioning.ProjectSnapshotBuild
  alias Storyarn.Versioning.ProjectSnapshotCapture
  alias Storyarn.Versioning.ProjectSnapshotReconciliationFinding
  alias Storyarn.Versioning.ProjectSnapshotReconciliationRun
  alias Storyarn.Versioning.SnapshotArchiveStorage
  alias Storyarn.Versioning.SnapshotObjectPublicationClaim
  alias Storyarn.Workers.BuildProjectSnapshotWorker
  alias Storyarn.Workers.InspectProjectSnapshotsWorker

  setup do
    original_storage = Application.fetch_env!(:storyarn, :storage)

    isolated_upload_dir =
      original_storage
      |> Keyword.fetch!(:upload_dir)
      |> Path.join("snapshot-reconciliation-#{System.unique_integer([:positive])}")

    File.mkdir_p!(isolated_upload_dir)

    Application.put_env(
      :storyarn,
      :storage,
      Keyword.put(original_storage, :upload_dir, isolated_upload_dir)
    )

    on_exit(fn ->
      Application.put_env(:storyarn, :storage, original_storage)
      File.rm_rf!(isolated_upload_dir)
    end)

    :ok
  end

  test "a paginated healthy dry-run is resumable, idempotent, and read-only" do
    {_user, _project, snapshot} = ready_snapshot!()
    reservation = Repo.get!(StorageReservation, snapshot.storage_reservation_id)
    claim = Repo.get!(SnapshotObjectPublicationClaim, snapshot.object_prefix)
    objects_before = list_all_objects("projects/")

    assert {:ok, run} = start_run()
    assert {:ok, replayed} = start_run()
    assert replayed.id == run.id

    assert {:ok, :continue, generation} =
             Versioning.advance_project_snapshot_reconciliation(run.id, run.cursor_generation)

    assert continuation_persisted?(run.id, generation)

    assert {:ok, :stale, ^generation} =
             Versioning.advance_project_snapshot_reconciliation(run.id, run.cursor_generation)

    completed = advance_until_terminal(run.id, generation)

    assert completed.status == "completed"
    assert completed.inspected_snapshot_count == 1
    assert completed.multipart_inventory_state == "unsupported"
    refute completed.physical_inventory_complete
    assert Versioning.list_project_snapshot_reconciliation_findings(run.id) == []

    assert Repo.get!(ProjectSnapshot, snapshot.id) == snapshot
    assert Repo.get!(StorageReservation, reservation.id) == reservation
    assert Repo.get!(SnapshotObjectPublicationClaim, claim.object_prefix) == claim
    assert list_all_objects("projects/") == objects_before
  end

  test "missing and same-size corrupt ready objects become immutable critical findings" do
    {_user, _project, missing_snapshot} = ready_snapshot!()
    assert :ok = Storage.delete(missing_snapshot.archive_storage_key)

    {_user, _project, corrupt_snapshot} = ready_snapshot!()
    {:ok, archive} = Storage.download(corrupt_snapshot.archive_storage_key)
    <<first, rest::binary>> = archive
    corrupt_archive = <<Bitwise.bxor(first, 1), rest::binary>>

    assert byte_size(corrupt_archive) == byte_size(archive)

    assert {:ok, _url} =
             Storage.upload(corrupt_snapshot.archive_storage_key, corrupt_archive, "application/zip")

    assert {:ok, run} = start_run()
    completed = advance_until_terminal(run.id, run.cursor_generation)
    findings = Versioning.list_project_snapshot_reconciliation_findings(run.id, limit: 500)

    assert completed.status == "completed"
    assert Enum.any?(findings, &(&1.category == "ready_object_missing" and &1.severity == "critical"))
    assert Enum.any?(findings, &(&1.category == "ready_object_corrupt" and &1.severity == "critical"))

    corrupt_finding = Enum.find(findings, &(&1.category == "ready_object_corrupt"))

    assert_raise Postgrex.Error, ~r/snapshot reconciliation findings are immutable/, fn ->
      Repo.transaction(fn ->
        corrupt_finding
        |> Ecto.Changeset.change(severity: "warning")
        |> Repo.update!()
      end)
    end

    assert_raise Postgrex.Error, ~r/snapshot reconciliation findings are immutable/, fn ->
      Repo.transaction(fn -> Repo.delete!(corrupt_finding) end)
    end
  end

  test "a v2 archive failure resumes at the manifest and reports combined damage" do
    {_user, _project, snapshot} = ready_snapshot!()
    assert {:ok, archive} = Storage.download(snapshot.archive_storage_key)
    <<first, rest::binary>> = archive
    corrupt_archive = <<Bitwise.bxor(first, 1), rest::binary>>

    assert {:ok, _url} =
             Storage.upload(snapshot.archive_storage_key, corrupt_archive, "application/zip")

    assert :ok = Storage.delete(snapshot.manifest_storage_key)

    assert {:ok, run} = start_run()
    completed = advance_until_terminal(run.id, run.cursor_generation)

    findings =
      run.id
      |> Versioning.list_project_snapshot_reconciliation_findings(limit: 500)
      |> Enum.filter(&(&1.project_snapshot_id_snapshot == snapshot.id))

    assert completed.status == "completed"
    assert completed.inspected_object_count == 1

    assert Enum.map(findings, &{&1.category, &1.storage_key}) == [
             {"ready_object_corrupt", snapshot.archive_storage_key},
             {"ready_manifest_missing", snapshot.manifest_storage_key}
           ]
  end

  test "an oversized v2 archive is reported without streaming the archive" do
    {_user, _project, snapshot} = ready_snapshot!()
    max_bytes = 128 * 1024 * 1024
    archive_size_bytes = max_bytes + 1
    total_size_bytes = archive_size_bytes + snapshot.manifest_size_bytes

    snapshot =
      snapshot
      |> Ecto.Changeset.change(
        archive_size_bytes: archive_size_bytes,
        total_size_bytes: total_size_bytes,
        accounted_size_bytes: total_size_bytes,
        progress_bytes: total_size_bytes,
        progress_total_bytes: total_size_bytes
      )
      |> Repo.update!()

    install_snapshot_read_switch_storage()
    SnapshotReadSwitchStorage.reset_counts()

    assert {:ok, run} =
             start_run(max_objects_per_step: 1, max_bytes_per_step: max_bytes)

    completed = advance_until_terminal(run.id, run.cursor_generation)
    findings = Versioning.list_project_snapshot_reconciliation_findings(run.id, limit: 500)

    assert completed.status == "completed"
    assert SnapshotReadSwitchStorage.stream_count(snapshot.archive_storage_key) == 0
    assert SnapshotReadSwitchStorage.stream_count(snapshot.manifest_storage_key) > 0

    assert Enum.any?(findings, fn finding ->
             finding.category == "ready_verification_limit_exceeded" and
               finding.error_code == "ready_verification_limit_exceeded" and
               finding.project_snapshot_id_snapshot == snapshot.id and
               finding.expected_size_bytes == max_bytes and
               finding.observed_size_bytes == archive_size_bytes
           end)
  end

  test "missing manifests are distinguished from object corruption" do
    {_user, _project, snapshot} = ready_snapshot!()
    assert :ok = Storage.delete(snapshot.manifest_storage_key)

    assert {:ok, run} = start_run()
    completed = advance_until_terminal(run.id, run.cursor_generation)

    assert completed.status == "completed"

    assert [%{category: "ready_manifest_missing", error_code: "storage_object_missing"}] =
             Versioning.list_project_snapshot_reconciliation_findings(run.id)
  end

  test "a manifest payload-size mismatch is recorded as corruption without aborting the run" do
    {_user, _project, snapshot} = ready_snapshot!()
    manifest = download_manifest!(snapshot)

    snapshot =
      replace_ready_manifest!(
        snapshot,
        Map.update!(manifest, "payload_size_bytes", &(&1 + 1))
      )

    assert {:ok, run} = start_run()
    completed = advance_until_terminal(run.id, run.cursor_generation)

    assert completed.status == "completed"

    assert [%{category: "ready_manifest_corrupt", error_code: "snapshot_payload_size_mismatch"}] =
             run.id
             |> Versioning.list_project_snapshot_reconciliation_findings(limit: 500)
             |> Enum.filter(&(&1.project_snapshot_id_snapshot == snapshot.id))
  end

  test "a dangling manifest relationship is recorded as corruption without aborting the run" do
    user = user_fixture()
    project = project_fixture(user)

    assert {:ok, _asset} =
             Assets.upload_binary_and_create_asset(
               "relationship source",
               %{filename: "relationship.png", content_type: "image/png"},
               project,
               user
             )

    {_user, _project, snapshot} = ready_snapshot!(user, project)
    manifest = download_manifest!(snapshot)
    [asset | remaining_assets] = manifest["assets"]

    corrupt_asset =
      update_in(asset, ["relationships"], fn relationships ->
        Map.put(relationships, "original", "asset-999999")
      end)

    snapshot =
      replace_ready_manifest!(
        snapshot,
        Map.put(manifest, "assets", [corrupt_asset | remaining_assets])
      )

    assert {:ok, run} = start_run()
    completed = advance_until_terminal(run.id, run.cursor_generation)

    assert completed.status == "completed"

    assert [%{category: "ready_manifest_corrupt", error_code: "dangling_asset_relationship"}] =
             run.id
             |> Versioning.list_project_snapshot_reconciliation_findings(limit: 500)
             |> Enum.filter(&(&1.project_snapshot_id_snapshot == snapshot.id))
  end

  test "exact inventory and global ownership scans report extras, unowned roots, and unsafe keys without deleting them" do
    {_user, project, snapshot} = ready_snapshot!()
    extra_key = snapshot.object_prefix <> "/unexpected.bin"
    unowned_key = SnapshotArchiveStorage.staging_prefix(project.id, String.duplicate("x", 16)) <> "/snapshot.zip"
    unsafe_key = "projects/#{project.id}/snapshots/archives/v2/ready/not-supported/snapshot.zip"

    for key <- [extra_key, unowned_key, unsafe_key] do
      assert {:ok, _url} = Storage.upload(key, "evidence", "application/octet-stream")
    end

    assert {:ok, run} = start_run()
    completed = advance_until_terminal(run.id, run.cursor_generation)
    findings = Versioning.list_project_snapshot_reconciliation_findings(run.id, limit: 500)

    assert completed.status == "completed"
    assert Enum.any?(findings, &(&1.category == "ready_inventory_mismatch"))
    assert Enum.any?(findings, &(&1.category == "ready_accounting_mismatch"))
    assert Enum.any?(findings, &(&1.category == "ambiguous_storage_object"))
    assert Enum.any?(findings, &(&1.category == "unsafe_snapshot_storage_key"))

    for key <- [extra_key, unowned_key, unsafe_key] do
      assert {:ok, "evidence"} = Storage.download(key)
    end
  end

  test "a staging object is not owned by an unstarted reservation without a publication claim" do
    user = user_fixture()
    project = project_fixture(user)

    assert {:ok, snapshot} =
             Versioning.request_full_project_snapshot(user_scope_fixture(user), project, %{
               idempotency_key: Ecto.UUID.generate()
             })

    staging_key = SnapshotArchiveStorage.archive_key(String.replace(snapshot.object_prefix, "/ready/", "/staging/"))
    assert {:ok, _url} = Storage.upload(staging_key, "unowned", "application/zip")

    assert {:ok, run} = start_run()
    completed = advance_until_terminal(run.id, run.cursor_generation)

    assert completed.status == "completed"

    assert Enum.any?(
             Versioning.list_project_snapshot_reconciliation_findings(run.id, limit: 500),
             &(&1.storage_key == staging_key and
                 &1.error_code == "snapshot_storage_object_has_no_compatible_owner")
           )
  end

  test "a staging claim and reservation are not ownership until their snapshot write is authorized" do
    user = user_fixture()
    project = project_fixture(user)

    assert {:ok, snapshot} =
             Versioning.request_full_project_snapshot(user_scope_fixture(user), project, %{
               idempotency_key: Ecto.UUID.generate()
             })

    reservation = Repo.get!(StorageReservation, snapshot.storage_reservation_id)

    snapshot.object_prefix
    |> SnapshotObjectPublicationClaim.create_changeset(
      String.duplicate("a", 64),
      Ecto.UUID.generate(),
      DateTime.add(TimeHelpers.now(), 3_600, :second),
      reservation.id,
      reservation.lease_token
    )
    |> Repo.insert!()

    staging_key = SnapshotArchiveStorage.archive_key(String.replace(snapshot.object_prefix, "/ready/", "/staging/"))
    assert {:ok, _url} = Storage.upload(staging_key, "unowned", "application/zip")

    assert {:ok, run} = start_run()
    completed = advance_until_terminal(run.id, run.cursor_generation)

    assert completed.status == "completed"

    assert Enum.any?(
             Versioning.list_project_snapshot_reconciliation_findings(run.id, limit: 500),
             &(&1.storage_key == staging_key and
                 &1.error_code == "snapshot_storage_object_has_no_compatible_owner")
           )
  end

  test "an expired reservation with a live owning build job is not called stale" do
    user = user_fixture()
    project = project_fixture(user)

    assert {:ok, snapshot} =
             Versioning.request_full_project_snapshot(user_scope_fixture(user), project, %{
               idempotency_key: Ecto.UUID.generate()
             })

    snapshot.storage_reservation_id
    |> then(&Repo.get!(StorageReservation, &1))
    |> Ecto.Changeset.change(
      expires_at: DateTime.add(TimeHelpers.now(), -1, :second),
      accounting_measured_at: DateTime.add(TimeHelpers.now(), -2, :second)
    )
    |> Repo.update!()

    assert Repo.get!(Oban.Job, snapshot.build_job_id).state == "available"
    assert {:ok, run} = start_run()
    completed = advance_until_terminal(run.id, run.cursor_generation)

    assert completed.status == "completed"

    refute Enum.any?(
             Versioning.list_project_snapshot_reconciliation_findings(run.id),
             &(&1.category == "stale_reservation")
           )
  end

  test "an expired mismatched reservation is stale even while the snapshot build job is live" do
    user = user_fixture()
    project = project_fixture(user)

    assert {:ok, snapshot} =
             Versioning.request_full_project_snapshot(user_scope_fixture(user), project, %{
               idempotency_key: Ecto.UUID.generate()
             })

    now = TimeHelpers.now()
    reservation = Repo.get!(StorageReservation, snapshot.storage_reservation_id)

    reservation
    |> Ecto.Changeset.change(
      expires_at: DateTime.add(now, -1, :second),
      accounting_measured_at: DateTime.add(now, -2, :second)
    )
    |> Repo.update!()

    snapshot
    |> Ecto.Changeset.change(storage_reservation_id: nil)
    |> Repo.update!()

    assert Repo.get!(Oban.Job, snapshot.build_job_id).state == "available"
    assert {:ok, run} = start_run()
    completed = advance_until_terminal(run.id, run.cursor_generation)

    assert completed.status == "completed"

    assert [%{category: "stale_reservation", details: %{"reason" => "snapshot_reservation_mismatch"}}] =
             Versioning.list_project_snapshot_reconciliation_findings(run.id)
  end

  test "an expired reservation whose exact build job is quiescent and discarded is reported" do
    user = user_fixture()
    project = project_fixture(user)

    assert {:ok, snapshot} =
             Versioning.request_full_project_snapshot(user_scope_fixture(user), project, %{
               idempotency_key: Ecto.UUID.generate()
             })

    now = TimeHelpers.now()
    old = %{DateTime.add(now, -86_400, :second) | microsecond: {0, 6}}

    snapshot.storage_reservation_id
    |> then(&Repo.get!(StorageReservation, &1))
    |> Ecto.Changeset.change(
      expires_at: DateTime.add(now, -1, :second),
      accounting_measured_at: DateTime.add(now, -2, :second)
    )
    |> Repo.update!()

    snapshot.build_job_id
    |> then(&Repo.get!(Oban.Job, &1))
    |> Ecto.Changeset.change(state: "discarded", discarded_at: old)
    |> Repo.update!()

    assert {:ok, run} = start_run()
    completed = advance_until_terminal(run.id, run.cursor_generation)

    assert completed.status == "completed"

    assert [%{category: "stale_reservation", details: %{"reason" => "owning_job_discarded"}}] =
             Versioning.list_project_snapshot_reconciliation_findings(run.id)
  end

  test "a build job on the wrong queue is reported as an invalid owner" do
    user = user_fixture()
    project = project_fixture(user)

    assert {:ok, snapshot} =
             Versioning.request_full_project_snapshot(user_scope_fixture(user), project, %{
               idempotency_key: Ecto.UUID.generate()
             })

    now = TimeHelpers.now()
    old = %{DateTime.add(now, -86_400, :second) | microsecond: {0, 6}}

    snapshot.storage_reservation_id
    |> then(&Repo.get!(StorageReservation, &1))
    |> Ecto.Changeset.change(
      expires_at: DateTime.add(now, -1, :second),
      accounting_measured_at: DateTime.add(now, -2, :second)
    )
    |> Repo.update!()

    snapshot.build_job_id
    |> then(&Repo.get!(Oban.Job, &1))
    |> Ecto.Changeset.change(queue: "default", state: "discarded", discarded_at: old)
    |> Repo.update!()

    assert {:ok, run} = start_run()
    completed = advance_until_terminal(run.id, run.cursor_generation)

    assert completed.status == "completed"

    assert [%{category: "stale_reservation", details: %{"reason" => "owning_job_invalid"}}] =
             Versioning.list_project_snapshot_reconciliation_findings(run.id)
  end

  test "active cleanup ownership protects an adopted staging namespace" do
    user = user_fixture()
    project = project_fixture(user)
    prefix = SnapshotArchiveStorage.staging_prefix(project.id, "ADOPTEDTEMP00001")
    storage_key = SnapshotArchiveStorage.archive_key(prefix)

    assert {:ok, _url} = Storage.upload(storage_key, "adopted", "application/json")
    assert {:ok, _request} = StorageCompensation.persist_planned_cleanup_request([storage_key])

    assert {:ok, run} = start_run()
    completed = advance_until_terminal(run.id, run.cursor_generation)

    assert completed.status == "completed"
    assert Versioning.list_project_snapshot_reconciliation_findings(run.id) == []
    assert {:ok, "adopted"} = Storage.download(storage_key)
  end

  test "exact cleanup ownership of one key does not hide an extra key under the same prefix" do
    user = user_fixture()
    project = project_fixture(user)
    prefix = SnapshotArchiveStorage.staging_prefix(project.id, "OWNEDSUBSET00001")
    owned_key = SnapshotArchiveStorage.archive_key(prefix)
    extra_key = prefix <> "/unexpected.bin"

    assert {:ok, _url} = Storage.upload(owned_key, "owned", "application/json")
    assert {:ok, _url} = Storage.upload(extra_key, "extra", "application/octet-stream")
    assert {:ok, _request} = StorageCompensation.persist_planned_cleanup_request([owned_key])

    assert {:ok, run} = start_run()
    completed = advance_until_terminal(run.id, run.cursor_generation)
    findings = Versioning.list_project_snapshot_reconciliation_findings(run.id, limit: 500)

    assert completed.status == "completed"

    assert Enum.any?(findings, fn finding ->
             finding.storage_key == extra_key and
               finding.category == "ambiguous_storage_object" and
               finding.error_code == "snapshot_storage_object_has_no_compatible_owner"
           end)

    refute Enum.any?(findings, &(&1.storage_key == owned_key))
  end

  test "an object that reappears after cleanup completion remains investigation-only" do
    user = user_fixture()
    project = project_fixture(user)
    prefix = SnapshotArchiveStorage.staging_prefix(project.id, "HISTCLEANUP00001")
    storage_key = SnapshotArchiveStorage.archive_key(prefix)

    assert {:ok, request} = StorageCompensation.persist_planned_cleanup_request([storage_key])
    Repo.delete!(request)
    assert {:ok, _url} = Storage.upload(storage_key, "reappeared", "application/json")

    assert {:ok, run} = start_run()
    completed = advance_until_terminal(run.id, run.cursor_generation)

    assert completed.status == "completed"

    assert [%{category: "ambiguous_storage_object", error_code: "snapshot_storage_object_reappeared_after_cleanup"}] =
             Versioning.list_project_snapshot_reconciliation_findings(run.id)

    assert {:ok, "reappeared"} = Storage.download(storage_key)
  end

  test "too many historical cleanup receipts fail the provider scan closed" do
    user = user_fixture()
    project = project_fixture(user)
    prefix = SnapshotArchiveStorage.staging_prefix(project.id, "MANYRECEIPTS0001")
    storage_key = SnapshotArchiveStorage.archive_key(prefix)

    for _receipt <- 1..101 do
      assert {:ok, request} = StorageCompensation.persist_planned_cleanup_request([storage_key])
      Repo.delete!(request)
    end

    assert {:ok, _url} = Storage.upload(storage_key, "historical", "application/json")
    assert {:ok, run} = start_run()
    failed = advance_until_terminal(run.id, run.cursor_generation)

    assert failed.status == "failed"
    assert failed.last_error_code == "snapshot_reconciliation_cleanup_evidence_limit_exceeded"
    refute failed.physical_inventory_complete
  end

  test "an oversized cleanup receipt fails without expanding its key inventory" do
    user = user_fixture()
    project = project_fixture(user)
    prefix = SnapshotArchiveStorage.staging_prefix(project.id, "LARGERECEIPT0001")
    storage_key = SnapshotArchiveStorage.archive_key(prefix)

    oversized_inventory =
      [
        storage_key
        | Enum.map(1..20_004, fn index ->
            suffix = index |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(12, "0")
            asset_id = "00000000-0000-4000-8000-#{suffix}"
            "projects/#{project.id}/assets/#{asset_id}/cleanup-evidence.bin"
          end)
      ]

    assert {:ok, request} = StorageCompensation.persist_planned_cleanup_request(oversized_inventory)
    assert length(request.storage_keys) == 20_005

    assert [[20_005]] =
             Repo.query!(
               "SELECT cardinality(storage_keys) FROM storage_cleanup_ownership_receipts WHERE cleanup_request_id = $1",
               [request.id]
             ).rows

    assert {:ok, _url} = Storage.upload(storage_key, "owned", "application/json")
    assert {:ok, run} = start_run()
    failed = advance_until_terminal(run.id, run.cursor_generation)

    assert failed.status == "failed"
    assert failed.last_error_code == "snapshot_reconciliation_cleanup_evidence_limit_exceeded"
    refute failed.physical_inventory_complete
  end

  test "live staging and reservation owners conflict with active cleanup ownership" do
    {_snapshot, ready_key} = in_flight_ready_namespace!("publishing")
    staging_key = String.replace(ready_key, "/ready/", "/staging/")

    {_user, project, ready_snapshot} = ready_snapshot!()

    assert {:ok, reservation} =
             Billing.reserve_storage(%{
               workspace_id: project.workspace_id,
               project_id: project.id,
               project_snapshot_id: ready_snapshot.id,
               idempotency_key: "reconciliation-conflict:#{project.id}",
               kind: "snapshot_export",
               reserved_bytes: 8
             })

    reservation_key = reservation.storage_namespace <> "/project.json"

    assert {:ok, _started} =
             Billing.mark_storage_reservation_started(
               reservation.id,
               reservation.lease_token,
               reservation.generation,
               %{temporary_prefix: reservation.storage_namespace, storage_keys: [reservation_key]}
             )

    assert {:ok, _url} = Storage.upload(staging_key, "staging", "application/json")
    assert {:ok, _url} = Storage.upload(reservation_key, "reserved", "application/json")

    assert {:ok, _request} =
             StorageCompensation.persist_planned_cleanup_request([staging_key, reservation_key])

    assert {:ok, run} = start_run()
    completed = advance_until_terminal(run.id, run.cursor_generation)
    findings = Versioning.list_project_snapshot_reconciliation_findings(run.id, limit: 500)

    assert completed.status == "completed"

    for storage_key <- [staging_key, reservation_key] do
      assert Enum.any?(findings, fn finding ->
               finding.storage_key == storage_key and
                 finding.category == "ambiguous_storage_object" and
                 finding.error_code == "snapshot_storage_object_has_conflicting_owners"
             end)
    end
  end

  test "poisoned publication claims are detected without provider objects" do
    user = user_fixture()
    project = project_fixture(user)

    assert {:ok, snapshot} =
             Versioning.request_full_project_snapshot(user_scope_fixture(user), project, %{
               idempotency_key: Ecto.UUID.generate()
             })

    reservation = Repo.get!(StorageReservation, snapshot.storage_reservation_id)
    prefix = SnapshotArchiveStorage.ready_prefix(project.id, "FAILEDCLAIM00001")

    claim =
      prefix
      |> SnapshotObjectPublicationClaim.create_changeset(
        String.duplicate("a", 64),
        Ecto.UUID.generate(),
        DateTime.add(TimeHelpers.now(), -1, :second),
        reservation.id,
        reservation.lease_token
      )
      |> Repo.insert!()

    claim
    |> SnapshotObjectPublicationClaim.status_changeset("poisoned")
    |> Repo.update!()

    assert {:ok, run} = start_run()
    completed = advance_until_terminal(run.id, run.cursor_generation)

    assert completed.status == "completed"

    assert [%{category: "failed_snapshot_finalization", error_code: "publication_claim_poisoned"}] =
             Versioning.list_project_snapshot_reconciliation_findings(run.id)
  end

  test "a published claim with the wrong snapshot claim token is reported" do
    {_user, _project, snapshot} = ready_snapshot!()
    {claim, reservation} = replace_published_claim!(snapshot, :claim_token)

    refute claim.claim_token == snapshot.publication_claim_token
    assert claim.storage_reservation_lease_token == reservation.lease_token

    assert_published_claim_ownership_mismatch!(snapshot)
  end

  test "a published claim with the wrong reservation lease token is reported" do
    {_user, _project, snapshot} = ready_snapshot!()
    {claim, reservation} = replace_published_claim!(snapshot, :reservation_lease_token)

    assert claim.claim_token == snapshot.publication_claim_token
    refute claim.storage_reservation_lease_token == reservation.lease_token

    assert_published_claim_ownership_mismatch!(snapshot)
  end

  test "a v2 poisoned claim with exact cleanup ownership is suppressed without its capture" do
    user = user_fixture()
    project = project_fixture(user)

    assert {:ok, snapshot} =
             Versioning.request_full_project_snapshot(user_scope_fixture(user), project, %{
               idempotency_key: Ecto.UUID.generate()
             })

    now = TimeHelpers.now()
    claim_token = Ecto.UUID.generate()

    snapshot.build_job_id
    |> then(&Repo.get!(Oban.Job, &1))
    |> Ecto.Changeset.change(
      state: "executing",
      attempt: 1,
      attempted_at: %{now | microsecond: {0, 6}}
    )
    |> Repo.update!()

    assert {:ok, :captured} =
             ProjectSnapshotBuild.materialize_capture(snapshot.id, snapshot.build_job_id)

    snapshot = Repo.get!(ProjectSnapshot, snapshot.id)

    snapshot =
      snapshot
      |> ProjectSnapshot.build_state_changeset(%{
        lifecycle_state: "building",
        progress_phase: "copying",
        build_attempt: 1,
        building_started_at: now,
        publication_claim_token: claim_token,
        state_updated_at: now
      })
      |> Repo.update!()

    reservation = Repo.get!(StorageReservation, snapshot.storage_reservation_id)
    capture = Repo.get!(ProjectSnapshotCapture, snapshot.id)
    assert snapshot.format_version == 2

    assert {:ok, cleanup_scope} =
             SnapshotArchiveStorage.cleanup_scope_from_snapshot(snapshot)

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
        claim_token,
        DateTime.add(TimeHelpers.now(), 3_600, :second),
        started.id,
        started.lease_token
      )
      |> Repo.insert!()
      |> SnapshotObjectPublicationClaim.status_changeset("poisoned")
      |> Repo.update!()

    assert claim.status == "poisoned"
    assert {:ok, cleanup_request} = StorageCompensation.persist_planned_cleanup_request(cleanup_scope.storage_keys)

    release_scope = Map.put(cleanup_scope, :cleanup_request_id, cleanup_request.id)

    assert {:ok, released} =
             Billing.release_storage_reservation(
               started.id,
               started.lease_token,
               started.generation,
               %{
                 reason: "snapshot_build_failed",
                 cleanup_status: "owned",
                 cleanup_request_id: cleanup_request.id,
                 cleanup_scope: release_scope
               }
             )

    assert released.status == "released"
    assert released.cleanup_status == "owned"

    snapshot
    |> ProjectSnapshot.build_state_changeset(%{
      lifecycle_state: "failed",
      integrity_state: "incomplete",
      progress_phase: "failed",
      failure_code: "build_failed",
      failure_message: "The snapshot could not be created.",
      failed_at: now,
      state_updated_at: now
    })
    |> Repo.update!()

    Repo.delete!(capture)
    refute Repo.get(ProjectSnapshotCapture, snapshot.id)

    assert {:ok, run} = start_run()
    completed = advance_until_terminal(run.id, run.cursor_generation)

    assert completed.status == "completed"

    refute Enum.any?(
             Versioning.list_project_snapshot_reconciliation_findings(run.id, limit: 500),
             &(&1.category == "failed_snapshot_finalization" and
                 &1.project_snapshot_id_snapshot == snapshot.id)
           )
  end

  test "a ready snapshot accounting change during inspection fails closed" do
    {_user, _project, snapshot} = ready_snapshot!()
    assert {:ok, run} = start_run()

    active = advance_until(run.id, run.cursor_generation, &(&1.active_snapshot_id == snapshot.id))

    assert {:ok, remeasured} =
             Versioning.remeasure_project_snapshot_object_set(
               snapshot.id,
               snapshot.accounting_generation,
               %{accounting_measured_at: TimeHelpers.now()}
             )

    assert remeasured.accounting_generation == snapshot.accounting_generation + 1

    failed = advance_until_terminal(run.id, active.cursor_generation)

    assert failed.status == "failed"
    assert failed.last_error_code == "snapshot_reconciliation_ready_candidate_changed"
    refute failed.physical_inventory_complete
  end

  test "coherently publishing ready objects are not reported as unowned" do
    {_publishing_snapshot, publishing_key} = in_flight_ready_namespace!("publishing")
    {_published_snapshot, published_key} = in_flight_ready_namespace!("published")
    staging_key = String.replace(publishing_key, "/ready/", "/staging/")
    assert {:ok, _url} = Storage.upload(staging_key, "publishing", "application/json")

    assert {:ok, run} = start_run()
    completed = advance_until_terminal(run.id, run.cursor_generation)
    findings = Versioning.list_project_snapshot_reconciliation_findings(run.id, limit: 500)

    assert completed.status == "completed"
    refute Enum.any?(findings, &(&1.storage_key in [publishing_key, published_key, staging_key]))
  end

  test "the publication-claim sequence excludes claims inserted after the run boundary" do
    user = user_fixture()
    project = project_fixture(user)

    assert {:ok, before_snapshot} =
             Versioning.request_full_project_snapshot(user_scope_fixture(user), project, %{
               idempotency_key: Ecto.UUID.generate()
             })

    before_claim = poisoned_claim!(before_snapshot)
    assert is_integer(before_claim.reconciliation_sequence)

    assert_raise Postgrex.Error, ~r/identity column defined as GENERATED ALWAYS/, fn ->
      Repo.transaction(fn ->
        before_claim
        |> Ecto.Changeset.change(reconciliation_sequence: before_claim.reconciliation_sequence + 100)
        |> Repo.update!()
      end)
    end

    assert_raise Postgrex.Error, ~r/reconciliation sequence is immutable/, fn ->
      Repo.transaction(fn ->
        Repo.query!(
          "UPDATE snapshot_object_publication_claims SET reconciliation_sequence = DEFAULT WHERE object_prefix = $1",
          [before_claim.object_prefix]
        )
      end)
    end

    assert {:ok, run} = start_run()
    assert run.claim_sequence_high_watermark == before_claim.reconciliation_sequence

    after_project = project_fixture(user)

    assert {:ok, after_snapshot} =
             Versioning.request_full_project_snapshot(user_scope_fixture(user), after_project, %{
               idempotency_key: Ecto.UUID.generate()
             })

    after_claim = poisoned_claim!(after_snapshot)
    assert after_claim.reconciliation_sequence > run.claim_sequence_high_watermark

    completed = advance_until_terminal(run.id, run.cursor_generation)
    findings = Versioning.list_project_snapshot_reconciliation_findings(run.id, limit: 500)

    assert completed.status == "completed"
    assert Enum.any?(findings, &(&1.object_prefix == before_claim.object_prefix))
    refute Enum.any?(findings, &(&1.object_prefix == after_claim.object_prefix))
  end

  test "a busy source-table boundary fails closed instead of capturing a partial identity view" do
    {lock_holder, lock_holder_pid} = hold_claim_writer_lock()

    try do
      assert {:error, :snapshot_reconciliation_boundary_busy} = start_run_once([])
      Process.send_after(lock_holder_pid, :release_claim_writer, 50)
      assert {:ok, _run} = start_run()
    after
      send(lock_holder_pid, :release_claim_writer)
      assert {:ok, _result} = Task.await(lock_holder, 2_000)
    end
  end

  test "database phases retain their bounded page size after the finding budget is full" do
    {_user, _project, damaged_snapshot} = ready_snapshot!()
    assert :ok = Storage.delete(damaged_snapshot.manifest_storage_key)

    for _index <- 1..3, do: ready_snapshot!()

    assert {:ok, run} =
             start_run(max_objects_per_step: 10, max_findings: 1)

    publication_run =
      advance_until(
        run.id,
        run.cursor_generation,
        &(&1.phase == "publication_claims")
      )

    assert publication_run.finding_count == 1

    assert {:ok, :continue, next_generation} =
             Versioning.advance_project_snapshot_reconciliation(
               publication_run.id,
               publication_run.cursor_generation
             )

    after_claims = Versioning.get_project_snapshot_reconciliation_run(run.id)
    assert after_claims.cursor_generation == next_generation
    assert after_claims.phase == "cleanup_intents"
    assert after_claims.claim_after_sequence == after_claims.claim_sequence_high_watermark
  end

  test "a finding beyond the configured budget fails without discarding prior evidence" do
    {_user, _project, first_snapshot} = ready_snapshot!()
    {_user, _project, second_snapshot} = ready_snapshot!()
    assert :ok = Storage.delete(first_snapshot.manifest_storage_key)
    assert :ok = Storage.delete(second_snapshot.manifest_storage_key)

    assert {:ok, run} = start_run(max_objects_per_step: 10, max_findings: 1)
    failed = advance_until_terminal(run.id, run.cursor_generation)

    assert failed.status == "failed"
    assert failed.last_error_code == "snapshot_reconciliation_finding_limit_exceeded"
    assert failed.finding_count == 1

    assert [finding] = Versioning.list_project_snapshot_reconciliation_findings(run.id)
    assert finding.project_snapshot_id_snapshot == first_snapshot.id
    assert finding.category == "ready_manifest_missing"
  end

  test "the exact ready inventory cursor is durable between bounded pages" do
    {_user, _project, _snapshot} = ready_snapshot!()
    assert {:ok, run} = start_run()

    inventory_run = advance_until(run.id, run.cursor_generation, &is_binary(&1.active_inventory_cursor))

    assert inventory_run.active_inventory_digest =~ ~r/\A[0-9a-f]{64}\z/
    assert inventory_run.active_inventory_object_count == 1
    assert inventory_run.inspected_snapshot_count == 0

    completed = advance_until_terminal(run.id, inventory_run.cursor_generation)
    assert completed.status == "completed"
  end

  test "ready inventory distinguishes provider failures from local page validation" do
    {_user, _project, snapshot} = ready_snapshot!()
    original_storage = Application.fetch_env!(:storyarn, :storage)

    Application.put_env(
      :storyarn,
      :storage,
      Keyword.put(original_storage, :adapter, Storyarn.SnapshotResetStorage)
    )

    :ok = Storyarn.SnapshotResetStorage.put_objects(%{})

    assert {:ok, run} = start_run(max_objects_per_step: 2, provider_page_size: 2)

    inventory_run =
      advance_until(
        run.id,
        run.cursor_generation,
        &(is_binary(&1.active_inventory_digest) and is_nil(&1.active_inventory_cursor))
      )

    prefix = snapshot.object_prefix <> "/"

    :ok =
      Storyarn.SnapshotResetStorage.put_list_prefix_metadata_response(
        {:ok,
         %{
           objects: [%{key: prefix <> "z", size: 1}, %{key: prefix <> "a", size: 1}],
           cursor: nil
         }}
      )

    assert {:error, :invalid_snapshot_reconciliation_provider_page} =
             Versioning.advance_project_snapshot_reconciliation(run.id, inventory_run.cursor_generation)

    unchanged = Versioning.get_project_snapshot_reconciliation_run(run.id)
    assert unchanged.status == "running"
    assert unchanged.cursor_generation == inventory_run.cursor_generation

    :ok =
      Storyarn.SnapshotResetStorage.put_list_prefix_metadata_response({:error, :provider_timeout})

    assert {:error, {:snapshot_reconciliation_provider_list_failed, :provider_timeout}} =
             Versioning.advance_project_snapshot_reconciliation(run.id, inventory_run.cursor_generation)
  end

  test "provider inventory limits fail closed instead of claiming completion" do
    {_user, _project, _snapshot} = ready_snapshot!()

    assert {:ok, run} =
             start_run(max_provider_objects: 1, provider_page_size: 1)

    failed = advance_until_terminal(run.id, run.cursor_generation)

    assert failed.status == "failed"
    assert failed.last_error_code == "snapshot_reconciliation_provider_inventory_limit_exceeded"
    refute failed.physical_inventory_complete
  end

  test "provider pagination rejects a cursor cycle caused by a key inserted before the cursor" do
    original_storage = Application.fetch_env!(:storyarn, :storage)
    Application.put_env(:storyarn, :storage, Keyword.put(original_storage, :adapter, Storyarn.SnapshotResetStorage))
    on_exit(fn -> Application.put_env(:storyarn, :storage, original_storage) end)

    Storyarn.SnapshotResetStorage.put_objects(%{
      "projects/1/unrelated-b" => 1,
      "projects/1/unrelated-c" => 1
    })

    Storyarn.SnapshotResetStorage.insert_before_list(2, %{"projects/1/unrelated-a" => 1})

    assert {:ok, run} = start_run(provider_page_size: 1)

    provider_run =
      advance_until(
        run.id,
        run.cursor_generation,
        &(&1.phase == "provider_objects" and is_binary(&1.provider_cursor))
      )

    assert {:error, :invalid_snapshot_reconciliation_provider_page} =
             Versioning.advance_project_snapshot_reconciliation(run.id, provider_run.cursor_generation)

    still_running = Versioning.get_project_snapshot_reconciliation_run(run.id)
    assert still_running.status == "running"
    assert still_running.cursor_generation == provider_run.cursor_generation
  end

  test "unsafe provider pages skip empty ownership reads and batch their findings" do
    original_storage = Application.fetch_env!(:storyarn, :storage)
    Application.put_env(:storyarn, :storage, Keyword.put(original_storage, :adapter, Storyarn.SnapshotResetStorage))

    :ok =
      Storyarn.SnapshotResetStorage.put_objects(%{
        "projects/1/snapshots/archives/v2/ready//rogue-a" => 1,
        "projects/1/snapshots/archives/v2/ready//rogue-b" => 1
      })

    assert {:ok, run} = start_run(max_objects_per_step: 10, provider_page_size: 10)

    provider_run =
      advance_until(
        run.id,
        run.cursor_generation,
        &(&1.phase == "provider_objects")
      )

    {result, queries} =
      capture_repo_queries(fn ->
        Versioning.advance_project_snapshot_reconciliation(run.id, provider_run.cursor_generation)
      end)

    assert {:ok, :completed} = result
    assert Versioning.get_project_snapshot_reconciliation_run(run.id).finding_count == 2

    assert 1 ==
             Enum.count(
               queries,
               &String.contains?(&1, ~s(INSERT INTO "project_snapshot_reconciliation_findings"))
             )

    refute Enum.any?(queries, &String.contains?(&1, ~s(FROM "projects")))
    refute Enum.any?(queries, &String.contains?(&1, ~s(FROM "workspace_storage_reservations")))
  end

  test "provider scan records NUL-bearing reserved keys with binary checkpoints and safe evidence" do
    original_storage = Application.fetch_env!(:storyarn, :storage)
    Application.put_env(:storyarn, :storage, Keyword.put(original_storage, :adapter, Storyarn.SnapshotResetStorage))
    on_exit(fn -> Application.put_env(:storyarn, :storage, original_storage) end)

    unsafe_keys =
      Enum.map(["a", "b"], &("projects/1/snapshots/archives/v2/ready/" <> <<0>> <> &1))

    Storyarn.SnapshotResetStorage.put_objects(Map.new(unsafe_keys, &{&1, 1}))

    assert {:ok, run} = start_run(provider_page_size: 1)
    completed = advance_until_terminal(run.id, run.cursor_generation)

    assert completed.status == "completed"
    assert completed.provider_last_key == List.last(unsafe_keys)

    findings = Versioning.list_project_snapshot_reconciliation_findings(run.id)
    assert Enum.map(findings, & &1.category) == ["unsafe_snapshot_storage_key", "unsafe_snapshot_storage_key"]
    assert Enum.all?(findings, &(&1.details["storage_key_encoding"] == "base64url"))

    assert Enum.sort(Enum.map(findings, & &1.storage_key)) ==
             Enum.sort(Enum.map(unsafe_keys, &("base64url:" <> Base.url_encode64(&1, padding: false))))
  end

  test "provider scan encodes URL- and credential-like storage keys without losing inventory identity" do
    original_storage = Application.fetch_env!(:storyarn, :storage)
    Application.put_env(:storyarn, :storage, Keyword.put(original_storage, :adapter, Storyarn.SnapshotResetStorage))
    on_exit(fn -> Application.put_env(:storyarn, :storage, original_storage) end)

    raw_keys = [
      "projects/1/snapshots/archives/v2/ready//HTTPS://storage.example/object",
      "projects/1/snapshots/archives/v2/ready/abcdefghijklmnop/file?token=secret"
    ]

    Storyarn.SnapshotResetStorage.put_objects(Map.new(raw_keys, &{&1, 1}))

    assert {:ok, run} = start_run()
    completed = advance_until_terminal(run.id, run.cursor_generation)

    assert completed.status == "completed"
    assert completed.provider_last_key == Enum.max(raw_keys)

    findings = Versioning.list_project_snapshot_reconciliation_findings(run.id)
    assert length(findings) == 2

    assert Enum.sort(Enum.map(findings, & &1.storage_key)) ==
             Enum.sort(Enum.map(raw_keys, &("base64url:" <> Base.url_encode64(&1, padding: false))))

    Enum.each(findings, fn finding ->
      assert finding.details["storage_key_encoding"] == "base64url"
      assert is_nil(finding.details["path"])
      "base64url:" <> encoded = finding.storage_key
      assert {:ok, decoded} = Base.url_decode64(encoded, padding: false)
      assert decoded in raw_keys
    end)

    refute String.contains?(inspect(findings), ["HTTPS://", "token=secret"])
  end

  test "the ready-snapshot high-watermark excludes snapshots created after the run starts" do
    assert {:ok, run} = start_run()
    assert run.snapshot_high_watermark == 0

    {_user, _project, _snapshot} = ready_snapshot!()
    completed = advance_until_terminal(run.id, run.cursor_generation)

    assert completed.status == "completed"
    assert completed.inspected_snapshot_count == 0
    assert Versioning.list_project_snapshot_reconciliation_findings(run.id) == []
  end

  test "run identity and progress are guarded in PostgreSQL" do
    assert {:ok, run} = start_run()

    assert_raise Postgrex.Error, ~r/snapshot reconciliation run identity is immutable/, fn ->
      Repo.transaction(fn ->
        run
        |> Ecto.Changeset.change(max_findings: run.max_findings - 1, cursor_generation: run.cursor_generation + 1)
        |> Repo.update!()
      end)
    end

    assert_raise Postgrex.Error, ~r/snapshot reconciliation progress must advance exactly once/, fn ->
      Repo.transaction(fn ->
        run
        |> Ecto.Changeset.change(status: "running", cursor_generation: run.cursor_generation + 2)
        |> Repo.update!()
      end)
    end

    now = TimeHelpers.now()

    assert_raise Postgrex.Error, ~r/snapshot reconciliation state cannot regress/, fn ->
      Repo.transaction(fn ->
        run
        |> Ecto.Changeset.change(
          status: "completed",
          phase: "completed",
          cursor_generation: run.cursor_generation + 1,
          started_at: now,
          finished_at: now
        )
        |> Repo.update!()
      end)
    end

    assert_raise Postgrex.Error, ~r/snapshot reconciliation runs cannot be deleted/, fn ->
      Repo.transaction(fn -> Repo.delete!(run) end)
    end

    # The repair ledger's restrictive foreign key now rejects the truncation
    # before the findings trigger can emit its own immutable-evidence message.
    assert_raise Postgrex.Error, ~r/cannot truncate a table referenced in a foreign key constraint/, fn ->
      Repo.transaction(fn -> Repo.query!("TRUNCATE project_snapshot_reconciliation_findings") end)
    end
  end

  test "runs must be inserted in the exact pristine pending state" do
    now = TimeHelpers.now()

    base_attrs = %{
      max_objects_per_step: 1,
      max_bytes_per_step: 128 * 1024 * 1024,
      max_findings: 10,
      provider_page_size: 1,
      max_provider_objects: 10,
      max_provider_bytes: 1024
    }

    invalid_runs = [
      Map.merge(base_attrs, %{
        provider_namespace_fingerprint: String.duplicate("e", 64),
        status: "completed",
        phase: "completed",
        provider_scan_completed: true,
        started_at: now,
        finished_at: now
      }),
      Map.merge(base_attrs, %{
        provider_namespace_fingerprint: String.duplicate("f", 64),
        inspected_object_count: 1
      })
    ]

    for attrs <- invalid_runs do
      assert_raise Postgrex.Error, ~r/snapshot reconciliation runs must start pending and pristine/, fn ->
        Repo.transaction(fn ->
          %ProjectSnapshotReconciliationRun{}
          |> Ecto.Changeset.change(attrs)
          |> Repo.insert!()
        end)
      end
    end
  end

  test "future phase cursors and fabricated provider entry are rejected in PostgreSQL" do
    {user, project, snapshot} = ready_snapshot!()
    reservation = Repo.get!(StorageReservation, snapshot.storage_reservation_id)

    assert {:ok, _intent} =
             Versioning.delete_project_snapshot(user_scope_fixture(user), project, snapshot.id)

    claim_prefix = SnapshotArchiveStorage.ready_prefix(project.id, "CURSORGUARD00001")

    claim_prefix
    |> SnapshotObjectPublicationClaim.create_changeset(
      String.duplicate("a", 64),
      Ecto.UUID.generate(),
      DateTime.add(TimeHelpers.now(), 3_600, :second),
      reservation.id,
      reservation.lease_token
    )
    |> Repo.insert!()

    assert {:ok, run} = start_run()
    assert run.reservation_high_watermark > 0
    assert run.claim_sequence_high_watermark > 0
    assert run.cleanup_intent_high_watermark > 0

    assert_progress_update_rejected(run, reservation_after_id: run.reservation_high_watermark)
    assert_progress_update_rejected(run, claim_after_sequence: run.claim_sequence_high_watermark)
    assert_progress_update_rejected(run, cleanup_intent_after_id: run.cleanup_intent_high_watermark)

    assert_progress_update_rejected(run,
      provider_cursor: "fabricated-cursor",
      provider_last_key: claim_prefix <> "/manifest.json",
      provider_object_count: 1,
      provider_bytes: 1
    )

    cleanup_phase =
      advance_until(run.id, run.cursor_generation, &(&1.phase == "cleanup_intents"))

    assert_progress_update_rejected(cleanup_phase,
      phase: "provider_objects",
      cleanup_intent_after_id: cleanup_phase.cleanup_intent_high_watermark,
      provider_cursor: "fabricated-cursor",
      provider_last_key: claim_prefix <> "/manifest.json",
      provider_object_count: 1,
      provider_bytes: 1
    )
  end

  test "terminal runs reject late findings in PostgreSQL" do
    assert {:ok, run} = start_run()
    assert {:ok, :failed} = Versioning.fail_project_snapshot_reconciliation(run.id, run.cursor_generation, :test)

    finding =
      ProjectSnapshotReconciliationFinding.create_changeset(
        %ProjectSnapshotReconciliationFinding{},
        %{
          run_id: run.id,
          fingerprint: String.duplicate("a", 64),
          category: "ambiguous_storage_object",
          severity: "critical",
          details: %{}
        }
      )

    assert finding.valid?

    assert_raise Postgrex.Error, ~r/findings cannot be inserted after run completion/, fn ->
      Repo.transaction(fn -> Repo.insert!(finding) end)
    end
  end

  test "finding validation rejects nested or oversized operator evidence" do
    changeset =
      ProjectSnapshotReconciliationFinding.create_changeset(
        %ProjectSnapshotReconciliationFinding{},
        %{
          run_id: 1,
          fingerprint: String.duplicate("a", 64),
          category: "ambiguous_storage_object",
          severity: "critical",
          details: %{"nested" => %{"secret" => "value"}}
        }
      )

    refute changeset.valid?
    assert "contains unsafe reconciliation evidence" in errors_on(changeset).details

    unsafe_url =
      ProjectSnapshotReconciliationFinding.create_changeset(
        %ProjectSnapshotReconciliationFinding{},
        %{
          run_id: 1,
          fingerprint: String.duplicate("b", 64),
          category: "ambiguous_storage_object",
          severity: "critical",
          details: %{"source" => "read failed at HTTPS://storage.example/presigned"}
        }
      )

    refute unsafe_url.valid?
    assert "contains unsafe reconciliation evidence" in errors_on(unsafe_url).details

    unsafe_storage_key =
      ProjectSnapshotReconciliationFinding.create_changeset(
        %ProjectSnapshotReconciliationFinding{},
        %{
          run_id: 1,
          fingerprint: String.duplicate("c", 64),
          category: "ambiguous_storage_object",
          severity: "critical",
          storage_key: "projects/1/HTTPS://storage.example/presigned",
          details: %{}
        }
      )

    refute unsafe_storage_key.valid?
    assert "contains unsafe reconciliation evidence" in errors_on(unsafe_storage_key).storage_key

    encoded_storage_key =
      ProjectSnapshotReconciliationFinding.create_changeset(
        %ProjectSnapshotReconciliationFinding{},
        %{
          run_id: 1,
          fingerprint: String.duplicate("d", 64),
          category: "ambiguous_storage_object",
          severity: "critical",
          storage_key: "base64url:abcx-amz-def",
          details: %{"storage_key_encoding" => "base64url"}
        }
      )

    assert encoded_storage_key.valid?
  end

  test "finding storage keys use the database byte limit" do
    attrs = %{
      run_id: 1,
      fingerprint: String.duplicate("a", 64),
      category: "ambiguous_storage_object",
      severity: "critical",
      details: %{}
    }

    at_limit =
      ProjectSnapshotReconciliationFinding.create_changeset(
        %ProjectSnapshotReconciliationFinding{},
        Map.put(attrs, :storage_key, String.duplicate("é", 2_048))
      )

    assert at_limit.valid?

    over_limit =
      ProjectSnapshotReconciliationFinding.create_changeset(
        %ProjectSnapshotReconciliationFinding{},
        Map.put(attrs, :storage_key, String.duplicate("é", 2_049))
      )

    refute over_limit.valid?
    assert "should be at most 4096 byte(s)" in errors_on(over_limit).storage_key
  end

  test "the worker relies on transactionally persisted continuations" do
    assert {:ok, run} = start_run()
    first_job = reconciliation_job!(run.id, run.cursor_generation)

    assert :ok = InspectProjectSnapshotsWorker.perform(%{first_job | attempt: 1})
    running = Versioning.get_project_snapshot_reconciliation_run(run.id)
    assert running.status == "running"
    assert continuation_persisted?(run.id, running.cursor_generation)

    completed = advance_until_terminal(run.id, running.cursor_generation)
    assert completed.status == "completed"
  end

  test "the worker terminalizes a raised page failure only on its final attempt" do
    assert {:ok, run} = start_run()
    job = reconciliation_job!(run.id, run.cursor_generation)
    advance = fn _run_id, _cursor_generation -> raise "private database failure" end

    assert_raise RuntimeError, "private database failure", fn ->
      InspectProjectSnapshotsWorker.perform_page(%{job | attempt: 1}, advance)
    end

    assert Versioning.get_project_snapshot_reconciliation_run(run.id).status == "pending"

    assert :ok =
             InspectProjectSnapshotsWorker.perform_page(
               %{job | attempt: job.max_attempts},
               advance
             )

    failed = Versioning.get_project_snapshot_reconciliation_run(run.id)
    assert failed.status == "failed"
    assert failed.last_error_code == "snapshot_reconciliation_page_exception"
    assert %DateTime{} = failed.finished_at
  end

  test "the worker terminalizes deterministic page errors without exhausting retries" do
    Enum.each(
      [
        :invalid_snapshot_reconciliation_inventory_digest,
        :invalid_snapshot_reconciliation_provider_page,
        :snapshot_reconciliation_inventory_limit_exceeded
      ],
      fn reason ->
        assert {:ok, run} = start_run()
        job = reconciliation_job!(run.id, run.cursor_generation)
        advance = fn _run_id, _cursor_generation -> {:error, reason} end

        assert :ok = InspectProjectSnapshotsWorker.perform_page(%{job | attempt: 1}, advance)

        failed = Versioning.get_project_snapshot_reconciliation_run(run.id)
        assert failed.status == "failed"
        assert failed.last_error_code == Atom.to_string(reason)
      end
    )
  end

  test "the worker keeps provider availability failures retryable" do
    assert {:ok, run} = start_run()
    job = reconciliation_job!(run.id, run.cursor_generation)

    advance = fn _run_id, _cursor_generation ->
      {:error, {:snapshot_reconciliation_provider_list_failed, :provider_timeout}}
    end

    assert {:error, :snapshot_reconciliation_page_failed} =
             InspectProjectSnapshotsWorker.perform_page(%{job | attempt: 1}, advance)

    unchanged = Versioning.get_project_snapshot_reconciliation_run(run.id)
    assert unchanged.status == "pending"
    assert is_nil(unchanged.last_error_code)
  end

  test "the worker lets exits and throws reach Oban even on the final attempt" do
    assert {:ok, run} = start_run()
    job = reconciliation_job!(run.id, run.cursor_generation)
    exit_advance = fn _run_id, _cursor_generation -> exit(:database_connection_timeout) end
    throw_advance = fn _run_id, _cursor_generation -> throw(:provider_cancelled) end

    assert catch_exit(
             InspectProjectSnapshotsWorker.perform_page(
               %{job | attempt: job.max_attempts},
               exit_advance
             )
           ) == :database_connection_timeout

    assert catch_throw(
             InspectProjectSnapshotsWorker.perform_page(
               %{job | attempt: job.max_attempts},
               throw_advance
             )
           ) == :provider_cancelled

    unchanged = Versioning.get_project_snapshot_reconciliation_run(run.id)
    assert unchanged.status == "pending"
    assert is_nil(unchanged.last_error_code)
  end

  test "the worker terminalizes an unexpected page result only on its final attempt" do
    assert {:ok, run} = start_run()
    job = reconciliation_job!(run.id, run.cursor_generation)
    advance = fn _run_id, _cursor_generation -> :unexpected_result end

    assert {:error, :snapshot_reconciliation_page_failed} =
             InspectProjectSnapshotsWorker.perform_page(%{job | attempt: 1}, advance)

    assert Versioning.get_project_snapshot_reconciliation_run(run.id).status == "pending"

    assert :ok =
             InspectProjectSnapshotsWorker.perform_page(
               %{job | attempt: job.max_attempts},
               advance
             )

    failed = Versioning.get_project_snapshot_reconciliation_run(run.id)
    assert failed.status == "failed"
    assert failed.last_error_code == "snapshot_reconciliation_invalid_page_result"
    assert %DateTime{} = failed.finished_at
  end

  test "starting an active run restores a missing current-generation delivery" do
    assert {:ok, run} = start_run()
    original = reconciliation_job!(run.id, run.cursor_generation)

    original
    |> Ecto.Changeset.change(state: "discarded", discarded_at: %{TimeHelpers.now() | microsecond: {0, 6}})
    |> Repo.update!()

    assert {:ok, same_run} = start_run()
    assert same_run.id == run.id

    replacement = reconciliation_job!(run.id, run.cursor_generation)
    assert replacement.id > original.id
    assert replacement.state == "available"
  end

  test "starting an active run rescues only stale executing current-generation delivery" do
    assert {:ok, run} = start_run()
    original = reconciliation_job!(run.id, run.cursor_generation)
    now = %{database_clock_now() | microsecond: {0, 6}}

    original
    |> Ecto.Changeset.change(state: "executing", attempt: 1, attempted_at: now)
    |> Repo.update!()

    assert {:ok, same_run} = start_run()
    assert same_run.id == run.id
    assert Repo.get!(Oban.Job, original.id).state == "executing"

    original
    |> Ecto.Changeset.change(
      state: "executing",
      attempt: 1,
      attempted_at: DateTime.add(now, -16 * 60, :second)
    )
    |> Repo.update!()

    assert {:ok, same_run} = start_run()
    assert same_run.id == run.id

    rescued = Repo.get!(Oban.Job, original.id)
    assert rescued.state == "available"
    assert rescued.attempt == 1
  end

  test "a stale executing final-attempt delivery is replaced for the active generation" do
    assert {:ok, run} = start_run()
    original = reconciliation_job!(run.id, run.cursor_generation)
    attempted_at = DateTime.add(database_clock_now(), -16 * 60, :second)

    original
    |> Ecto.Changeset.change(
      state: "executing",
      attempt: original.max_attempts,
      attempted_at: %{attempted_at | microsecond: {0, 6}}
    )
    |> Repo.update!()

    assert {:ok, same_run} = start_run()
    assert same_run.id == run.id
    assert Repo.get!(Oban.Job, original.id).state == "discarded"

    replacement = reconciliation_job!(run.id, run.cursor_generation)
    assert replacement.id > original.id
    assert replacement.state == "available"
  end

  test "active-run recovery does not requeue a stale delivery for another contract" do
    assert {:ok, run} = start_run()
    attempted_at = DateTime.add(database_clock_now(), -16 * 60, :second)

    wrong_contract =
      %{
        run_id: run.id,
        cursor_generation: run.cursor_generation,
        contract_version: run.contract_version + 1
      }
      |> InspectProjectSnapshotsWorker.new()
      |> Oban.insert!()
      |> Ecto.Changeset.change(
        state: "executing",
        attempt: 1,
        attempted_at: %{attempted_at | microsecond: {0, 6}}
      )
      |> Repo.update!()

    assert {:ok, same_run} = start_run()
    assert same_run.id == run.id
    assert Repo.get!(Oban.Job, wrong_contract.id).state == "executing"
  end

  test "the worker's final attempt persists namespace failures as terminal evidence" do
    assert {:ok, run} = start_run()
    job = reconciliation_job!(run.id, run.cursor_generation)
    current_storage = Application.fetch_env!(:storyarn, :storage)
    different_upload_dir = Keyword.fetch!(current_storage, :upload_dir) <> "-different"
    File.mkdir_p!(different_upload_dir)

    Application.put_env(
      :storyarn,
      :storage,
      Keyword.put(current_storage, :upload_dir, different_upload_dir)
    )

    on_exit(fn -> File.rm_rf!(different_upload_dir) end)

    assert :ok = InspectProjectSnapshotsWorker.perform(%{job | attempt: job.max_attempts})
    failed = Versioning.get_project_snapshot_reconciliation_run(run.id)
    assert failed.status == "failed"
    assert failed.last_error_code == "snapshot_reconciliation_namespace_changed"
  end

  test "telemetry reports committed dry-run progress without identifier tags" do
    test_pid = self()
    handler_id = {__MODULE__, System.unique_integer([:positive])}

    events = [
      [:storyarn, :snapshot, :reconciliation, :start],
      [:storyarn, :snapshot, :reconciliation, :page],
      [:storyarn, :snapshot, :reconciliation, :stop]
    ]

    :ok =
      :telemetry.attach_many(
        handler_id,
        events,
        fn event, measurements, metadata, _config ->
          send(test_pid, {:reconciliation_telemetry, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert {:ok, run} = start_run()

    assert_receive {:reconciliation_telemetry, [:storyarn, :snapshot, :reconciliation, :start], %{count: 1},
                    %{contract_version: 1, mode: :dry_run}}

    completed = advance_until_terminal(run.id, run.cursor_generation)
    assert completed.status == "completed"

    assert_receive {:reconciliation_telemetry, [:storyarn, :snapshot, :reconciliation, :page], measurements,
                    %{phase: phase, status: status}}

    assert is_integer(measurements.finding_count)
    assert phase in [:ready_snapshots, :stale_reservations, :publication_claims, :cleanup_intents, :provider_objects]
    assert status == :running

    assert_receive {:reconciliation_telemetry, [:storyarn, :snapshot, :reconciliation, :stop], %{count: 1},
                    %{status: :completed, multipart_inventory_state: :unsupported, error_code: "none"}}
  end

  test "completed-run summary reports bounded actionable drift without double counting snapshots" do
    user = user_fixture()
    project = project_fixture(user)

    assert {:ok, _asset} =
             Assets.upload_binary_and_create_asset(
               "summary asset bytes",
               %{filename: "summary.png", content_type: "image/png"},
               project,
               user
             )

    {_user, _project, damaged_snapshot} = ready_snapshot!(user, project)
    assert {:ok, archive} = Storage.download(damaged_snapshot.archive_storage_key)
    <<first, rest::binary>> = archive

    assert {:ok, _url} =
             Storage.upload(
               damaged_snapshot.archive_storage_key,
               <<Bitwise.bxor(first, 1), rest::binary>>,
               "application/zip"
             )

    assert :ok = Storage.delete(damaged_snapshot.manifest_storage_key)

    stale_project = project_fixture(user)

    assert {:ok, stale_snapshot} =
             Versioning.request_full_project_snapshot(user_scope_fixture(user), stale_project, %{
               idempotency_key: Ecto.UUID.generate()
             })

    now = TimeHelpers.now()
    old = %{DateTime.add(now, -86_400, :second) | microsecond: {0, 6}}

    stale_reservation =
      stale_snapshot.storage_reservation_id
      |> then(&Repo.get!(StorageReservation, &1))
      |> Ecto.Changeset.change(
        expires_at: DateTime.add(now, -1, :second),
        accounting_measured_at: DateTime.add(now, -2, :second)
      )
      |> Repo.update!()

    stale_snapshot.build_job_id
    |> then(&Repo.get!(Oban.Job, &1))
    |> Ecto.Changeset.change(state: "discarded", discarded_at: old)
    |> Repo.update!()

    {_user, _project, abandoned_snapshot} = ready_snapshot!()
    abandoned_key = String.replace(abandoned_snapshot.object_prefix, "/ready/", "/staging/") <> "/orphan.bin"
    abandoned_bytes = "abandoned summary bytes"
    assert {:ok, _url} = Storage.upload(abandoned_key, abandoned_bytes, "application/octet-stream")

    cleanup_project = project_fixture(user)
    {_user, _project, cleanup_snapshot} = ready_snapshot!(user, cleanup_project)

    assert {:ok, cleanup_intent} =
             Versioning.delete_project_snapshot(
               user_scope_fixture(user),
               cleanup_project,
               cleanup_snapshot.id
             )

    assert {:ok, :terminal} =
             Versioning.process_project_snapshot_cleanup_intent(cleanup_intent.id,
               delete_fun: fn keys -> {:error, keys} end,
               final_attempt?: true
             )

    test_pid = self()
    handler_id = {__MODULE__, :summary, System.unique_integer([:positive])}

    :ok =
      :telemetry.attach(
        handler_id,
        [:storyarn, :snapshot, :reconciliation, :summary],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:reconciliation_summary, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert {:ok, run} = start_run()
    completed = advance_until_terminal(run.id, run.cursor_generation)
    assert completed.status == "completed"

    assert_receive {:reconciliation_summary, [:storyarn, :snapshot, :reconciliation, :summary], measurements,
                    %{contract_version: 1, mode: :dry_run, multipart_inventory_state: :unsupported}}

    assert measurements == %{
             stale_reservation_bytes: stale_reservation.reserved_bytes,
             orphan_object_bytes: byte_size(abandoned_bytes),
             missing_ready_snapshot_count: 1,
             corrupt_ready_snapshot_count: 1,
             terminal_cleanup_failure_count: 1,
             terminal_cleanup_retry_count: 1
           }

    assert {:ok, :completed} =
             Versioning.advance_project_snapshot_reconciliation(completed.id, completed.cursor_generation)

    refute_receive {:reconciliation_summary, _, _, _}
  end

  defp ready_snapshot! do
    user = user_fixture()
    project = project_fixture(user)

    ready_snapshot!(user, project)
  end

  defp ready_snapshot!(user, project) do
    assert {:ok, requested} =
             Versioning.request_full_project_snapshot(user_scope_fixture(user), project, %{
               idempotency_key: Ecto.UUID.generate()
             })

    job =
      requested.build_job_id
      |> then(&Repo.get!(Oban.Job, &1))
      |> Ecto.Changeset.change(
        state: "executing",
        attempt: 1,
        attempted_at: %{TimeHelpers.now() | microsecond: {0, 6}}
      )
      |> Repo.update!()

    assert :ok = BuildProjectSnapshotWorker.perform(job)
    snapshot = Repo.get!(ProjectSnapshot, requested.id)
    assert snapshot.lifecycle_state == "ready"
    {user, project, snapshot}
  end

  defp download_manifest!(snapshot) do
    assert {:ok, manifest_json} = Storage.download(snapshot.manifest_storage_key)
    Jason.decode!(manifest_json)
  end

  defp replace_ready_manifest!(snapshot, manifest) do
    manifest_json = Jason.encode!(manifest)
    manifest_size_bytes = byte_size(manifest_json)
    size_delta = manifest_size_bytes - snapshot.manifest_size_bytes
    manifest_checksum = :sha256 |> :crypto.hash(manifest_json) |> Base.encode16(case: :lower)

    assert {:ok, _url} = Storage.upload(snapshot.manifest_storage_key, manifest_json, "application/json")

    snapshot
    |> Ecto.Changeset.change(
      manifest_checksum: manifest_checksum,
      manifest_size_bytes: manifest_size_bytes,
      total_size_bytes: snapshot.total_size_bytes + size_delta,
      accounted_size_bytes: snapshot.accounted_size_bytes + size_delta,
      progress_bytes: snapshot.progress_bytes + size_delta,
      progress_total_bytes: snapshot.progress_total_bytes + size_delta
    )
    |> Repo.update!()
  end

  defp in_flight_ready_namespace!(claim_status) when claim_status in ["publishing", "published"] do
    user = user_fixture()
    project = project_fixture(user)

    assert {:ok, requested} =
             Versioning.request_full_project_snapshot(user_scope_fixture(user), project, %{
               idempotency_key: Ecto.UUID.generate()
             })

    now = TimeHelpers.now()
    claim_token = Ecto.UUID.generate()

    requested.build_job_id
    |> then(&Repo.get!(Oban.Job, &1))
    |> Ecto.Changeset.change(
      state: "executing",
      attempt: 1,
      attempted_at: %{now | microsecond: {0, 6}}
    )
    |> Repo.update!()

    assert {:ok, :captured} =
             ProjectSnapshotBuild.materialize_capture(requested.id, requested.build_job_id)

    requested = Repo.get!(ProjectSnapshot, requested.id)

    building =
      requested
      |> ProjectSnapshot.build_state_changeset(%{
        lifecycle_state: "building",
        progress_phase: "copying",
        build_attempt: 1,
        building_started_at: now,
        publication_claim_token: claim_token,
        state_updated_at: now
      })
      |> Repo.update!()

    reservation = Repo.get!(StorageReservation, building.storage_reservation_id)

    assert {:ok, cleanup_scope} =
             SnapshotArchiveStorage.cleanup_scope_from_snapshot(building)

    assert {:ok, started} =
             Billing.mark_storage_reservation_started(
               reservation.id,
               reservation.lease_token,
               reservation.generation,
               cleanup_scope
             )

    claim =
      building.object_prefix
      |> SnapshotObjectPublicationClaim.create_changeset(
        String.duplicate("a", 64),
        claim_token,
        DateTime.add(now, 3_600, :second),
        started.id,
        started.lease_token
      )
      |> Repo.insert!()
      |> SnapshotObjectPublicationClaim.status_changeset("staged")
      |> Repo.update!()
      |> SnapshotObjectPublicationClaim.status_changeset("publishing", DateTime.add(now, 3_600, :second))
      |> Repo.update!()

    if claim_status == "published" do
      claim
      |> SnapshotObjectPublicationClaim.status_changeset("published")
      |> Repo.update!()
    end

    verifying =
      building
      |> ProjectSnapshot.build_state_changeset(%{
        lifecycle_state: "verifying",
        progress_phase: "verifying",
        verifying_started_at: now,
        state_updated_at: now
      })
      |> Repo.update!()

    storage_key = verifying.archive_storage_key
    assert {:ok, _url} = Storage.upload(storage_key, "publishing", "application/zip")

    {verifying, storage_key}
  end

  defp poisoned_claim!(snapshot) do
    reservation = Repo.get!(StorageReservation, snapshot.storage_reservation_id)

    snapshot.object_prefix
    |> SnapshotObjectPublicationClaim.create_changeset(
      String.duplicate("a", 64),
      Ecto.UUID.generate(),
      DateTime.add(TimeHelpers.now(), 3_600, :second),
      reservation.id,
      reservation.lease_token
    )
    |> Repo.insert!()
    |> SnapshotObjectPublicationClaim.status_changeset("poisoned")
    |> Repo.update!()
  end

  defp replace_published_claim!(snapshot, mismatch) when mismatch in [:claim_token, :reservation_lease_token] do
    existing_claim = Repo.get!(SnapshotObjectPublicationClaim, snapshot.object_prefix)
    reservation = Repo.get!(StorageReservation, snapshot.storage_reservation_id)
    now = TimeHelpers.now()
    old_enough = DateTime.add(now, -3_600, :second)

    Repo.delete!(existing_claim)

    claim_token =
      if mismatch == :claim_token,
        do: Ecto.UUID.generate(),
        else: snapshot.publication_claim_token

    reservation_lease_token =
      if mismatch == :reservation_lease_token,
        do: Ecto.UUID.generate(),
        else: reservation.lease_token

    claim =
      snapshot.object_prefix
      |> SnapshotObjectPublicationClaim.create_changeset(
        SnapshotObjectPublicationClaim.inventory_digest(snapshot),
        claim_token,
        DateTime.add(now, 3_600, :second),
        reservation.id,
        reservation_lease_token
      )
      |> Repo.insert!()
      |> SnapshotObjectPublicationClaim.status_changeset("staged")
      |> Repo.update!()
      |> SnapshotObjectPublicationClaim.status_changeset("publishing", DateTime.add(now, 3_600, :second))
      |> Repo.update!()
      |> SnapshotObjectPublicationClaim.status_changeset("published")
      |> Repo.update!()
      |> Ecto.Changeset.change(updated_at: old_enough)
      |> Repo.update!()

    snapshot.build_job_id
    |> then(&Repo.get!(Oban.Job, &1))
    |> Ecto.Changeset.change(
      state: "discarded",
      discarded_at: %{old_enough | microsecond: {0, 6}}
    )
    |> Repo.update!()

    {claim, reservation}
  end

  defp assert_published_claim_ownership_mismatch!(snapshot) do
    assert {:ok, run} = start_run()
    completed = advance_until_terminal(run.id, run.cursor_generation)

    assert completed.status == "completed"

    assert Enum.any?(
             Versioning.list_project_snapshot_reconciliation_findings(run.id, limit: 500),
             &(&1.category == "failed_snapshot_finalization" and
                 &1.error_code == "published_claim_ownership_mismatch" and
                 &1.project_snapshot_id_snapshot == snapshot.id)
           )
  end

  defp start_run(opts \\ []) do
    Storyarn.SnapshotReconciliationTestHelpers.start_run(default_start_run_opts(opts))
  end

  defp start_run_once(opts) do
    Versioning.start_project_snapshot_reconciliation(default_start_run_opts(opts))
  end

  defp default_start_run_opts(opts) do
    defaults = [
      max_objects_per_step: 1,
      provider_page_size: 1,
      max_provider_objects: 1_000,
      max_provider_bytes: 1024 * 1024 * 1024
    ]

    Keyword.merge(defaults, opts)
  end

  defp install_snapshot_read_switch_storage do
    original_storage = Application.fetch_env!(:storyarn, :storage)
    {:ok, _pid} = SnapshotReadSwitchStorage.start_link(%{})

    Application.put_env(
      :storyarn,
      :storage,
      Keyword.put(original_storage, :adapter, SnapshotReadSwitchStorage)
    )

    on_exit(fn ->
      Application.put_env(:storyarn, :storage, original_storage)

      if Process.whereis(SnapshotReadSwitchStorage) do
        Agent.stop(SnapshotReadSwitchStorage)
      end
    end)
  end

  defp advance_until_terminal(run_id, generation, remaining \\ 100)

  defp advance_until_terminal(run_id, _generation, 0) do
    flunk("snapshot reconciliation run ##{run_id} did not terminate")
  end

  defp advance_until_terminal(run_id, generation, remaining) do
    case Versioning.advance_project_snapshot_reconciliation(run_id, generation) do
      {:ok, :completed} ->
        Versioning.get_project_snapshot_reconciliation_run(run_id)

      {:ok, :failed} ->
        Versioning.get_project_snapshot_reconciliation_run(run_id)

      {:ok, status, next_generation} when status in [:continue, :stale] ->
        advance_until_terminal(run_id, next_generation, remaining - 1)

      other ->
        flunk("unexpected snapshot reconciliation result: #{inspect(other)}")
    end
  end

  defp advance_until(run_id, generation, predicate, remaining \\ 20)

  defp advance_until(run_id, _generation, _predicate, 0) do
    flunk("snapshot reconciliation run ##{run_id} did not reach the expected progress state")
  end

  defp advance_until(run_id, generation, predicate, remaining) do
    case Versioning.advance_project_snapshot_reconciliation(run_id, generation) do
      {:ok, :continue, next_generation} ->
        run = Versioning.get_project_snapshot_reconciliation_run(run_id)

        if predicate.(run),
          do: run,
          else: advance_until(run_id, next_generation, predicate, remaining - 1)

      other ->
        flunk("unexpected snapshot reconciliation progress result: #{inspect(other)}")
    end
  end

  defp capture_repo_queries(fun) when is_function(fun, 0) do
    handler_id = "snapshot-reconciliation-query-capture-#{System.unique_integer([:positive])}"
    marker = make_ref()
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:storyarn, :repo, :query],
        fn _event, _measurements, %{query: query}, {pid, ref} ->
          if self() == pid, do: send(pid, {ref, query})
        end,
        {test_pid, marker}
      )

    try do
      {fun.(), drain_repo_queries(marker)}
    after
      :telemetry.detach(handler_id)
    end
  end

  defp drain_repo_queries(marker, queries \\ []) do
    receive do
      {^marker, query} -> drain_repo_queries(marker, [query | queries])
    after
      0 -> Enum.reverse(queries)
    end
  end

  defp continuation_persisted?(run_id, generation) do
    Repo.exists?(
      from(job in Oban.Job,
        where:
          job.worker == ^inspect(InspectProjectSnapshotsWorker) and
            fragment("?->>'run_id'", job.args) == ^to_string(run_id) and
            fragment("?->>'cursor_generation'", job.args) == ^to_string(generation)
      )
    )
  end

  defp assert_progress_update_rejected(run, attrs) do
    assert_raise Postgrex.Error, ~r/snapshot reconciliation progress must advance exactly once/, fn ->
      Repo.transaction(fn ->
        run
        |> Ecto.Changeset.change(Keyword.put(attrs, :cursor_generation, run.cursor_generation + 1))
        |> Repo.update!()
      end)
    end
  end

  defp reconciliation_job!(run_id, generation) do
    Repo.one!(
      from(job in Oban.Job,
        where:
          job.worker == ^inspect(InspectProjectSnapshotsWorker) and
            fragment("?->>'run_id'", job.args) == ^to_string(run_id) and
            fragment("?->>'cursor_generation'", job.args) == ^to_string(generation),
        order_by: [desc: job.id],
        limit: 1
      )
    )
  end

  defp list_all_objects(prefix) do
    {:ok, %{objects: objects, cursor: nil}} = Storage.list_prefix(prefix, limit: 1_000)
    Enum.sort_by(objects, & &1.key)
  end

  defp database_clock_now do
    %Postgrex.Result{rows: [[now]]} = Repo.query!("SELECT clock_timestamp()")
    now
  end

  defp hold_claim_writer_lock do
    parent = self()

    lock_holder =
      Task.async(fn ->
        :ok = Sandbox.checkout(Repo, sandbox: false)

        try do
          Repo.transaction(fn ->
            Repo.query!("LOCK TABLE snapshot_object_publication_claims IN ROW EXCLUSIVE MODE")
            send(parent, {:claim_writer_locked, self()})

            receive do
              :release_claim_writer -> :ok
            after
              5_000 -> exit(:claim_writer_release_timeout)
            end
          end)
        after
          Sandbox.checkin(Repo)
        end
      end)

    assert_receive {:claim_writer_locked, lock_holder_pid}, 2_000
    {lock_holder, lock_holder_pid}
  end
end
