defmodule Storyarn.Projects.Versioning.ProjectSnapshotReconciliationRepairTest do
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import ExUnit.CaptureLog
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Commercial.Billing
  alias Storyarn.Commercial.Billing.StorageReservation
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.Assets.Storage
  alias Storyarn.Projects.Assets.StorageCleanupRequest
  alias Storyarn.Projects.Versioning
  alias Storyarn.Projects.Versioning.ProjectSnapshot
  alias Storyarn.Projects.Versioning.ProjectSnapshotLifecycle
  alias Storyarn.Projects.Versioning.ProjectSnapshotReconciliationFinding
  alias Storyarn.Projects.Versioning.ProjectSnapshotReconciliationRepair
  alias Storyarn.Projects.Versioning.ProjectSnapshotReconciliationRepairAction
  alias Storyarn.Projects.Versioning.SnapshotArchiveStorage
  alias Storyarn.Projects.Versioning.SnapshotCleanupIntent
  alias Storyarn.Projects.Versioning.SnapshotObjectPublicationClaim
  alias Storyarn.Repo
  alias Storyarn.SnapshotReadSwitchStorage
  alias Storyarn.Workers.BuildProjectSnapshotWorker
  alias Storyarn.Workers.CleanupProjectSnapshotWorker
  alias Storyarn.Workers.RepairProjectSnapshotFindingWorker
  alias Storyarn.Workspaces

  setup do
    original_storage = Application.fetch_env!(:storyarn, :storage)

    isolated_upload_dir =
      original_storage
      |> Keyword.fetch!(:upload_dir)
      |> Path.join("snapshot-repair-#{System.unique_integer([:positive])}")

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

  test "repair planning is bounded, immutable, and idempotent" do
    {_user, _project, snapshot} = ready_snapshot!()
    assert :ok = Storage.delete(snapshot_payload_key(snapshot))

    assert {:ok, pending_run} = start_run()

    assert {:error, :snapshot_reconciliation_run_incomplete} =
             Versioning.plan_project_snapshot_reconciliation_repairs(pending_run.id)

    completed = advance_until_terminal(pending_run.id, pending_run.cursor_generation)
    assert completed.status == "completed"

    assert {:error, :invalid_snapshot_reconciliation_repair_options} =
             Versioning.plan_project_snapshot_reconciliation_repairs(completed.id, limit: 0)

    assert {:error, :invalid_snapshot_reconciliation_repair_options} =
             Versioning.plan_project_snapshot_reconciliation_repairs(completed.id, unsupported: true)

    assert {:ok, first_page} =
             Versioning.plan_project_snapshot_reconciliation_repairs(completed.id, limit: 1)

    assert [action] = first_page.actions
    assert action.action_kind == "mark_missing"
    assert action.status == "pending"
    assert action.attempt_count == 0
    refute first_page.complete?

    assert {:ok, repeated_page} =
             Versioning.plan_project_snapshot_reconciliation_repairs(completed.id, limit: 1)

    assert [repeated] = repeated_page.actions
    assert repeated.id == action.id

    assert [job] =
             [worker: RepairProjectSnapshotFindingWorker]
             |> all_enqueued()
             |> Enum.filter(&(&1.args["action_id"] == action.id))

    assert job.args["contract_version"] == 1

    assert [listed] = Versioning.list_project_snapshot_reconciliation_repairs(completed.id)
    assert listed.id == action.id

    job
    |> Ecto.Changeset.change(
      state: "discarded",
      attempt: job.max_attempts,
      discarded_at: %{TimeHelpers.now() | microsecond: {0, 6}}
    )
    |> Repo.update!()

    assert {:ok, %{actions: [%{id: repeated_id}]}} =
             Versioning.plan_project_snapshot_reconciliation_repairs(completed.id, limit: 1)

    assert repeated_id == action.id

    assert Repo.aggregate(
             from(job in Oban.Job,
               where:
                 job.worker == "Storyarn.Workers.RepairProjectSnapshotFindingWorker" and
                   fragment("(?->>'action_id')::bigint = ?", job.args, ^action.id)
             ),
             :count
           ) == 1

    assert_raise Postgrex.Error, ~r/snapshot reconciliation repair action identity is immutable/, fn ->
      Repo.transaction(fn ->
        action
        |> Ecto.Changeset.change(subject_fingerprint: String.duplicate("f", 64))
        |> Repo.update!()
      end)
    end

    assert_raise Postgrex.Error, ~r/snapshot reconciliation repair actions cannot be deleted/, fn ->
      Repo.transaction(fn -> Repo.delete!(action) end)
    end

    assert_raise Postgrex.Error, ~r/snapshot reconciliation repair actions cannot be truncated/, fn ->
      Repo.transaction(fn -> Repo.query!("TRUNCATE project_snapshot_reconciliation_repair_actions") end)
    end
  end

  test "missing and corrupt ready objects are reverified and degrade only integrity" do
    {_user, _project, missing_snapshot} = ready_snapshot!()
    missing_identity = snapshot_identity(missing_snapshot)
    assert :ok = Storage.delete(snapshot_payload_key(missing_snapshot))

    {_user, _project, corrupt_snapshot} = ready_snapshot!()
    corrupt_identity = snapshot_identity(corrupt_snapshot)
    corrupt_key = snapshot_payload_key(corrupt_snapshot)
    assert {:ok, payload} = Storage.download(corrupt_key)
    <<first, rest::binary>> = payload
    corrupt_payload = <<Bitwise.bxor(first, 1), rest::binary>>

    assert {:ok, _url} =
             Storage.upload(corrupt_key, corrupt_payload, snapshot_payload_content_type(corrupt_snapshot))

    run = completed_run!()
    {missing_finding, missing_action} = finding_action!(run, "ready_object_missing", missing_snapshot.id)
    {_corrupt_finding, corrupt_action} = finding_action!(run, "ready_object_corrupt", corrupt_snapshot.id)

    assert missing_finding.accounting_generation == missing_snapshot.accounting_generation

    attach_repair_telemetry!()

    assert {:ok, :repaired} =
             Versioning.perform_project_snapshot_reconciliation_repair(missing_action.id)

    assert {:ok, :repaired} =
             Versioning.perform_project_snapshot_reconciliation_repair(corrupt_action.id)

    assert_snapshot_integrity(missing_snapshot.id, "missing", missing_identity)
    assert_snapshot_integrity(corrupt_snapshot.id, "corrupt", corrupt_identity)

    assert_receive {
      [:storyarn, :snapshot, :reconciliation, :repair, :stop],
      %{count: 1, bytes: 0},
      %{action: :mark_missing, outcome: :repaired}
    }

    assert_receive {
      [:storyarn, :snapshot, :reconciliation, :repair, :stop],
      %{count: 1, bytes: 0},
      %{action: :mark_corrupt, outcome: :repaired}
    }

    missing_finished = Repo.get!(ProjectSnapshotReconciliationRepairAction, missing_action.id)
    assert missing_finished.status == "repaired"
    assert missing_finished.attempt_count == 1
    assert missing_finished.result_code == "integrity_marked_missing"
    assert %DateTime{} = missing_finished.finished_at

    assert {:ok, :repaired} =
             Versioning.perform_project_snapshot_reconciliation_repair(missing_action.id)

    assert Repo.get!(ProjectSnapshotReconciliationRepairAction, missing_action.id).attempt_count == 1
    refute_receive {[:storyarn, :snapshot, :reconciliation, :repair, :stop], _, _}
  end

  test "ready-object verification streams outside the workspace lock and reads the manifest once" do
    {_user, project, snapshot} = ready_snapshot!()
    payload_key = snapshot_payload_key(snapshot)
    assert {:ok, manifest_json} = Storage.download(snapshot.manifest_storage_key)
    <<first, rest::binary>> = manifest_json
    corrupt_manifest = <<Bitwise.bxor(first, 1), rest::binary>>

    assert {:ok, _url} =
             Storage.upload(snapshot.manifest_storage_key, corrupt_manifest, "application/json")

    run = completed_run!()
    {_finding, action} = finding_action!(run, "ready_manifest_corrupt", snapshot.id)
    install_snapshot_read_switch_storage()

    parent = self()

    SnapshotReadSwitchStorage.observe_io(fn operation, key ->
      send(parent, {
        :snapshot_repair_io,
        operation,
        key,
        Billing.workspace_lock_held?(project.workspace_id)
      })
    end)

    SnapshotReadSwitchStorage.reset_counts()
    assert {:ok, :repaired} = Versioning.perform_project_snapshot_reconciliation_repair(action.id)

    manifest_key = snapshot.manifest_storage_key
    assert_receive {:snapshot_repair_io, :stat, ^manifest_key, false}
    assert_receive {:snapshot_repair_io, :stream_chunk, ^manifest_key, false}
    assert_receive {:snapshot_repair_io, :stat, ^payload_key, false}
    assert_receive {:snapshot_repair_io, :stream_chunk, ^payload_key, false}
    refute_receive {:snapshot_repair_io, _operation, _key, true}
    assert SnapshotReadSwitchStorage.stream_count(snapshot.manifest_storage_key) == 1
    assert SnapshotReadSwitchStorage.stream_count(payload_key) == 1
  end

  test "integrity repair revalidates snapshot state after provider I/O" do
    {_user, _project, snapshot} = ready_snapshot!()
    assert :ok = Storage.delete(snapshot_payload_key(snapshot))
    run = completed_run!()
    {_finding, action} = finding_action!(run, "ready_object_missing", snapshot.id)
    install_snapshot_read_switch_storage()

    SnapshotReadSwitchStorage.observe_io(fn operation, key ->
      if operation == :stat and key == snapshot_payload_key(snapshot) do
        snapshot.id
        |> then(&Repo.get!(ProjectSnapshot, &1))
        |> ProjectSnapshot.reconciliation_integrity_changeset("corrupt")
        |> Repo.update!()
      end
    end)

    assert {:ok, :resolved} = Versioning.perform_project_snapshot_reconciliation_repair(action.id)
    assert Repo.get!(ProjectSnapshot, snapshot.id).integrity_state == "corrupt"

    assert %ProjectSnapshotReconciliationRepairAction{
             status: "resolved",
             result_code: "integrity_finding_stale"
           } = Repo.get!(ProjectSnapshotReconciliationRepairAction, action.id)
  end

  test "v2 integrity repair revalidates archive identity after provider I/O" do
    {_user, _project, snapshot} = ready_snapshot!()
    assert snapshot.format_version == 2
    assert :ok = Storage.delete(snapshot.archive_storage_key)
    run = completed_run!()
    {_finding, action} = finding_action!(run, "ready_object_missing", snapshot.id)
    install_snapshot_read_switch_storage()
    changed_checksum = String.duplicate("f", 64)

    SnapshotReadSwitchStorage.observe_io(fn operation, key ->
      if operation == :stat and key == snapshot.archive_storage_key do
        snapshot.id
        |> then(&Repo.get!(ProjectSnapshot, &1))
        |> Ecto.Changeset.change(archive_checksum: changed_checksum)
        |> Repo.update!()
      end
    end)

    assert {:ok, :resolved} = Versioning.perform_project_snapshot_reconciliation_repair(action.id)

    assert %ProjectSnapshot{integrity_state: "verified", archive_checksum: ^changed_checksum} =
             Repo.get!(ProjectSnapshot, snapshot.id)

    assert %ProjectSnapshotReconciliationRepairAction{
             status: "resolved",
             result_code: "integrity_finding_stale"
           } = Repo.get!(ProjectSnapshotReconciliationRepairAction, action.id)
  end

  test "integrity repair fails closed when the provider namespace changes during inspection" do
    {_user, _project, snapshot} = ready_snapshot!()
    assert :ok = Storage.delete(snapshot_payload_key(snapshot))
    run = completed_run!()
    {_finding, action} = finding_action!(run, "ready_object_missing", snapshot.id)
    install_snapshot_read_switch_storage()

    SnapshotReadSwitchStorage.observe_io(fn operation, key ->
      if operation == :stat and key == snapshot_payload_key(snapshot) do
        SnapshotReadSwitchStorage.override_namespace_fingerprint(String.duplicate("f", 64))
      end
    end)

    assert {:ok, :manual} = Versioning.perform_project_snapshot_reconciliation_repair(action.id)
    assert Repo.get!(ProjectSnapshot, snapshot.id).integrity_state == "verified"

    assert %ProjectSnapshotReconciliationRepairAction{
             status: "manual",
             result_code: "provider_namespace_changed"
           } = Repo.get!(ProjectSnapshotReconciliationRepairAction, action.id)
  end

  test "a recurring finding receives a new action without reopening the prior outcome" do
    {_user, _project, snapshot} = ready_snapshot!()
    assert :ok = Storage.delete(snapshot_payload_key(snapshot))

    run_one = completed_run!()
    {finding_one, action_one} = finding_action!(run_one, "ready_object_missing", snapshot.id)
    assert {:ok, :repaired} = Versioning.perform_project_snapshot_reconciliation_repair(action_one.id)

    run_two = completed_run!()
    {finding_two, action_two} = finding_action!(run_two, "ready_object_missing", snapshot.id)

    assert finding_two.fingerprint == finding_one.fingerprint
    refute action_two.id == action_one.id
    listed = Versioning.list_project_snapshot_reconciliation_repairs(run_two.id)
    assert Enum.any?(listed, &(&1.id == action_two.id))
    refute Enum.any?(listed, &(&1.id == action_one.id))
    assert Repo.get!(ProjectSnapshotReconciliationRepairAction, action_one.id).status == "repaired"
  end

  test "a failed action does not suppress the same finding in a later run" do
    {_user, _project, snapshot} = ready_snapshot!()
    assert :ok = Storage.delete(snapshot_payload_key(snapshot))

    run_one = completed_run!()
    {finding_one, action_one} = finding_action!(run_one, "ready_object_missing", snapshot.id)

    assert {:error, :provider_unavailable} =
             ProjectSnapshotReconciliationRepair.perform_with_lock(action_one.id, fn _name, _callback ->
               {:error, :provider_unavailable}
             end)

    assert {:ok, :failed} =
             Versioning.fail_project_snapshot_reconciliation_repair(action_one.id, :provider_unavailable)

    run_two = completed_run!()
    {finding_two, action_two} = finding_action!(run_two, "ready_object_missing", snapshot.id)

    assert finding_two.fingerprint == finding_one.fingerprint
    refute action_two.id == action_one.id
    listed = Versioning.list_project_snapshot_reconciliation_repairs(run_two.id)
    assert Enum.any?(listed, &(&1.id == action_two.id))
    refute Enum.any?(listed, &(&1.id == action_one.id))
    assert Repo.get!(ProjectSnapshotReconciliationRepairAction, action_one.id).status == "failed"
  end

  test "an object restored after inspection resolves the finding without degrading the snapshot" do
    {_user, _project, snapshot} = ready_snapshot!()
    payload_key = snapshot_payload_key(snapshot)
    assert {:ok, payload} = Storage.download(payload_key)
    assert :ok = Storage.delete(payload_key)

    run = completed_run!()
    {_finding, action} = finding_action!(run, "ready_object_missing", snapshot.id)

    assert {:ok, _url} = Storage.upload(payload_key, payload, snapshot_payload_content_type(snapshot))
    attach_repair_telemetry!()
    assert {:ok, :resolved} = Versioning.perform_project_snapshot_reconciliation_repair(action.id)

    assert_receive {
      [:storyarn, :snapshot, :reconciliation, :repair, :stop],
      %{count: 1, bytes: 0},
      %{action: :mark_missing, outcome: :resolved}
    }

    assert Repo.get!(ProjectSnapshot, snapshot.id).integrity_state == "verified"

    finished = Repo.get!(ProjectSnapshotReconciliationRepairAction, action.id)
    assert finished.status == "resolved"
    assert finished.result_code == "storage_object_now_verified"
  end

  test "ambiguous storage remains untouched and is recorded for manual review" do
    user = user_fixture()
    project = project_fixture(user)
    prefix = SnapshotArchiveStorage.staging_prefix(project.id, "UNOWNEDTEMP00001")
    storage_key = SnapshotArchiveStorage.archive_key(prefix)

    assert {:ok, _url} = Storage.upload(storage_key, "ambiguous", "application/json")
    run = completed_run!()
    {finding, action} = finding_action!(run, "ambiguous_storage_object")

    assert finding.storage_key == storage_key
    assert action.action_kind == "report_only"
    attach_repair_telemetry!()
    assert {:ok, :manual} = Versioning.perform_project_snapshot_reconciliation_repair(action.id)
    assert {:ok, "ambiguous"} = Storage.download(storage_key)

    assert_receive {
      [:storyarn, :snapshot, :reconciliation, :repair, :stop],
      %{count: 1, bytes: 0},
      %{action: :report_only, outcome: :manual}
    }

    finished = Repo.get!(ProjectSnapshotReconciliationRepairAction, action.id)
    assert finished.status == "manual"
    assert finished.result_code == "manual_review_ambiguous_storage_object"
  end

  test "an abandoned temporary object remains untouched for manual review" do
    {_user, _project, snapshot} = ready_snapshot!()
    staging_prefix = String.replace(snapshot.object_prefix, "/ready/", "/staging/")
    storage_key = staging_prefix <> "/orphan.bin"

    assert {:ok, _url} = Storage.upload(storage_key, "orphan", "application/json")
    run = completed_run!()
    {finding, action} = finding_action!(run, "abandoned_temporary_object", snapshot.id)

    assert finding.storage_key == storage_key
    assert finding.storage_reservation_id_snapshot == snapshot.storage_reservation_id
    assert finding.lifecycle_generation == snapshot.lifecycle_generation
    assert finding.accounting_generation == snapshot.accounting_generation
    assert action.action_kind == "report_only"

    # The immutable finding cannot prove that a same-key replacement is still
    # abandoned, even when its observable size is unchanged.
    assert {:ok, _url} = Storage.upload(storage_key, "change", "application/json")
    assert {:ok, :manual} = Versioning.perform_project_snapshot_reconciliation_repair(action.id)

    finished = Repo.get!(ProjectSnapshotReconciliationRepairAction, action.id)
    assert finished.status == "manual"
    assert finished.result_code == "manual_review_abandoned_temporary_object"
    assert {:ok, "change"} = Storage.download(storage_key)
  end

  test "an exact expired build delegates settlement to the lifecycle primitive" do
    {snapshot, finding, action} = expired_build_action!()

    assert finding.details["reason"] == "owning_job_discarded"
    attach_repair_telemetry!()
    assert {:ok, :repaired} = Versioning.perform_project_snapshot_reconciliation_repair(action.id)

    assert_receive {
      [:storyarn, :snapshot, :reconciliation, :repair, :stop],
      %{count: 1, bytes: expected_size_bytes},
      %{action: :cleanup_expired_build, outcome: :repaired}
    }

    assert expected_size_bytes == finding.expected_size_bytes

    refute Repo.get(ProjectSnapshot, snapshot.id)
    assert Repo.get!(StorageReservation, snapshot.storage_reservation_id).status == "released"

    assert %SnapshotCleanupIntent{} =
             Repo.get_by!(SnapshotCleanupIntent, project_snapshot_id_snapshot: snapshot.id)

    assert Repo.get!(ProjectSnapshotReconciliationRepairAction, action.id).result_code ==
             "expired_build_cleanup_scheduled"
  end

  test "expired-build repair rejects provider namespace drift before lifecycle mutation" do
    {snapshot, _finding, action} = expired_build_action!()
    install_snapshot_read_switch_storage()

    assert {:ok, expected_namespace} = Storage.namespace_fingerprint()
    different_namespace = String.duplicate("f", 64)
    refute different_namespace == expected_namespace

    reservation_before = Repo.get!(StorageReservation, snapshot.storage_reservation_id)
    cleanup_request_count = Repo.aggregate(StorageCleanupRequest, :count)

    SnapshotReadSwitchStorage.observe_namespace(fn
      ^expected_namespace ->
        SnapshotReadSwitchStorage.override_namespace_fingerprint(different_namespace)

      _value ->
        :ok
    end)

    assert {:ok, :manual} = Versioning.perform_project_snapshot_reconciliation_repair(action.id)

    assert %ProjectSnapshot{} = Repo.get(ProjectSnapshot, snapshot.id)
    assert Repo.get!(StorageReservation, snapshot.storage_reservation_id) == reservation_before
    assert Repo.aggregate(StorageCleanupRequest, :count) == cleanup_request_count
    refute Repo.get_by(SnapshotCleanupIntent, project_snapshot_id_snapshot: snapshot.id)

    assert %ProjectSnapshotReconciliationRepairAction{
             status: "manual",
             result_code: "provider_namespace_changed"
           } = Repo.get!(ProjectSnapshotReconciliationRepairAction, action.id)
  end

  test "an exact partial expired-build commit is recognized without settling unrelated state" do
    {snapshot, finding, action} = expired_build_action!()

    assert [candidate] =
             Versioning.list_expired_project_snapshot_build_candidates(TimeHelpers.now(),
               after_id: snapshot.id - 1,
               through_id: snapshot.id,
               limit: 1
             )

    assert {:ok, %SnapshotCleanupIntent{} = intent} =
             Versioning.delete_expired_project_snapshot_build_candidate(candidate)

    reservation = Repo.get!(StorageReservation, snapshot.storage_reservation_id)
    request = Repo.get!(StorageCleanupRequest, intent.cleanup_request_id)
    assert {:ok, namespace} = Storage.namespace_fingerprint()
    assert reservation.generation == finding.reservation_generation + 1
    assert reservation.cleanup_status == "not_required"
    assert reservation.cleanup_reference == "storage_not_started:#{reservation.storage_namespace}"
    assert is_nil(reservation.cleanup_inventory_digest)
    assert is_nil(reservation.cleanup_inventory_count)
    assert intent.deletion_generation == finding.lifecycle_generation + 1
    assert intent.ready_prefix == finding.object_prefix
    assert intent.provider_namespace_fingerprint == namespace
    assert request.provider_namespace_fingerprint == namespace
    assert request.storage_keys == intent.storage_keys

    assert {:ok, :repaired} = Versioning.perform_project_snapshot_reconciliation_repair(action.id)

    refute Repo.get(ProjectSnapshot, snapshot.id)
    assert Repo.get!(StorageReservation, snapshot.storage_reservation_id).status == "released"

    assert %SnapshotCleanupIntent{project_snapshot_id_snapshot: snapshot_id} =
             Repo.get_by!(SnapshotCleanupIntent, project_snapshot_id_snapshot: snapshot.id)

    assert snapshot_id == snapshot.id

    assert Repo.get!(ProjectSnapshotReconciliationRepairAction, action.id).result_code ==
             "expired_build_cleanup_already_scheduled"
  end

  test "changed expired-build evidence cannot release the reservation or create cleanup" do
    {snapshot, _finding, action} = expired_build_action!()

    snapshot.build_job_id
    |> then(&Repo.get!(Oban.Job, &1))
    |> Ecto.Changeset.change(state: "available", discarded_at: nil)
    |> Repo.update!()

    assert {:ok, :manual} = Versioning.perform_project_snapshot_reconciliation_repair(action.id)
    assert Repo.get!(StorageReservation, snapshot.storage_reservation_id).status == "active"
    assert %ProjectSnapshot{} = Repo.get(ProjectSnapshot, snapshot.id)
    refute Repo.get_by(SnapshotCleanupIntent, project_snapshot_id_snapshot: snapshot.id)

    assert Repo.get!(ProjectSnapshotReconciliationRepairAction, action.id).result_code ==
             "expired_build_no_longer_repairable"
  end

  test "failed finalization remains manual without exact expired-build proof" do
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

    run = completed_run!()
    {finding, action} = finding_action!(run, "failed_snapshot_finalization", snapshot.id)

    assert finding.error_code == "publication_claim_poisoned"
    assert action.action_kind == "cleanup_expired_build"
    assert {:ok, :manual} = Versioning.perform_project_snapshot_reconciliation_repair(action.id)
    assert Repo.get!(StorageReservation, reservation.id).status == "active"
    assert %ProjectSnapshot{} = Repo.get(ProjectSnapshot, snapshot.id)
    refute Repo.get_by(SnapshotCleanupIntent, project_snapshot_id_snapshot: snapshot.id)
  end

  test "a terminal cleanup failure is replayed through the existing fenced lifecycle primitive" do
    {user, project, snapshot} = ready_snapshot!()

    assert {:ok, intent} =
             Versioning.delete_project_snapshot(user_scope_fixture(user), project, snapshot.id)

    assert {:ok, :terminal} =
             process_cleanup_until_boundary(intent.id,
               delete_fun: fn keys -> {:error, keys} end,
               final_attempt?: true
             )

    run = completed_run!()
    {finding, action} = finding_action!(run, "terminal_cleanup_failure", snapshot.id)

    assert finding.cleanup_intent_id_snapshot == intent.id
    assert action.action_kind == "replay_cleanup"
    assert {:ok, :repaired} = Versioning.perform_project_snapshot_reconciliation_repair(action.id)

    replayed = Repo.get!(SnapshotCleanupIntent, intent.id)
    assert replayed.status == "retrying"
    assert is_nil(replayed.terminal_at)

    finished = Repo.get!(ProjectSnapshotReconciliationRepairAction, action.id)
    assert finished.status == "repaired"
    assert finished.result_code == "cleanup_intent_replayed"
  end

  test "a terminal cleanup without an error code remains exact and requires manual review" do
    {user, project, snapshot} = ready_snapshot!()

    assert {:ok, intent} =
             Versioning.delete_project_snapshot(user_scope_fixture(user), project, snapshot.id)

    assert {:ok, :terminal} =
             process_cleanup_until_boundary(intent.id,
               delete_fun: fn keys -> {:error, keys} end,
               final_attempt?: true
             )

    intent.id
    |> then(&Repo.get!(SnapshotCleanupIntent, &1))
    |> Ecto.Changeset.change(last_error_code: nil)
    |> Repo.update!()

    run = completed_run!()
    {finding, action} = finding_action!(run, "terminal_cleanup_failure", snapshot.id)

    assert is_nil(finding.error_code)

    assert {:ok, {:manual_repair_required, "missing_error_code"}} =
             ProjectSnapshotLifecycle.cleanup_operator_action(intent.id)

    assert {:ok, :manual} = Versioning.perform_project_snapshot_reconciliation_repair(action.id)
    assert Repo.get!(SnapshotCleanupIntent, intent.id).status == "terminal"

    assert %ProjectSnapshotReconciliationRepairAction{
             status: "manual",
             result_code: "cleanup_intent_manual_repair_required"
           } = Repo.get!(ProjectSnapshotReconciliationRepairAction, action.id)
  end

  test "an exact active cleanup replay completes a repair action after a partial commit" do
    {user, project, snapshot} = ready_snapshot!()

    assert {:ok, intent} =
             Versioning.delete_project_snapshot(user_scope_fixture(user), project, snapshot.id)

    assert {:ok, :terminal} =
             process_cleanup_until_boundary(intent.id,
               delete_fun: fn keys -> {:error, keys} end,
               final_attempt?: true
             )

    run = completed_run!()
    {finding, action} = finding_action!(run, "terminal_cleanup_failure", snapshot.id)

    assert {:ok, %SnapshotCleanupIntent{status: "retrying"}} =
             ProjectSnapshotLifecycle.replay_terminal_cleanup_intent(
               intent.id,
               cleanup_replay_expectations(finding)
             )

    replay_job_ids = cleanup_replay_job_ids(intent.id)
    assert length(replay_job_ids) == 1

    assert {:ok, :repaired} = Versioning.perform_project_snapshot_reconciliation_repair(action.id)

    assert %ProjectSnapshotReconciliationRepairAction{
             status: "repaired",
             result_code: "cleanup_intent_already_active"
           } = Repo.get!(ProjectSnapshotReconciliationRepairAction, action.id)

    assert Repo.get!(SnapshotCleanupIntent, intent.id).status == "retrying"
    assert cleanup_replay_job_ids(intent.id) == replay_job_ids
  end

  test "changed cleanup evidence resolves stale repair without replaying it" do
    {user, project, snapshot} = ready_snapshot!()

    assert {:ok, intent} =
             Versioning.delete_project_snapshot(user_scope_fixture(user), project, snapshot.id)

    assert {:ok, :terminal} =
             process_cleanup_until_boundary(intent.id,
               delete_fun: fn keys -> {:error, keys} end,
               final_attempt?: true
             )

    run = completed_run!()
    {_finding, action} = finding_action!(run, "terminal_cleanup_failure", snapshot.id)

    assert {:ok, %SnapshotCleanupIntent{}} =
             Versioning.replay_terminal_project_snapshot_cleanup(intent.id)

    assert {:ok, :terminal} =
             process_cleanup_until_boundary(intent.id,
               delete_fun: fn keys -> {:error, keys} end,
               final_attempt?: true
             )

    assert {:ok, :resolved} = Versioning.perform_project_snapshot_reconciliation_repair(action.id)

    assert %ProjectSnapshotReconciliationRepairAction{
             status: "resolved",
             result_code: "cleanup_intent_changed"
           } = Repo.get!(ProjectSnapshotReconciliationRepairAction, action.id)

    assert Repo.get!(SnapshotCleanupIntent, intent.id).status == "terminal"
  end

  test "a still-owned cleanup namespace stays terminal and requires manual review" do
    {user, project, snapshot} = ready_snapshot!()

    assert {:ok, intent} =
             Versioning.delete_project_snapshot(user_scope_fixture(user), project, snapshot.id)

    assert {:ok, namespace_owner} =
             Versioning.request_full_project_snapshot(user_scope_fixture(user), project, %{
               idempotency_key: Ecto.UUID.generate()
             })

    namespace_owner
    |> Ecto.Changeset.change(
      object_prefix: intent.ready_prefix,
      archive_storage_key: "#{intent.ready_prefix}/snapshot.zip",
      manifest_storage_key: "#{intent.ready_prefix}/manifest.json"
    )
    |> Repo.update!()

    assert {:ok, :terminal} =
             Versioning.process_project_snapshot_cleanup_intent(intent.id, final_attempt?: true)

    run = completed_run!()
    {_finding, action} = finding_action!(run, "terminal_cleanup_failure", snapshot.id)

    assert {:ok, :manual} = Versioning.perform_project_snapshot_reconciliation_repair(action.id)

    assert %SnapshotCleanupIntent{status: "terminal"} = Repo.get!(SnapshotCleanupIntent, intent.id)

    assert %ProjectSnapshotReconciliationRepairAction{
             status: "manual",
             result_code: "cleanup_intent_namespace_still_owned"
           } = Repo.get!(ProjectSnapshotReconciliationRepairAction, action.id)
  end

  test "workspace deletion resolves stale integrity and expired-build actions" do
    {user, project, snapshot} = ready_snapshot!()
    assert :ok = Storage.delete(snapshot_payload_key(snapshot))
    integrity_run = completed_run!()
    {_finding, integrity_action} = finding_action!(integrity_run, "ready_object_missing", snapshot.id)

    assert {:ok, _workspace} =
             Workspaces.delete_workspace(user_scope_fixture(user), project.workspace_id)

    assert {:ok, :resolved} =
             Versioning.perform_project_snapshot_reconciliation_repair(integrity_action.id)

    assert Repo.get!(ProjectSnapshotReconciliationRepairAction, integrity_action.id).result_code ==
             "workspace_no_longer_exists"

    {expired_snapshot, _finding, expired_action} = expired_build_action!()

    expired_workspace_id =
      Repo.get!(StorageReservation, expired_snapshot.storage_reservation_id).workspace_id_snapshot

    assert [candidate] =
             Versioning.list_expired_project_snapshot_build_candidates(TimeHelpers.now(),
               after_id: expired_snapshot.id - 1,
               through_id: expired_snapshot.id,
               limit: 1
             )

    assert {:ok, %SnapshotCleanupIntent{}} =
             Versioning.delete_expired_project_snapshot_build_candidate(candidate)

    expired_workspace = Workspaces.get_workspace!(expired_workspace_id)
    expired_owner = Repo.get!(Storyarn.Accounts.User, expired_workspace.owner_id)

    assert {:ok, _workspace} =
             Workspaces.delete_workspace(
               user_scope_fixture(expired_owner),
               expired_workspace_id
             )

    assert {:ok, :resolved} = Versioning.perform_project_snapshot_reconciliation_repair(expired_action.id)

    assert Repo.get!(ProjectSnapshotReconciliationRepairAction, expired_action.id).result_code ==
             "workspace_no_longer_exists"
  end

  test "repair worker exposes only bounded exception metadata to Oban" do
    private_message = "private repair for Private Project/private-snapshot.zip/projects/42/object"

    job = %Oban.Job{
      args: %{"action_id" => 1, "contract_version" => 1},
      attempt: 1,
      max_attempts: 5
    }

    retry_log =
      capture_log(fn ->
        assert {:error, {:snapshot_reconciliation_repair_exception, RuntimeError}} =
                 RepairProjectSnapshotFindingWorker.perform_action(job, fn _action_id ->
                   raise private_message
                 end)
      end)

    refute retry_log =~ private_message
  end

  test "repair worker retries bounded stops and persists terminal evidence on the final attempt" do
    {_snapshot, _finding, action} = expired_build_action!()

    action =
      action
      |> ProjectSnapshotReconciliationRepairAction.attempt_changeset()
      |> Repo.update!()

    job = %Oban.Job{
      args: %{"action_id" => action.id, "contract_version" => 1},
      attempt: 1,
      max_attempts: 5
    }

    private_exit = {:database_connection_timeout, "private-project/private-exit.zip"}
    private_throw = {:provider_cancelled, "projects/42/private-storage-key"}

    retry_result =
      RepairProjectSnapshotFindingWorker.perform_action(job, fn _action_id ->
        exit(private_exit)
      end)

    assert retry_result == {:error, {:snapshot_reconciliation_repair_stopped, :exit}}
    assert Repo.get!(ProjectSnapshotReconciliationRepairAction, action.id).status == "pending"

    terminal_result =
      RepairProjectSnapshotFindingWorker.perform_action(%{job | attempt: job.max_attempts}, fn _action_id ->
        throw(private_throw)
      end)

    assert terminal_result == :ok
    refute inspect({retry_result, terminal_result}) =~ "private-project"
    refute inspect({retry_result, terminal_result}) =~ "private-storage-key"

    failed = Repo.get!(ProjectSnapshotReconciliationRepairAction, action.id)
    assert failed.status == "failed"
    assert failed.result_code == "snapshot_reconciliation_repair_stopped"
  end

  defp finding_action!(run, category, snapshot_id \\ nil) do
    finding =
      run.id
      |> Versioning.list_project_snapshot_reconciliation_findings(limit: 500)
      |> Enum.find(fn finding ->
        finding.category == category and
          (is_nil(snapshot_id) or finding.project_snapshot_id_snapshot == snapshot_id)
      end)

    assert %ProjectSnapshotReconciliationFinding{} = finding
    assert {:ok, %{actions: actions}} = Versioning.plan_project_snapshot_reconciliation_repairs(run.id, limit: 100)

    action = Enum.find(actions, &(&1.source_finding_id == finding.id))
    assert %ProjectSnapshotReconciliationRepairAction{} = action
    {finding, action}
  end

  defp attach_repair_telemetry! do
    handler_id = "snapshot-repair-stop-#{System.unique_integer([:positive])}"
    parent = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:storyarn, :snapshot, :reconciliation, :repair, :stop],
        fn event, measurements, metadata, pid -> send(pid, {event, measurements, metadata}) end,
        parent
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  defp cleanup_replay_expectations(finding) do
    %{
      cleanup_intent_id_snapshot: finding.cleanup_intent_id_snapshot,
      workspace_id_snapshot: finding.workspace_id_snapshot,
      project_id_snapshot: finding.project_id_snapshot,
      project_snapshot_id_snapshot: finding.project_snapshot_id_snapshot,
      lifecycle_generation: finding.lifecycle_generation,
      object_prefix: finding.object_prefix,
      expected_size_bytes: finding.expected_size_bytes,
      error_code: finding.error_code,
      reason: finding.details["reason"],
      retry_count: finding.details["retry_count"],
      processing_generation: finding.details["processing_generation"]
    }
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

  defp cleanup_replay_job_ids(intent_id) do
    [worker: CleanupProjectSnapshotWorker]
    |> all_enqueued()
    |> Enum.filter(fn job ->
      job.args["intent_id"] == intent_id and is_binary(job.args["replay_token"])
    end)
    |> Enum.map(& &1.id)
  end

  defp expired_build_action! do
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

    run = completed_run!()
    {finding, action} = finding_action!(run, "stale_reservation", snapshot.id)
    assert action.action_kind == "cleanup_expired_build"
    {snapshot, finding, action}
  end

  defp ready_snapshot! do
    user = user_fixture()
    project = project_fixture(user)

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

  defp completed_run! do
    assert {:ok, run} = start_run()
    completed = advance_until_terminal(run.id, run.cursor_generation)
    assert completed.status == "completed"
    completed
  end

  # Exact multipart cleanup performs at most one provider operation per
  # delivery. Drive only immediate continuations and fail if the FSM loops.
  defp process_cleanup_until_boundary(intent_id, opts, attempts_left \\ 100)

  defp process_cleanup_until_boundary(intent_id, opts, attempts_left) when attempts_left > 0 do
    case Versioning.process_project_snapshot_cleanup_intent(intent_id, opts) do
      {:ok, {:deferred, 1}} -> process_cleanup_until_boundary(intent_id, opts, attempts_left - 1)
      result -> result
    end
  end

  defp process_cleanup_until_boundary(_intent_id, _opts, 0),
    do: flunk("exact multipart cleanup did not reach a durable delivery boundary")

  defp start_run do
    Storyarn.SnapshotReconciliationTestHelpers.start_run(
      max_objects_per_step: 10,
      provider_page_size: 100,
      max_provider_objects: 10_000,
      max_provider_bytes: 1024 * 1024 * 1024
    )
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

  defp snapshot_identity(snapshot) do
    Map.take(snapshot, [
      :lifecycle_state,
      :lifecycle_generation,
      :accounting_generation,
      :archive_storage_key,
      :archive_size_bytes,
      :archive_checksum,
      :manifest_checksum,
      :manifest_storage_key,
      :object_prefix,
      :accounted_size_bytes
    ])
  end

  defp snapshot_payload_key(%ProjectSnapshot{archive_storage_key: key}), do: key

  defp snapshot_payload_content_type(%ProjectSnapshot{}), do: "application/zip"

  defp assert_snapshot_integrity(snapshot_id, integrity_state, identity) do
    snapshot = Repo.get!(ProjectSnapshot, snapshot_id)
    assert snapshot.integrity_state == integrity_state
    assert snapshot_identity(snapshot) == identity
  end
end
