defmodule Storyarn.Workers.ReconcileAIReservationsWorker do
  @moduledoc "Expires allowance and terminalizes stale managed reservations without retrying providers."
  # The uniqueness window must stay strictly below the `*/15` cron interval it is
  # scheduled at. Oban compares a DB-clock `inserted_at` against an app-clock
  # cutoff with an inclusive `>=`, so a window equal to the schedule dedupes
  # every other tick as soon as clock skew exceeds the BEGIN round-trip.
  use Oban.Worker, queue: :ai_maintenance, max_attempts: 1, unique: [period: 240]

  import Ecto.Query

  alias Storyarn.AI.Alerts
  alias Storyarn.AI.Allowance
  alias Storyarn.AI.AllowanceReservation
  alias Storyarn.AI.Operation
  alias Storyarn.AI.Operations
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers

  # Recovery bound = this threshold + the cron interval. It was 900 + 300; the
  # cron moved to 900 to let the database compute idle, so this drops to 300 to
  # hold the documented ≤20 minute bound unchanged.
  #
  # This is the shorter of the two knobs, so it is the one that decides how long
  # a genuinely slow provider call may run before being treated as stalled. It
  # must stay above the longest managed execution — safe today because the only
  # registered task is `execution_mode: :inline` and never reserves in the
  # background.
  @default_stale_after_seconds 300
  @default_batch_size 100

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    args = if is_map(args), do: args, else: %{}
    sweep_started_at = sweep_started_at(args)
    batch_size = batch_size()

    allowance_batch = expire_allowance_batch(args, sweep_started_at, batch_size)
    stale_batch = stale_operations_batch(args, sweep_started_at, batch_size)

    Enum.each(stale_batch.operations, &reconcile/1)

    maybe_schedule_followup(allowance_batch, stale_batch, sweep_started_at)
  end

  defp expire_allowance_batch(args, sweep_started_at, batch_size) do
    if args["allowance_done"] == true do
      %{expired_count: 0, failure_count: 0, more?: false, next_account_id: nil}
    else
      Allowance.expire_due(sweep_started_at,
        batch_size: batch_size,
        after_account_id: cursor(args, "after_account_id")
      )
    end
  end

  defp stale_operations_batch(args, sweep_started_at, batch_size) do
    if args["stale_operations_done"] == true do
      %{operations: [], more?: false, next_operation_id: nil}
    else
      query_stale_operations(args, sweep_started_at, batch_size)
    end
  end

  defp query_stale_operations(args, sweep_started_at, batch_size) do
    cutoff = DateTime.add(sweep_started_at, -stale_after_seconds(), :second)
    after_operation_id = cursor(args, "after_operation_id")

    operations =
      Repo.all(
        from(operation in Operation,
          join: reservation in AllowanceReservation,
          on: reservation.operation_id == operation.id,
          where:
            operation.id > ^after_operation_id and reservation.status == "reserved" and
              reservation.inserted_at <= ^cutoff and operation.execution_status in ["queued", "running"],
          order_by: [asc: operation.id],
          limit: ^(batch_size + 1),
          select: operation
        )
      )

    {batch, overflow} = Enum.split(operations, batch_size)

    %{
      operations: batch,
      more?: overflow != [],
      next_operation_id: batch |> List.last() |> operation_id()
    }
  end

  defp reconcile(%Operation{} = operation) do
    Alerts.record(%{
      dedupe_key: "stale-reservation:#{operation.id}",
      kind: "stale_reservation",
      severity: "critical",
      workspace_id: operation.workspace_id,
      workspace_id_snapshot: operation.workspace_id_snapshot,
      operation_id: operation.id,
      metadata: %{"execution_status" => operation.execution_status, "task_id" => operation.task_id}
    })

    case operation.execution_status do
      "queued" -> Operations.fail_queued_after_retries(operation.id, :stale_reservation)
      "running" -> Operations.recover_interrupted(operation.id)
    end
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

  # Insert directly as available: scheduled jobs depend on the deliberately
  # coarse Oban staging interval. Serial queue concurrency keeps this page from
  # starting until the current one returns, while older available maintenance
  # jobs remain ahead of the newly inserted continuation.
  #
  # A cron tick may already have queued a root job while this page was running.
  # Coalesce that conflict into the continuation by replacing its args, keeping
  # the cursor and frozen cutoff instead of silently restarting the sweep. The
  # continuation period is infinite because an available root can wait longer
  # than the cron uniqueness window behind another maintenance job. The worker's
  # compile-time 240-second period still governs ordinary cron insertions.
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

  defp cursor(args, key) do
    case Map.get(args, key, 0) do
      value when is_integer(value) and value >= 0 -> value
      _invalid -> 0
    end
  end

  defp operation_id(nil), do: nil
  defp operation_id(%Operation{id: id}), do: id
end
