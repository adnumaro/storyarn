defmodule Storyarn.AI.Operations.Commands.ReconcileReservations do
  @moduledoc "Reconciles expired allowance and stale managed operation reservations in bounded pages."

  import Ecto.Query

  alias Storyarn.AI.Alerts
  alias Storyarn.AI.AllowanceReservation
  alias Storyarn.AI.ManagedSpend
  alias Storyarn.AI.Operation
  alias Storyarn.AI.Operations.Commands.Lifecycle
  alias Storyarn.Repo

  @type batch :: %{
          required(:more?) => boolean(),
          optional(:next_account_id) => integer() | nil,
          optional(:next_operation_id) => integer() | nil
        }

  @spec run(map(), DateTime.t(), pos_integer(), non_neg_integer()) :: %{
          allowance_batch: batch(),
          stale_batch: batch()
        }
  def run(args, sweep_started_at, batch_size, stale_after_seconds)
      when is_map(args) and is_struct(sweep_started_at, DateTime) and is_integer(batch_size) and batch_size > 0 and
             is_integer(stale_after_seconds) and stale_after_seconds >= 0 do
    allowance_batch = expire_allowance_batch(args, sweep_started_at, batch_size)
    stale_batch = stale_operations_batch(args, sweep_started_at, batch_size, stale_after_seconds)

    Enum.each(stale_batch.operations, &reconcile/1)

    %{allowance_batch: allowance_batch, stale_batch: Map.delete(stale_batch, :operations)}
  end

  defp expire_allowance_batch(args, sweep_started_at, batch_size) do
    if args["allowance_done"] == true do
      %{expired_count: 0, failure_count: 0, more?: false, next_account_id: nil}
    else
      ManagedSpend.expire_due(sweep_started_at,
        batch_size: batch_size,
        after_account_id: cursor(args, "after_account_id")
      )
    end
  end

  defp stale_operations_batch(args, sweep_started_at, batch_size, stale_after_seconds) do
    if args["stale_operations_done"] == true do
      %{operations: [], more?: false, next_operation_id: nil}
    else
      query_stale_operations(args, sweep_started_at, batch_size, stale_after_seconds)
    end
  end

  defp query_stale_operations(args, sweep_started_at, batch_size, stale_after_seconds) do
    cutoff = DateTime.add(sweep_started_at, -stale_after_seconds, :second)
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
      "queued" -> Lifecycle.fail_queued_after_retries(operation.id, :stale_reservation)
      "running" -> Lifecycle.recover_interrupted(operation.id)
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
