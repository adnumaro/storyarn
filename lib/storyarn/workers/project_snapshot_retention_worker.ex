defmodule Storyarn.Workers.ProjectSnapshotRetentionWorker do
  @moduledoc """
  Revalidates and deletes expired system snapshots and abandoned builds in
  bounded keyset batches.

  Candidate selection is advisory. Every destructive decision is repeated
  under the workspace, project, and snapshot locks by the lifecycle context.
  """

  use Oban.Worker,
    queue: :snapshots_maintenance,
    max_attempts: 5,
    unique: [fields: [:worker, :args], period: 3_600, states: [:available, :scheduled, :executing, :retryable]]

  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Versioning

  @batch_size 50

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    now = TimeHelpers.now()
    retention_after_id = Map.get(args, "retention_after_id", 0)
    expired_build_after_id = Map.get(args, "expired_build_after_id", 0)

    expired_builds =
      Versioning.list_expired_project_snapshot_build_candidates(now,
        after_id: expired_build_after_id,
        limit: @batch_size
      )

    candidates =
      Versioning.list_project_snapshot_retention_candidates(now,
        after_id: retention_after_id,
        limit: @batch_size
      )

    {expired_build_count, expired_build_failure_count} =
      process_candidates(
        expired_builds,
        &Versioning.delete_expired_project_snapshot_build_candidate/2,
        :expired_build_candidate_changed,
        now
      )

    {deleted_count, failure_count} =
      process_candidates(
        candidates,
        &Versioning.delete_project_snapshot_retention_candidate/2,
        :retention_candidate_changed,
        now
      )

    failure_count = failure_count + expired_build_failure_count
    {continuation_count, failure_count} = continuation_result(candidates, expired_builds, failure_count)

    :telemetry.execute(
      [:storyarn, :snapshot, :retention, :stop],
      %{
        deleted_count: deleted_count,
        expired_build_count: expired_build_count,
        failure_count: failure_count,
        continuation_count: continuation_count
      },
      %{status: if(failure_count == 0, do: :ok, else: :partial)}
    )

    retention_result(failure_count)
  end

  defp process_candidates(candidates, delete, changed_reason, now) do
    Enum.reduce(candidates, {0, 0}, fn candidate, {deleted, failed} ->
      case delete.(candidate, now) do
        {:ok, _intent} -> {deleted + 1, failed}
        {:error, ^changed_reason} -> {deleted, failed}
        {:error, _reason} -> {deleted, failed + 1}
      end
    end)
  end

  defp continuation_result(candidates, expired_builds, failure_count) do
    case maybe_schedule_followup(candidates, expired_builds) do
      {:ok, count} -> {count, failure_count}
      {:error, _reason} -> {0, failure_count + 1}
    end
  end

  defp retention_result(0), do: :ok
  defp retention_result(_failure_count), do: {:error, :snapshot_retention_incomplete}

  defp maybe_schedule_followup(candidates, expired_builds)
       when length(candidates) == @batch_size or length(expired_builds) == @batch_size do
    %{
      retention_after_id: next_after_id(candidates),
      expired_build_after_id: next_after_id(expired_builds)
    }
    |> new(schedule_in: 1)
    |> Oban.insert()
    |> case do
      {:ok, _job} -> {:ok, 1}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_schedule_followup(_candidates, _expired_builds), do: {:ok, 0}

  defp next_after_id([]), do: 0
  defp next_after_id(candidates), do: List.last(candidates).snapshot_id
end
