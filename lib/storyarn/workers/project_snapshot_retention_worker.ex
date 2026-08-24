defmodule Storyarn.Workers.ProjectSnapshotRetentionWorker do
  @moduledoc """
  Revalidates and deletes expired system snapshots and abandoned builds, and
  terminalizes abandoned restore deliveries, in bounded keyset batches.

  Candidate selection is advisory. Every destructive decision is repeated
  under the workspace, project, and snapshot locks by the lifecycle context.
  The cron runs every 15 minutes: snapshot TTLs tolerate that cadence, while
  expired build reservations require bounded quota reclamation.
  """

  use Oban.Worker,
    queue: :snapshots_maintenance,
    max_attempts: 5,
    unique: [fields: [:worker, :args], period: 600, states: [:available, :scheduled, :executing, :retryable]]

  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Versioning

  @batch_size 50
  @timeout_ms 10 * 60 * 1_000

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    Versioning.discard_stale_project_snapshot_maintenance_jobs()

    now = TimeHelpers.now()
    build_recovery = Versioning.reconcile_stale_project_snapshot_builds()

    snapshot_import_recovery =
      Versioning.reconcile_abandoned_workspace_snapshot_import_deliveries(limit: @batch_size)

    {export_lease_after_id, export_lease_cutoff} = export_lease_cursor(args, now)
    {export_lease_purge_after_id, export_lease_purge_cutoff} = export_lease_purge_cursor(args, now)

    export_lease_recovery =
      Versioning.recover_expired_project_snapshot_export_leases(export_lease_cutoff,
        after_id: export_lease_after_id,
        limit: @batch_size
      )

    export_lease_purge =
      Versioning.purge_released_project_snapshot_export_leases(export_lease_purge_cutoff,
        after_id: export_lease_purge_after_id,
        limit: @batch_size
      )

    retention_after_id = Map.get(args, "retention_after_id", 0)
    expired_build_after_id = Map.get(args, "expired_build_after_id", 0)
    through_id = Map.get(args, "through_id") || Versioning.project_snapshot_lifecycle_high_watermark()

    restore_recovery_after_id =
      normalize_after_id(Map.get(args, "restore_recovery_after_id", 0))

    restore_recovery_through_id =
      Map.get(args, "restore_recovery_through_id") ||
        Versioning.project_snapshot_restore_delivery_recovery_high_watermark()

    abandoned_restores =
      Versioning.list_abandoned_project_snapshot_restore_deliveries(
        after_id: restore_recovery_after_id,
        through_id: restore_recovery_through_id,
        limit: @batch_size
      )

    expired_builds =
      Versioning.list_expired_project_snapshot_build_candidates(now,
        after_id: expired_build_after_id,
        through_id: through_id,
        limit: @batch_size
      )

    candidates =
      Versioning.list_project_snapshot_retention_candidates(now,
        after_id: retention_after_id,
        through_id: through_id,
        limit: @batch_size
      )

    {expired_build_count, expired_build_failure_count} =
      process_candidates(
        expired_builds,
        &Versioning.delete_expired_project_snapshot_build_candidate/1,
        :expired_build_candidate_changed
      )

    {deleted_count, failure_count} =
      process_candidates(
        candidates,
        &Versioning.delete_project_snapshot_retention_candidate/1,
        :retention_candidate_changed
      )

    {abandoned_restore_count, abandoned_restore_failure_count} =
      process_abandoned_restore_candidates(abandoned_restores)

    failure_count =
      failure_count + expired_build_failure_count + build_recovery.failure_count +
        export_lease_recovery.failure_count + export_lease_purge.failure_count +
        abandoned_restore_failure_count + snapshot_import_recovery.failure_count

    continuation = %{
      candidates: candidates,
      expired_builds: expired_builds,
      retention_after_id: retention_after_id,
      expired_build_after_id: expired_build_after_id,
      through_id: through_id,
      abandoned_restores: abandoned_restores,
      restore_recovery_after_id: restore_recovery_after_id,
      restore_recovery_through_id: restore_recovery_through_id,
      export_lease_recovery: export_lease_recovery,
      export_lease_after_id: export_lease_after_id,
      export_lease_cutoff: export_lease_cutoff,
      export_lease_purge: export_lease_purge,
      export_lease_purge_after_id: export_lease_purge_after_id,
      export_lease_purge_cutoff: export_lease_purge_cutoff
    }

    {continuation_count, failure_count} =
      continuation_result(continuation, failure_count)

    {recovery_followup_count, failure_count} =
      build_recovery_followup_result(build_recovery.orphaned_count, now, failure_count)

    continuation_count = continuation_count + recovery_followup_count

    :telemetry.execute(
      [:storyarn, :snapshot, :retention, :stop],
      %{
        deleted_count: deleted_count,
        expired_build_count: expired_build_count,
        expired_export_lease_candidate_count: export_lease_recovery.candidate_count,
        expired_export_lease_count: export_lease_recovery.released_count,
        expired_export_lease_changed_count: export_lease_recovery.changed_count,
        purged_export_lease_candidate_count: export_lease_purge.candidate_count,
        purged_export_lease_count: export_lease_purge.purged_count,
        purged_export_lease_changed_count: export_lease_purge.changed_count,
        orphaned_build_count: build_recovery.orphaned_count,
        settled_build_count: build_recovery.settled_count,
        abandoned_restore_count: abandoned_restore_count,
        abandoned_snapshot_import_candidate_count: snapshot_import_recovery.candidate_count,
        abandoned_snapshot_import_terminalized_count: snapshot_import_recovery.terminalized_count,
        abandoned_snapshot_import_changed_count: snapshot_import_recovery.changed_count,
        failure_count: failure_count,
        continuation_count: continuation_count
      },
      %{status: if(failure_count == 0, do: :ok, else: :partial)}
    )

    retention_result(failure_count)
  end

  @impl Oban.Worker
  def timeout(_job), do: @timeout_ms

  defp process_candidates(candidates, delete, changed_reason) do
    Enum.reduce(candidates, {0, 0}, fn candidate, {deleted, failed} ->
      case delete.(candidate) do
        {:ok, _intent} -> {deleted + 1, failed}
        {:error, ^changed_reason} -> {deleted, failed}
        {:error, _reason} -> {deleted, failed + 1}
      end
    end)
  end

  defp process_abandoned_restore_candidates(candidates) do
    Enum.reduce(candidates, {0, 0}, fn candidate, {recovered, failed} ->
      case Versioning.recover_abandoned_project_snapshot_restore_delivery(candidate) do
        {:ok, :recovered} -> {recovered + 1, failed}
        {:ok, :stale} -> {recovered, failed}
        {:error, :project_snapshot_restore_delivery_busy} -> {recovered, failed}
        {:error, _reason} -> {recovered, failed + 1}
      end
    end)
  end

  defp continuation_result(continuation, failure_count) do
    case maybe_schedule_followup(continuation) do
      {:ok, count} -> {count, failure_count}
      {:error, _reason} -> {0, failure_count + 1}
    end
  end

  defp retention_result(0), do: :ok
  defp retention_result(_failure_count), do: {:error, :snapshot_retention_incomplete}

  defp build_recovery_followup_result(0, _now, failure_count), do: {0, failure_count}

  defp build_recovery_followup_result(_orphaned_count, now, failure_count) do
    scheduled_at =
      DateTime.add(now, Versioning.project_snapshot_build_recovery_quarantine_seconds(), :second)

    %{build_recovery_followup: true}
    |> new(scheduled_at: scheduled_at)
    |> Oban.insert()
    |> case do
      {:ok, %Oban.Job{conflict?: true}} -> {0, failure_count}
      {:ok, %Oban.Job{}} -> {1, failure_count}
      {:error, _reason} -> {0, failure_count + 1}
    end
  end

  defp maybe_schedule_followup(continuation) do
    cursor = continuation_cursor(continuation)

    if continuation_required?(continuation, cursor) do
      continuation
      |> followup_args(cursor)
      |> schedule_followup()
    else
      {:ok, 0}
    end
  end

  defp continuation_cursor(continuation) do
    recovery = continuation.export_lease_recovery
    purge = continuation.export_lease_purge

    %{
      retention_after_id: next_after_id(continuation.candidates, continuation.retention_after_id),
      expired_build_after_id: next_after_id(continuation.expired_builds, continuation.expired_build_after_id),
      restore_recovery_after_id:
        next_restore_after_id(
          continuation.abandoned_restores,
          continuation.restore_recovery_after_id
        ),
      export_lease_after_id: recovery.last_candidate_id || continuation.export_lease_after_id,
      continue_export_leases?: recovery.candidate_count == @batch_size and is_integer(recovery.last_candidate_id),
      export_lease_purge_after_id: purge.last_candidate_id || continuation.export_lease_purge_after_id,
      continue_export_lease_purge?: purge.candidate_count == @batch_size and is_integer(purge.last_candidate_id)
    }
  end

  defp continuation_required?(continuation, cursor) do
    stream_remaining?(
      continuation.candidates,
      cursor.retention_after_id,
      continuation.through_id
    ) or
      stream_remaining?(
        continuation.expired_builds,
        cursor.expired_build_after_id,
        continuation.through_id
      ) or
      stream_remaining?(
        continuation.abandoned_restores,
        cursor.restore_recovery_after_id,
        continuation.restore_recovery_through_id
      ) or cursor.continue_export_leases? or cursor.continue_export_lease_purge?
  end

  defp stream_remaining?([], _next_after_id, _through_id), do: false
  defp stream_remaining?(_candidates, next_after_id, through_id), do: next_after_id < through_id

  defp followup_args(continuation, cursor) do
    %{
      retention_after_id: cursor.retention_after_id,
      expired_build_after_id: cursor.expired_build_after_id,
      through_id: continuation.through_id,
      restore_recovery_after_id: cursor.restore_recovery_after_id,
      restore_recovery_through_id: continuation.restore_recovery_through_id
    }
    |> maybe_put_export_lease_cursor(
      cursor.continue_export_leases?,
      cursor.export_lease_after_id,
      continuation.export_lease_cutoff
    )
    |> maybe_put_export_lease_purge_cursor(
      cursor.continue_export_lease_purge?,
      cursor.export_lease_purge_after_id,
      continuation.export_lease_purge_cutoff
    )
  end

  defp schedule_followup(args) do
    args
    |> new()
    |> Oban.insert()
    |> case do
      {:ok, _job} -> {:ok, 1}
      {:error, reason} -> {:error, reason}
    end
  end

  defp next_after_id([], current_after_id), do: current_after_id
  defp next_after_id(candidates, _current_after_id), do: List.last(candidates).snapshot_id

  defp next_restore_after_id([], current_after_id), do: current_after_id
  defp next_restore_after_id(candidates, _current_after_id), do: List.last(candidates).restore_id

  defp normalize_after_id(after_id) when is_integer(after_id) and after_id >= 0, do: after_id
  defp normalize_after_id(_after_id), do: 0

  defp export_lease_cursor(args, now) do
    after_id = Map.get(args, "export_lease_after_id", Map.get(args, :export_lease_after_id, 0))
    cutoff = Map.get(args, "export_lease_cutoff", Map.get(args, :export_lease_cutoff))

    {normalize_export_lease_after_id(after_id), normalize_export_lease_cutoff(cutoff, now)}
  end

  defp normalize_export_lease_after_id(after_id) when is_integer(after_id) and after_id >= 0, do: after_id
  defp normalize_export_lease_after_id(_after_id), do: 0

  defp normalize_export_lease_cutoff(nil, now), do: now

  defp normalize_export_lease_cutoff(value, now) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, cutoff, 0} -> cutoff
      _invalid -> now
    end
  end

  defp normalize_export_lease_cutoff(_value, now), do: now

  defp maybe_put_export_lease_cursor(args, true, after_id, cutoff) do
    args
    |> Map.put(:export_lease_after_id, after_id)
    |> Map.put(:export_lease_cutoff, DateTime.to_iso8601(cutoff))
  end

  defp maybe_put_export_lease_cursor(args, false, _after_id, _cutoff), do: args

  defp export_lease_purge_cursor(args, now) do
    after_id =
      Map.get(
        args,
        "export_lease_purge_after_id",
        Map.get(args, :export_lease_purge_after_id, 0)
      )

    cutoff =
      Map.get(
        args,
        "export_lease_purge_cutoff",
        Map.get(args, :export_lease_purge_cutoff)
      )

    default_cutoff =
      DateTime.add(
        now,
        -Versioning.project_snapshot_export_lease_retention_seconds(),
        :second
      )

    {normalize_export_lease_after_id(after_id), normalize_export_lease_cutoff(cutoff, default_cutoff)}
  end

  defp maybe_put_export_lease_purge_cursor(args, true, after_id, cutoff) do
    args
    |> Map.put(:export_lease_purge_after_id, after_id)
    |> Map.put(:export_lease_purge_cutoff, DateTime.to_iso8601(cutoff))
  end

  defp maybe_put_export_lease_purge_cursor(args, false, _after_id, _cutoff), do: args
end
