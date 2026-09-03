defmodule Storyarn.Projects.Versioning.ProjectSnapshotReconciliationMetricsTest do
  use Storyarn.DataCase, async: true

  import ExUnit.CaptureLog

  alias Storyarn.Application, as: StoryarnApplication
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.Assets.Storage
  alias Storyarn.Projects.Versioning.ProjectSnapshotReconciliationFinding
  alias Storyarn.Projects.Versioning.ProjectSnapshotReconciliationMetrics
  alias Storyarn.Projects.Versioning.ProjectSnapshotReconciliationRun
  alias Storyarn.Repo

  @event [:storyarn, :snapshot, :reconciliation, :projection, :stop]

  test "poller is opt-in and starts with an immediate durable projection" do
    interval = to_timeout(minute: 15)

    assert ProjectSnapshotReconciliationMetrics.child_specs(
             enabled: false,
             oban_poll_interval: interval
           ) == []

    assert [%{id: ProjectSnapshotReconciliationMetrics, start: {:telemetry_poller, :start_link, [options]}}] =
             ProjectSnapshotReconciliationMetrics.child_specs(
               enabled: true,
               oban_poll_interval: interval
             )

    assert Keyword.fetch!(options, :period) == interval
    assert Keyword.fetch!(options, :init_delay) == 0
    assert Keyword.fetch!(options, :measurements) == [{ProjectSnapshotReconciliationMetrics, :emit, []}]
  end

  test "application starts the projection only after Repo and Oban" do
    operational_metrics_config =
      :storyarn
      |> Application.fetch_env!(:operational_metrics)
      |> Keyword.put(:enabled, true)

    children = StoryarnApplication.children(operational_metrics_config)

    repo_index = Enum.find_index(children, &(&1 == Repo))
    oban_index = Enum.find_index(children, &match?({Oban, _opts}, &1))
    projection_index = Enum.find_index(children, &match?(%{id: ProjectSnapshotReconciliationMetrics}, &1))

    assert is_integer(repo_index)
    assert is_integer(oban_index)
    assert is_integer(projection_index)
    assert repo_index < oban_index
    assert oban_index < projection_index
  end

  test "emits an observed unavailable snapshot when no completed run exists" do
    now = ~U[2026-09-02 20:00:00Z]
    attach_projection_handler()

    assert :ok = ProjectSnapshotReconciliationMetrics.emit_with(fn -> nil end, now)

    assert_receive {@event, measurements, %{}}
    assert measurements.success == 1
    assert measurements.failure_count == 0
    assert measurements.latest_completed_available == 0
    assert measurements.latest_completed_at_unix_seconds == 0
    assert measurements.observed_at_unix_seconds == DateTime.to_unix(now)
    assert measurements.finding_count == 0
    assert measurements.missing_ready_snapshot_count == 0
  end

  test "rehydrates the latest completed run for the configured provider namespace" do
    {:ok, namespace_fingerprint} = Storage.namespace_fingerprint()

    latest =
      insert_completed_run!(namespace_fingerprint, [
        %{
          category: "ambiguous_storage_object",
          severity: "warning",
          details: %{}
        }
      ])

    foreign_namespace_fingerprint =
      if namespace_fingerprint == String.duplicate("a", 64),
        do: String.duplicate("b", 64),
        else: String.duplicate("a", 64)

    _newer_foreign_namespace = insert_completed_run!(foreign_namespace_fingerprint, [])

    attach_projection_handler()

    assert :ok = ProjectSnapshotReconciliationMetrics.emit()

    assert_receive {@event, measurements, %{}}
    assert measurements.success == 1
    assert measurements.latest_completed_available == 1
    assert measurements.latest_completed_at_unix_seconds == DateTime.to_unix(latest.finished_at)
    assert measurements.finding_count == 1
    assert measurements.stale_reservation_bytes == 0
    assert measurements.orphan_object_bytes == 0
    assert measurements.missing_ready_snapshot_count == 0
    assert measurements.corrupt_ready_snapshot_count == 0
    assert measurements.terminal_cleanup_failure_count == 0
    assert measurements.terminal_cleanup_retry_count == 0

    refute Enum.any?(
             [:run_id, :workspace_id, :project_id, :snapshot_id, :storage_key, :provider_namespace_fingerprint],
             &Map.has_key?(measurements, &1)
           )
  end

  test "projects a one-row aggregate with distinct snapshots and safe retry counts" do
    {:ok, namespace_fingerprint} = Storage.namespace_fingerprint()

    findings = [
      %{category: "stale_reservation", severity: "warning", expected_size_bytes: 120, details: %{}},
      %{
        category: "abandoned_temporary_object",
        severity: "warning",
        observed_size_bytes: 45,
        details: %{}
      },
      ready_snapshot_finding("ready_manifest_missing", 101),
      ready_snapshot_finding("ready_object_missing", 101),
      ready_snapshot_finding("ready_manifest_corrupt", 202),
      ready_snapshot_finding("ready_object_corrupt", 202),
      cleanup_finding(301, 4),
      cleanup_finding(302, -9),
      cleanup_finding(303, "100")
    ]

    _run = insert_completed_run!(namespace_fingerprint, findings)
    attach_projection_handler()

    assert :ok = ProjectSnapshotReconciliationMetrics.emit()

    assert_receive {@event, measurements, %{}}
    assert measurements.finding_count == length(findings)
    assert measurements.stale_reservation_bytes == 120
    assert measurements.orphan_object_bytes == 45
    assert measurements.missing_ready_snapshot_count == 1
    assert measurements.corrupt_ready_snapshot_count == 1
    assert measurements.terminal_cleanup_failure_count == 3
    assert measurements.terminal_cleanup_retry_count == 4

    for measurement <- [
          :finding_count,
          :stale_reservation_bytes,
          :orphan_object_bytes,
          :missing_ready_snapshot_count,
          :corrupt_ready_snapshot_count,
          :terminal_cleanup_failure_count,
          :terminal_cleanup_retry_count
        ] do
      assert is_integer(Map.fetch!(measurements, measurement))
    end
  end

  test "projection failures expose neither exception messages nor telemetry identifiers" do
    private_message = "postgres://private-user:secret@private-host/database"
    attach_projection_handler()

    log =
      capture_log(fn ->
        assert :ok =
                 ProjectSnapshotReconciliationMetrics.emit_with(
                   fn -> raise private_message end,
                   ~U[2026-09-02 20:00:00Z]
                 )
      end)

    assert_receive {@event, %{success: 0, failure_count: 1}, %{}}
    assert log =~ "failure=exception"
    assert log =~ "exception_module=RuntimeError"
    refute log =~ private_message
    refute log =~ "private-user"
    refute log =~ "private-host"
  end

  defp attach_projection_handler do
    handler_id = "snapshot-reconciliation-projection-#{System.unique_integer([:positive])}"
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        @event,
        fn event, measurements, metadata, pid -> send(pid, {event, measurements, metadata}) end,
        test_pid
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  defp insert_completed_run!(namespace_fingerprint, findings) do
    run =
      %ProjectSnapshotReconciliationRun{}
      |> ProjectSnapshotReconciliationRun.create_changeset(%{
        provider_namespace_fingerprint: namespace_fingerprint,
        snapshot_high_watermark: 0,
        reservation_high_watermark: 0,
        claim_sequence_high_watermark: 0,
        cleanup_intent_high_watermark: 0,
        max_objects_per_step: 1,
        max_bytes_per_step: 128 * 1024 * 1024,
        max_findings: 10,
        provider_page_size: 10,
        max_provider_objects: 10,
        max_provider_bytes: 1024 * 1024 * 1024
      })
      |> Repo.insert!()

    Enum.each(findings, &insert_finding!(run, &1))

    Enum.reduce(
      ["stale_reservations", "publication_claims", "cleanup_intents", "provider_objects", "completed"],
      run,
      &advance_run!(&2, &1, length(findings))
    )
  end

  defp insert_finding!(run, attrs) do
    attrs =
      Map.merge(
        %{
          run_id: run.id,
          fingerprint:
            :sha256
            |> :crypto.hash("#{run.id}:#{attrs.category}:#{System.unique_integer([:positive, :monotonic])}")
            |> Base.encode16(case: :lower)
        },
        attrs
      )

    %ProjectSnapshotReconciliationFinding{}
    |> ProjectSnapshotReconciliationFinding.create_changeset(attrs)
    |> Repo.insert!()
  end

  defp advance_run!(run, phase, finding_count) do
    now = TimeHelpers.now()
    completed? = phase == "completed"

    run
    |> ProjectSnapshotReconciliationRun.progress_changeset(%{
      status: if(completed?, do: "completed", else: "running"),
      phase: phase,
      snapshot_after_id: run.snapshot_after_id,
      reservation_after_id: run.reservation_after_id,
      claim_after_sequence: run.claim_after_sequence,
      cleanup_intent_after_id: run.cleanup_intent_after_id,
      provider_scan_completed: completed?,
      cursor_generation: run.cursor_generation + 1,
      inspected_snapshot_count: run.inspected_snapshot_count,
      inspected_object_count: run.inspected_object_count,
      inspected_bytes: run.inspected_bytes,
      provider_object_count: run.provider_object_count,
      provider_bytes: run.provider_bytes,
      finding_count: finding_count,
      started_at: run.started_at || now,
      finished_at: if(completed?, do: now)
    })
    |> Repo.update!()
  end

  defp ready_snapshot_finding(category, snapshot_id) do
    %{
      category: category,
      severity: "critical",
      project_snapshot_id_snapshot: snapshot_id,
      accounting_generation: 1,
      details: %{}
    }
  end

  defp cleanup_finding(cleanup_intent_id, retry_count) do
    %{
      category: "terminal_cleanup_failure",
      severity: "critical",
      cleanup_intent_id_snapshot: cleanup_intent_id,
      details: %{"retry_count" => retry_count}
    }
  end
end
