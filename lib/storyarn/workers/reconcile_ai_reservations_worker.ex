defmodule Storyarn.Workers.ReconcileAIReservationsWorker do
  @moduledoc "Expires allowance and terminalizes stale managed reservations without retrying providers."
  use Oban.Worker, queue: :ai, max_attempts: 1, unique: [period: 300]

  import Ecto.Query

  alias Storyarn.AI.Alerts
  alias Storyarn.AI.Allowance
  alias Storyarn.AI.AllowanceReservation
  alias Storyarn.AI.Operation
  alias Storyarn.AI.Operations
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers

  @default_stale_after_seconds 900

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Allowance.expire_due()

    Enum.each(stale_operations(), &reconcile/1)
    :ok
  end

  defp stale_operations do
    cutoff = DateTime.add(TimeHelpers.now(), -stale_after_seconds(), :second)

    Repo.all(
      from(operation in Operation,
        join: reservation in AllowanceReservation,
        on: reservation.operation_id == operation.id,
        where:
          reservation.status == "reserved" and reservation.inserted_at <= ^cutoff and
            operation.execution_status in ["queued", "running"],
        select: operation
      )
    )
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
end
