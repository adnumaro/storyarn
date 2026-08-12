defmodule Storyarn.SnapshotReconciliationTestHelpers do
  @moduledoc false

  alias Storyarn.Versioning

  @retry_window_ms 5_000
  @retry_delay_ms 20

  def start_run(opts) when is_list(opts) do
    deadline_ms = System.monotonic_time(:millisecond) + @retry_window_ms
    retry_start_run(opts, deadline_ms)
  end

  defp retry_start_run(opts, deadline_ms) do
    case Versioning.start_project_snapshot_reconciliation(opts) do
      {:error, :snapshot_reconciliation_boundary_busy} = error ->
        retry_boundary_busy(opts, deadline_ms, error)

      result ->
        result
    end
  end

  defp retry_boundary_busy(opts, deadline_ms, error) do
    remaining_ms = deadline_ms - System.monotonic_time(:millisecond)

    if remaining_ms > @retry_delay_ms do
      Process.sleep(@retry_delay_ms)
      retry_start_run(opts, deadline_ms)
    else
      error
    end
  end
end
