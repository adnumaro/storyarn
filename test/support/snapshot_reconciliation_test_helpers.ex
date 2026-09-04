defmodule Storyarn.SnapshotReconciliationTestHelpers do
  @moduledoc false

  import ExUnit.Assertions, only: [flunk: 1]

  alias Storyarn.Projects.Versioning

  @retry_window_ms 5_000
  @retry_delay_ms 20

  def start_run(opts) when is_list(opts) do
    deadline_ms = System.monotonic_time(:millisecond) + @retry_window_ms
    retry_start_run(opts, deadline_ms)
  end

  # Exact multipart cleanup performs at most one provider operation per
  # delivery. Drive only immediate continuations and fail if the FSM loops.
  def process_cleanup_until_boundary(intent_id, opts \\ [], attempts_left \\ 100)

  def process_cleanup_until_boundary(intent_id, opts, attempts_left) when attempts_left > 0 do
    case Versioning.process_project_snapshot_cleanup_intent(intent_id, opts) do
      {:ok, {:deferred, 1}} -> process_cleanup_until_boundary(intent_id, opts, attempts_left - 1)
      result -> result
    end
  end

  def process_cleanup_until_boundary(_intent_id, _opts, 0),
    do: flunk("exact multipart cleanup did not reach a durable delivery boundary")

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
