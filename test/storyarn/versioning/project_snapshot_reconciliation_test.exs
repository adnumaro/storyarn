defmodule Storyarn.Versioning.ProjectSnapshotReconciliationTest do
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Assets
  alias Storyarn.Assets.Storage
  alias Storyarn.Assets.StorageCompensation
  alias Storyarn.Billing
  alias Storyarn.Billing.StorageReservation
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Versioning
  alias Storyarn.Versioning.ProjectSnapshot
  alias Storyarn.Versioning.ProjectSnapshotCapture
  alias Storyarn.Versioning.ProjectSnapshotReconciliationFinding
  alias Storyarn.Versioning.ProjectSnapshotReconciliationRun
  alias Storyarn.Versioning.SnapshotObjectPublicationClaim
  alias Storyarn.Versioning.SnapshotObjectStorage
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
    assert :ok = Storage.delete(missing_snapshot.project_storage_key)

    {_user, _project, corrupt_snapshot} = ready_snapshot!()
    {:ok, project_json} = Storage.download(corrupt_snapshot.project_storage_key)
    <<first, rest::binary>> = project_json
    corrupt_json = <<Bitwise.bxor(first, 1), rest::binary>>

    assert byte_size(corrupt_json) == byte_size(project_json)
    assert {:ok, _url} = Storage.upload(corrupt_snapshot.project_storage_key, corrupt_json, "application/json")

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

  test "two damaged objects in one ready snapshot both become findings and the scan completes" do
    user = user_fixture()
    project = project_fixture(user)

    assert {:ok, _asset} =
             Assets.upload_binary_and_create_asset(
               "snapshot asset bytes",
               %{filename: "snapshot.png", content_type: "image/png"},
               project,
               user
             )

    {_user, _project, snapshot} = ready_snapshot!(user, project)

    assert {:ok, %{manifest: manifest}} =
             SnapshotObjectStorage.inspect_ready_manifest(
               snapshot.manifest_storage_key,
               snapshot.manifest_checksum,
               snapshot.manifest_size_bytes
             )

    project_descriptor = Enum.find(manifest["objects"], &(&1["kind"] == "project"))
    blob_descriptor = Enum.find(manifest["objects"], &(&1["kind"] == "asset_blob"))
    project_key = snapshot.object_prefix <> "/" <> project_descriptor["path"]
    blob_key = snapshot.object_prefix <> "/" <> blob_descriptor["path"]

    assert :ok = Storage.delete(blob_key)
    assert {:ok, project_json} = Storage.download(project_key)
    <<first, rest::binary>> = project_json
    corrupt_json = <<Bitwise.bxor(first, 1), rest::binary>>

    assert {:ok, _url} = Storage.upload(project_key, corrupt_json, project_descriptor["content_type"])

    assert {:ok, run} = start_run()
    completed = advance_until_terminal(run.id, run.cursor_generation)

    findings =
      run.id
      |> Versioning.list_project_snapshot_reconciliation_findings(limit: 500)
      |> Enum.filter(
        &(&1.project_snapshot_id_snapshot == snapshot.id and
            &1.category in ["ready_object_missing", "ready_object_corrupt"])
      )

    assert completed.status == "completed"

    assert findings |> Enum.map(&{&1.category, &1.storage_key}) |> Enum.sort() ==
             Enum.sort([
               {"ready_object_corrupt", project_key},
               {"ready_object_missing", blob_key}
             ])
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
    unowned_key = SnapshotObjectStorage.staging_prefix(project.id, String.duplicate("x", 16)) <> "/project.json"
    unsafe_key = "projects/#{project.id}/snapshots/object-sets/v2/ready/not-supported/project.json"

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

    staging_key = String.replace(snapshot.object_prefix, "/ready/", "/staging/") <> "/project.json"
    assert {:ok, _url} = Storage.upload(staging_key, "unowned", "application/json")

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

    staging_key = String.replace(snapshot.object_prefix, "/ready/", "/staging/") <> "/project.json"
    assert {:ok, _url} = Storage.upload(staging_key, "unowned", "application/json")

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

  test "active cleanup ownership protects an adopted staging namespace" do
    user = user_fixture()
    project = project_fixture(user)
    prefix = SnapshotObjectStorage.staging_prefix(project.id, "ADOPTEDTEMP00001")
    storage_key = prefix <> "/project.json"

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
    prefix = SnapshotObjectStorage.staging_prefix(project.id, "OWNEDSUBSET00001")
    owned_key = prefix <> "/project.json"
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
    prefix = SnapshotObjectStorage.staging_prefix(project.id, "HISTCLEANUP00001")
    storage_key = prefix <> "/project.json"

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
    prefix = SnapshotObjectStorage.staging_prefix(project.id, "MANYRECEIPTS0001")
    storage_key = prefix <> "/project.json"

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
    prefix = SnapshotObjectStorage.staging_prefix(project.id, "LARGERECEIPT0001")
    storage_key = prefix <> "/project.json"

    oversized_inventory =
      [
        storage_key
        | Enum.map(1..20_004, fn index ->
            hash = index |> Integer.to_string() |> String.pad_leading(64, "0")
            "#{prefix}/blobs/#{hash}.bin"
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
    prefix = SnapshotObjectStorage.ready_prefix(project.id, "FAILEDCLAIM00001")

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

  test "a poisoned claim with fully resolved exact cleanup ownership is suppressed" do
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

    assert {:ok, cleanup_scope} =
             SnapshotObjectStorage.cleanup_scope_from_capture(
               project.id,
               snapshot.object_prefix,
               capture.manifest_json
             )

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

    assert_raise Postgrex.Error, ~r/snapshot reconciliation evidence cannot be truncated/, fn ->
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

    claim_prefix = SnapshotObjectStorage.ready_prefix(project.id, "CURSORGUARD00001")

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
          details: %{"source" => "https://storage.example/presigned"}
        }
      )

    refute unsafe_url.valid?
    assert "contains unsafe reconciliation evidence" in errors_on(unsafe_url).details
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

    capture = Repo.get!(ProjectSnapshotCapture, building.id)
    reservation = Repo.get!(StorageReservation, building.storage_reservation_id)

    assert {:ok, cleanup_scope} =
             SnapshotObjectStorage.cleanup_scope_from_capture(
               project.id,
               building.object_prefix,
               capture.manifest_json
             )

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

    storage_key = verifying.object_prefix <> "/project.json"
    assert {:ok, _url} = Storage.upload(storage_key, "publishing", "application/json")

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

  defp start_run(opts \\ []) do
    defaults = [
      max_objects_per_step: 1,
      provider_page_size: 1,
      max_provider_objects: 1_000,
      max_provider_bytes: 1024 * 1024 * 1024
    ]

    Versioning.start_project_snapshot_reconciliation(Keyword.merge(defaults, opts))
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
end
