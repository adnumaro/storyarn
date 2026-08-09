defmodule Storyarn.Versioning.ProjectSnapshotReconciliationRepairRecoveryTest do
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  alias Storyarn.Assets.Storage
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Versioning
  alias Storyarn.Versioning.ProjectSnapshotReconciliationFinding
  alias Storyarn.Versioning.ProjectSnapshotReconciliationRepair
  alias Storyarn.Versioning.ProjectSnapshotReconciliationRepairAction
  alias Storyarn.Workers.ReconcileProjectSnapshotRepairWorker
  alias Storyarn.Workers.RepairProjectSnapshotFindingWorker

  setup do
    original_storage = Application.fetch_env!(:storyarn, :storage)

    isolated_upload_dir =
      original_storage
      |> Keyword.fetch!(:upload_dir)
      |> Path.join("snapshot-repair-recovery-#{System.unique_integer([:positive])}")

    File.mkdir_p!(isolated_upload_dir)
    Application.put_env(:storyarn, :storage, Keyword.put(original_storage, :upload_dir, isolated_upload_dir))

    on_exit(fn ->
      Application.put_env(:storyarn, :storage, original_storage)
      File.rm_rf!(isolated_upload_dir)
    end)

    :ok
  end

  test "integrity classification only degrades positively identified corruption" do
    assert {:ok, :missing} = ProjectSnapshotReconciliationRepair.classify_integrity_result({:error, :enoent})

    assert {:ok, :corrupt} =
             ProjectSnapshotReconciliationRepair.classify_integrity_result(
               {:error, {:snapshot_manifest_validation_failed, :invalid_snapshot_manifest}}
             )

    assert {:ok, :corrupt} =
             ProjectSnapshotReconciliationRepair.classify_integrity_result(
               {:error,
                {:snapshot_inspection_object_failed,
                 %{reason: {:snapshot_object_checksum_mismatch, "expected", "actual"}}}}
             )

    assert {:error, {:http_error, 503, "private provider response"}} =
             ProjectSnapshotReconciliationRepair.classify_integrity_result(
               {:error, {:http_error, 503, "private provider response"}}
             )

    assert {:error, :unknown_provider_failure} =
             ProjectSnapshotReconciliationRepair.classify_integrity_result({:error, :unknown_provider_failure})
  end

  test "repair and list option parsing fails closed for malformed lists" do
    assert ProjectSnapshotReconciliationRepair.repair_page_limit() == 100
    assert Versioning.project_snapshot_reconciliation_repair_page_limit() == 100

    for invalid <- [[:malformed], [{"limit", 1}], :not_a_list] do
      assert {:error, :invalid_snapshot_reconciliation_repair_options} =
               ProjectSnapshotReconciliationRepair.plan(1, invalid)

      assert [] == ProjectSnapshotReconciliationRepair.list_actions(1, invalid)
    end
  end

  test "a missing delivery is re-enqueued with exact identity" do
    action = action_fixture!()

    assert {:ok, page} = recover(action)
    assert page.reenqueued_count == 1
    assert page.failure_count == 0

    assert [%Oban.Job{state: "available", max_attempts: 5} = job] = exact_jobs(action)
    assert job.queue == "snapshots_maintenance"
  end

  test "a stale executing delivery is rescued without resetting its attempts" do
    action = action_fixture!()
    job = executing_delivery!(action, attempt: 3, attempted_seconds_ago: 1_200)

    assert {:ok, %{requeued_count: 1, failure_count: 0}} = recover(action)
    assert %Oban.Job{state: "available", attempt: 3, discarded_at: nil} = Repo.get!(Oban.Job, job.id)
    assert Enum.map(exact_jobs(action), & &1.id) == [job.id]
  end

  test "a fresh executing delivery is never stolen" do
    action = action_fixture!()
    job = executing_delivery!(action, attempt: 2, attempted_seconds_ago: 60)

    assert {:ok, %{already_active_count: 1, failure_count: 0}} = recover(action)
    assert %Oban.Job{state: "executing", attempt: 2} = Repo.get!(Oban.Job, job.id)
  end

  test "wrong worker queue and args are untouched while exact delivery is restored" do
    action = action_fixture!()

    wrong_queue =
      action
      |> repair_job_changeset()
      |> Ecto.Changeset.put_change(:queue, "snapshots")
      |> Repo.insert!()

    wrong_args =
      %{action_id: action.id, contract_version: 99}
      |> RepairProjectSnapshotFindingWorker.new()
      |> Repo.insert!()

    assert {:ok, %{reenqueued_count: 1, failure_count: 0}} = recover(action)
    assert Repo.get!(Oban.Job, wrong_queue.id).state == "available"
    assert Repo.get!(Oban.Job, wrong_args.id).state == "available"
    assert length(exact_jobs(action)) == 1
  end

  test "an exhausted stale delivery terminalizes the durable action without a new cycle" do
    action = action_fixture!()
    job = executing_delivery!(action, attempt: 5, max_attempts: 5, attempted_seconds_ago: 1_200)
    attach_repair_telemetry!()

    assert {:ok, %{terminalized_count: 1, failure_count: 0}} = recover(action)
    assert %Oban.Job{state: "discarded"} = Repo.get!(Oban.Job, job.id)

    assert_receive {
      [:storyarn, :snapshot, :reconciliation, :repair, :stop],
      %{count: 1, bytes: 0},
      %{action: :report_only, outcome: :failed}
    }

    assert %ProjectSnapshotReconciliationRepairAction{
             status: "failed",
             result_code: "repair_delivery_exhausted",
             attempt_count: 1
           } = Repo.get!(ProjectSnapshotReconciliationRepairAction, action.id)

    assert exact_jobs(action) == []
  end

  test "an exhausted cancelled delivery terminalizes instead of starting a replacement" do
    action = action_fixture!()

    job =
      action
      |> repair_job_changeset(max_attempts: 5)
      |> Repo.insert!()
      |> Ecto.Changeset.change(
        state: "cancelled",
        attempt: 5,
        cancelled_at: %{TimeHelpers.now() | microsecond: {0, 6}}
      )
      |> Repo.update!()

    assert {:ok, %{terminalized_count: 1, failure_count: 0}} = recover(action)
    assert Repo.get!(Oban.Job, job.id).state == "cancelled"

    assert Repo.get!(ProjectSnapshotReconciliationRepairAction, action.id).result_code ==
             "repair_delivery_exhausted"

    assert exact_jobs(action) == []
  end

  test "a discarded delivery with budget is reused with its attempts intact" do
    action = action_fixture!()

    job =
      action
      |> repair_job_changeset(max_attempts: 5)
      |> Repo.insert!()
      |> Ecto.Changeset.change(
        state: "discarded",
        attempt: 3,
        discarded_at: %{TimeHelpers.now() | microsecond: {0, 6}}
      )
      |> Repo.update!()

    assert {:ok, %{requeued_count: 1, failure_count: 0}} = recover(action)
    assert %Oban.Job{state: "available", attempt: 3} = Repo.get!(Oban.Job, job.id)
  end

  test "a missing delivery receives only the action's remaining attempt budget" do
    action = action_fixture!()

    for _attempt <- 1..4 do
      assert {:error, :provider_unavailable} =
               ProjectSnapshotReconciliationRepair.perform_with_lock(action.id, fn _name, _callback ->
                 {:error, :provider_unavailable}
               end)
    end

    assert {:ok, %{reenqueued_count: 1, failure_count: 0}} = recover(action)
    assert [%Oban.Job{max_attempts: 1}] = exact_jobs(action)
  end

  test "a final session-lock failure records the attempt before terminal evidence" do
    action = action_fixture!()

    job = %Oban.Job{
      args: %{"action_id" => action.id, "contract_version" => 1},
      attempt: 5,
      max_attempts: 5
    }

    repair = fn action_id ->
      ProjectSnapshotReconciliationRepair.perform_with_lock(action_id, fn lock_name, _callback ->
        assert lock_name == "snapshot-reconciliation-repair:#{action.id}"
        {:error, :session_lock_timeout}
      end)
    end

    assert :ok = RepairProjectSnapshotFindingWorker.perform_action(job, repair)

    assert %ProjectSnapshotReconciliationRepairAction{
             status: "failed",
             result_code: "session_lock_timeout",
             attempt_count: 1
           } = Repo.get!(ProjectSnapshotReconciliationRepairAction, action.id)
  end

  test "provider failures retry within budget and terminalize without leaking provider details" do
    action = action_fixture!()
    private_body = "private bucket and object details"

    repair = fn action_id ->
      ProjectSnapshotReconciliationRepair.perform_with_lock(action_id, fn _lock_name, _callback ->
        {:error, {:http_error, 503, private_body}}
      end)
    end

    assert {:error, :snapshot_reconciliation_repair_failed} =
             RepairProjectSnapshotFindingWorker.perform_action(
               %Oban.Job{
                 args: %{"action_id" => action.id, "contract_version" => 1},
                 attempt: 1,
                 max_attempts: 5
               },
               repair
             )

    assert %ProjectSnapshotReconciliationRepairAction{status: "pending", attempt_count: 1} =
             Repo.get!(ProjectSnapshotReconciliationRepairAction, action.id)

    assert :ok =
             RepairProjectSnapshotFindingWorker.perform_action(
               %Oban.Job{
                 args: %{"action_id" => action.id, "contract_version" => 1},
                 attempt: 5,
                 max_attempts: 5
               },
               repair
             )

    finished = Repo.get!(ProjectSnapshotReconciliationRepairAction, action.id)
    assert finished.status == "failed"
    assert finished.attempt_count == 2
    assert finished.result_code == "http_error"
    refute inspect(finished) =~ private_body
  end

  test "the cron runner captures one high-watermark and schedules a bounded continuation" do
    parent = self()

    recover_page = fn opts ->
      send(parent, {:recover_page, opts})
      {:ok, %{complete?: false, failure_count: 0, next_after_id: 50}}
    end

    enqueue = fn changeset ->
      send(parent, {:continuation_args, Ecto.Changeset.get_field(changeset, :args)})
      {:ok, %Oban.Job{}}
    end

    assert :ok =
             ReconcileProjectSnapshotRepairWorker.perform_recovery(
               %Oban.Job{args: %{}},
               fn -> 75 end,
               recover_page,
               enqueue
             )

    assert_receive {:recover_page, [after_id: 0, through_id: 75, limit: 50]}
    assert_receive {:continuation_args, %{after_id: 50, through_id: 75}}
  end

  test "the cron runner retries a failed page without advancing its cursor" do
    parent = self()

    assert {:error, :snapshot_reconciliation_repair_recovery_failed} =
             ReconcileProjectSnapshotRepairWorker.perform_recovery(
               %Oban.Job{args: %{"after_id" => 10, "through_id" => 20}},
               fn -> flunk("continuation must retain its captured boundary") end,
               fn _opts -> {:ok, %{complete?: false, failure_count: 1, next_after_id: 15}} end,
               fn _changeset -> send(parent, :unexpected_continuation) end
             )

    refute_receive :unexpected_continuation
  end

  test "repair timeout, recovery margin, and cron cadence remain coupled" do
    assert RepairProjectSnapshotFindingWorker.recovery_after_seconds() == 15 * 60

    crontab =
      :storyarn
      |> Application.fetch_env!(Oban)
      |> Keyword.fetch!(:plugins)
      |> Enum.find_value(fn
        {Oban.Plugins.Cron, opts} -> Keyword.fetch!(opts, :crontab)
        _plugin -> nil
      end)

    assert {"*/15 * * * *", ReconcileProjectSnapshotRepairWorker} in crontab
  end

  defp recover(action) do
    ProjectSnapshotReconciliationRepair.recover_repair_delivery_page(
      through_id: action.id,
      limit: 1
    )
  end

  defp attach_repair_telemetry! do
    handler_id = "snapshot-repair-recovery-stop-#{System.unique_integer([:positive])}"
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

  defp action_fixture! do
    assert {:ok, namespace} = Storage.namespace_fingerprint()

    assert {:ok, run} =
             Versioning.start_project_snapshot_reconciliation(
               max_objects_per_step: 10,
               provider_page_size: 100,
               max_provider_objects: 10_000,
               max_provider_bytes: 1024 * 1024 * 1024
             )

    fingerprint =
      :sha256 |> :crypto.hash("repair-recovery-#{System.unique_integer([:positive])}") |> Base.encode16(case: :lower)

    finding =
      %ProjectSnapshotReconciliationFinding{}
      |> ProjectSnapshotReconciliationFinding.create_changeset(%{
        run_id: run.id,
        fingerprint: fingerprint,
        category: "ambiguous_storage_object",
        severity: "warning",
        details: %{}
      })
      |> Repo.insert!()

    completed = advance_until_terminal(run.id, run.cursor_generation)
    assert completed.status == "completed"

    %ProjectSnapshotReconciliationRepairAction{}
    |> ProjectSnapshotReconciliationRepairAction.plan_changeset(%{
      source_finding_id: finding.id,
      provider_namespace_fingerprint_snapshot: namespace,
      subject_fingerprint: finding.fingerprint,
      action_kind: "report_only"
    })
    |> Repo.insert!()
  end

  defp advance_until_terminal(run_id, generation, remaining \\ 20)

  defp advance_until_terminal(run_id, _generation, 0),
    do: flunk("snapshot reconciliation run ##{run_id} did not complete")

  defp advance_until_terminal(run_id, generation, remaining) do
    case Versioning.advance_project_snapshot_reconciliation(run_id, generation) do
      {:ok, status} when status in [:completed, :failed] ->
        Versioning.get_project_snapshot_reconciliation_run(run_id)

      {:ok, status, next_generation} when status in [:continue, :stale] ->
        advance_until_terminal(run_id, next_generation, remaining - 1)

      unexpected ->
        flunk("unexpected reconciliation result: #{inspect(unexpected)}")
    end
  end

  defp executing_delivery!(action, opts) do
    attempt = Keyword.fetch!(opts, :attempt)
    max_attempts = Keyword.get(opts, :max_attempts, 5)
    attempted_seconds_ago = Keyword.fetch!(opts, :attempted_seconds_ago)

    action
    |> repair_job_changeset(max_attempts: max_attempts)
    |> Repo.insert!()
    |> Ecto.Changeset.change(
      state: "executing",
      attempt: attempt,
      attempted_at: %{DateTime.add(TimeHelpers.now(), -attempted_seconds_ago, :second) | microsecond: {0, 6}}
    )
    |> Repo.update!()
  end

  defp repair_job_changeset(action, opts \\ []) do
    RepairProjectSnapshotFindingWorker.new(
      %{action_id: action.id, contract_version: action.contract_version},
      opts
    )
  end

  defp exact_jobs(action) do
    Repo.all(
      from(job in Oban.Job,
        where:
          job.worker == "Storyarn.Workers.RepairProjectSnapshotFindingWorker" and
            job.queue == "snapshots_maintenance" and
            job.args ==
              ^%{
                "action_id" => action.id,
                "contract_version" => action.contract_version
              } and
            job.state in ["available", "scheduled", "executing", "retryable"],
        order_by: [asc: job.id]
      )
    )
  end
end
