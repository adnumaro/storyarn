defmodule Storyarn.Workers.ReconcileAIReservationsWorker do
  @moduledoc "Expires allowance and terminalizes stale managed reservations without retrying providers."

  # The uniqueness window must stay strictly below the `*/15` cron interval it
  # is scheduled at. Oban compares a DB-clock `inserted_at` against an app-clock
  # cutoff with an inclusive `>=`.
  use Oban.Worker, queue: :ai_maintenance, max_attempts: 1, unique: [period: 240]

  alias Storyarn.AI
  alias Storyarn.Platform.Shared.TimeHelpers

  @default_stale_after_seconds 300
  @default_batch_size 100

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    args = if is_map(args), do: args, else: %{}
    sweep_started_at = sweep_started_at(args)

    %{allowance_batch: allowance_batch, stale_batch: stale_batch} =
      AI.reconcile_reservations(
        args,
        sweep_started_at,
        batch_size(),
        stale_after_seconds()
      )

    maybe_schedule_followup(allowance_batch, stale_batch, sweep_started_at)
  end

  defp stale_after_seconds do
    :storyarn
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:stale_after_seconds, @default_stale_after_seconds)
  end

  defp batch_size do
    case :storyarn |> Application.get_env(__MODULE__, []) |> Keyword.get(:batch_size, @default_batch_size) do
      value when is_integer(value) and value > 0 -> value
      _invalid -> @default_batch_size
    end
  end

  defp maybe_schedule_followup(%{more?: false}, %{more?: false}, _sweep_started_at), do: :ok

  defp maybe_schedule_followup(allowance_batch, stale_batch, sweep_started_at) do
    sweep_started_at
    |> continuation_args(allowance_batch, stale_batch)
    |> schedule_followup()
    |> case do
      {:ok, _job} -> :ok
      {:error, reason} -> {:error, {:followup_schedule_failed, reason}}
    end
  end

  defp continuation_args(sweep_started_at, allowance_batch, stale_batch) do
    %{"sweep_started_at" => DateTime.to_iso8601(sweep_started_at)}
    |> put_allowance_state(allowance_batch)
    |> put_stale_operations_state(stale_batch)
  end

  defp put_allowance_state(args, %{more?: true, next_account_id: account_id}) when is_integer(account_id) do
    Map.put(args, "after_account_id", account_id)
  end

  defp put_allowance_state(args, _batch), do: Map.put(args, "allowance_done", true)

  defp put_stale_operations_state(args, %{more?: true, next_operation_id: operation_id}) when is_integer(operation_id) do
    Map.put(args, "after_operation_id", operation_id)
  end

  defp put_stale_operations_state(args, _batch), do: Map.put(args, "stale_operations_done", true)

  # Insert directly as available: serial queue concurrency keeps this page from
  # starting until the current one returns. A colliding root job is replaced
  # with the continuation so the frozen cutoff and cursors are preserved.
  defp schedule_followup(args) do
    args
    |> new(
      replace: [
        available: [:args],
        scheduled: [:args],
        retryable: [:args]
      ],
      unique: [
        fields: [:worker],
        period: :infinity,
        states: [:available, :scheduled, :retryable]
      ]
    )
    |> Oban.insert()
  end

  defp sweep_started_at(args) do
    case Map.get(args, "sweep_started_at") do
      value when is_binary(value) -> parse_sweep_started_at(value)
      _missing -> TimeHelpers.now()
    end
  end

  defp parse_sweep_started_at(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      {:error, _reason} -> TimeHelpers.now()
    end
  end
end
