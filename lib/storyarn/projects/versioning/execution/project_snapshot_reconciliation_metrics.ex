defmodule Storyarn.Projects.Versioning.ProjectSnapshotReconciliationMetrics do
  @moduledoc """
  Rehydrates the latest durable snapshot-reconciliation result into telemetry.

  The projection exports only aggregate counts, byte totals, timestamps, and
  bounded state. Reconciliation findings may contain operational identifiers,
  but those values never enter telemetry metadata or measurements.
  """

  import Ecto.Query

  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.Assets.Storage
  alias Storyarn.Projects.Versioning.ProjectSnapshotReconciliationFinding
  alias Storyarn.Projects.Versioning.ProjectSnapshotReconciliationRun
  alias Storyarn.Repo

  require Logger

  @event [:storyarn, :snapshot, :reconciliation, :projection, :stop]
  @aggregate_measurements [
    :corrupt_ready_snapshot_count,
    :missing_ready_snapshot_count,
    :orphan_object_bytes,
    :stale_reservation_bytes,
    :terminal_cleanup_failure_count,
    :terminal_cleanup_retry_count
  ]
  @missing_categories ~w(ready_manifest_missing ready_object_missing)
  @corrupt_categories ~w(ready_manifest_corrupt ready_object_corrupt)
  @empty_summary %{
    corrupt_ready_snapshot_count: 0,
    finding_count: 0,
    missing_ready_snapshot_count: 0,
    orphan_object_bytes: 0,
    stale_reservation_bytes: 0,
    terminal_cleanup_failure_count: 0,
    terminal_cleanup_retry_count: 0
  }

  @doc false
  @spec child_specs(keyword()) :: [Supervisor.child_spec()]
  def child_specs(config) when is_list(config) do
    if Keyword.fetch!(config, :enabled) do
      interval = Keyword.fetch!(config, :oban_poll_interval)

      [
        Supervisor.child_spec(
          {:telemetry_poller, measurements: [{__MODULE__, :emit, []}], period: interval, init_delay: 0},
          id: __MODULE__
        )
      ]
    else
      []
    end
  end

  @doc false
  @spec emit() :: :ok
  def emit do
    emit_with(&latest_completed_snapshot/0, TimeHelpers.now())
  end

  @doc false
  @spec emit_with((-> nil | {ProjectSnapshotReconciliationRun.t(), map()}), DateTime.t()) :: :ok
  def emit_with(snapshot, %DateTime{} = now) when is_function(snapshot, 0) do
    case snapshot.() do
      nil -> emit_missing(now)
      {%ProjectSnapshotReconciliationRun{} = run, summary} when is_map(summary) -> emit_completed(run, summary, now)
      _invalid -> raise "invalid snapshot reconciliation metrics projection"
    end

    :ok
  rescue
    exception ->
      Logger.error(
        "Snapshot reconciliation metrics projection failed failure=exception " <>
          "exception_module=#{inspect(exception.__struct__)}"
      )

      emit_failure()
      :ok
  catch
    kind, _reason when kind in [:exit, :throw] ->
      Logger.error("Snapshot reconciliation metrics projection failed failure=#{kind}")
      emit_failure()
      :ok
  end

  defp latest_completed_snapshot do
    case Storage.namespace_fingerprint() do
      {:ok, namespace_fingerprint} -> latest_completed_snapshot(namespace_fingerprint)
      {:error, _reason} -> raise "snapshot reconciliation metrics namespace unavailable"
    end
  end

  defp latest_completed_snapshot(namespace_fingerprint) do
    query =
      from(run in ProjectSnapshotReconciliationRun,
        where:
          run.provider_namespace_fingerprint == ^namespace_fingerprint and
            run.status == "completed" and not is_nil(run.finished_at),
        order_by: [desc: run.finished_at, desc: run.id],
        limit: 1
      )

    case Repo.one(query) do
      %ProjectSnapshotReconciliationRun{} = run -> {run, summary_findings(run.id)}
      nil -> nil
    end
  end

  defp summary_findings(run_id) do
    ProjectSnapshotReconciliationFinding
    |> where([finding], finding.run_id == ^run_id)
    |> select([finding], %{
      stale_reservation_bytes:
        coalesce(
          filter(
            sum(finding.expected_size_bytes),
            finding.category == "stale_reservation" and finding.expected_size_bytes >= 0
          ),
          0
        ),
      orphan_object_bytes:
        coalesce(
          filter(
            sum(finding.observed_size_bytes),
            finding.category == "abandoned_temporary_object" and finding.observed_size_bytes >= 0
          ),
          0
        ),
      missing_ready_snapshot_count:
        filter(
          count(finding.project_snapshot_id_snapshot, :distinct),
          finding.category in ^@missing_categories
        ),
      corrupt_ready_snapshot_count:
        filter(
          count(finding.project_snapshot_id_snapshot, :distinct),
          finding.category in ^@corrupt_categories
        ),
      terminal_cleanup_failure_count: filter(count(finding.id), finding.category == "terminal_cleanup_failure"),
      terminal_cleanup_retry_count:
        fragment(
          """
          COALESCE(
            SUM(
              CASE
                WHEN ? = 'terminal_cleanup_failure'
                  AND jsonb_typeof(?->'retry_count') = 'number'
                  AND (?->>'retry_count') ~ '^(-[0-9]+|[0-9]+)$'
                THEN GREATEST((?->>'retry_count')::numeric, 0)
                ELSE 0
              END
            ),
            0
          )
          """,
          finding.category,
          finding.details,
          finding.details,
          finding.details
        )
    })
    |> Repo.one!()
    |> normalize_summary()
  end

  defp normalize_summary(summary) do
    Map.new(@aggregate_measurements, fn measurement ->
      {measurement, summary |> Map.fetch!(measurement) |> normalize_non_negative_integer!()}
    end)
  end

  defp normalize_non_negative_integer!(value) when is_integer(value) and value >= 0, do: value

  defp normalize_non_negative_integer!(%Decimal{} = value) do
    integer = Decimal.to_integer(value)

    if integer >= 0 and Decimal.equal?(value, Decimal.new(integer)) do
      integer
    else
      raise "invalid snapshot reconciliation aggregate"
    end
  end

  defp normalize_non_negative_integer!(_value) do
    raise "invalid snapshot reconciliation aggregate"
  end

  defp emit_completed(run, summary, now) do
    measurements =
      summary
      |> Map.put(:finding_count, run.finding_count)
      |> Map.merge(%{
        latest_completed_available: 1,
        latest_completed_at_unix_seconds: DateTime.to_unix(run.finished_at),
        observed_at_unix_seconds: DateTime.to_unix(now),
        success: 1,
        failure_count: 0
      })

    :telemetry.execute(@event, measurements, %{})
  end

  defp emit_missing(now) do
    measurements =
      Map.merge(@empty_summary, %{
        latest_completed_available: 0,
        latest_completed_at_unix_seconds: 0,
        observed_at_unix_seconds: DateTime.to_unix(now),
        success: 1,
        failure_count: 0
      })

    :telemetry.execute(@event, measurements, %{})
  end

  defp emit_failure do
    :telemetry.execute(@event, %{success: 0, failure_count: 1}, %{})
  end
end
