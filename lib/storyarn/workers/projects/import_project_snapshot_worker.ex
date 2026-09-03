defmodule Storyarn.Workers.ImportProjectSnapshotWorker do
  @moduledoc "Executes one durable workspace project-snapshot import."

  @max_attempts 3
  use Oban.Worker,
    queue: :snapshot_imports,
    max_attempts: @max_attempts,
    unique: [
      fields: [:worker, :args],
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias Storyarn.Projects

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{} = job), do: perform_import(job, &Projects.perform_workspace_snapshot_import/2)

  @doc false
  def perform_import(
        %Oban.Job{id: job_id, args: %{"import_id" => import_id}, attempt: attempt, max_attempts: max_attempts},
        perform_import
      )
      when is_function(perform_import, 2) do
    perform_import
    |> call_safely(import_id,
      job_id: job_id,
      attempt: attempt,
      max_attempts: max_attempts
    )
    |> handle_call_result()
  end

  def perform_import(%Oban.Job{}, _perform_import) do
    emit_outcome(:unexpected)
    {:discard, :invalid_workspace_snapshot_import_job}
  end

  @doc false
  def max_attempts, do: @max_attempts

  defp call_safely(perform_import, import_id, opts) do
    {:returned, perform_import.(import_id, opts)}
  rescue
    exception ->
      Logger.error(
        "Workspace snapshot import worker failed failure=exception " <>
          "exception_module=#{inspect(exception.__struct__)}"
      )

      {:failed, :exception}
  catch
    kind, _reason when kind in [:exit, :throw] ->
      Logger.error("Workspace snapshot import worker failed failure_kind=#{kind}")
      {:failed, kind}
  end

  defp handle_call_result({:returned, result}) do
    {oban_result, outcome} = normalize_result(result)
    emit_outcome(outcome)
    oban_result
  end

  defp handle_call_result({:failed, _failure}) do
    emit_outcome(:unexpected)
    {:error, :workspace_snapshot_import_delivery_failed}
  end

  defp normalize_result({:ok, %{status: "completed"}}), do: {:ok, :completed}
  defp normalize_result({:ok, %{status: "failed"}}), do: {:ok, :terminal_failure}

  # Oban persists and may log returned error terms. Keep domain details inside the
  # import record and expose only fixed, aggregate-safe reasons at this boundary.
  defp normalize_result({:retry, _reason}), do: {{:error, :workspace_snapshot_import_retry}, :retrying}

  defp normalize_result({:snooze, seconds}) when is_integer(seconds) and seconds > 0, do: {{:snooze, seconds}, :snoozed}

  defp normalize_result({:discard, _reason}), do: {{:discard, :workspace_snapshot_import_discarded}, :discarded}

  defp normalize_result(_unexpected), do: {{:error, :workspace_snapshot_import_unexpected_result}, :unexpected}

  defp emit_outcome(outcome) do
    :telemetry.execute(
      [:storyarn, :snapshot, :import, :delivery, :stop],
      %{count: 1},
      %{outcome: outcome}
    )
  end
end
