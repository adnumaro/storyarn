defmodule Storyarn.AI.Operations do
  @moduledoc "Legal operation and usage-event lifecycle transitions."

  import Ecto.Query

  alias Storyarn.AI.ExecutionRoute
  alias Storyarn.AI.Operation
  alias Storyarn.AI.PolicyDecision
  alias Storyarn.AI.Result
  alias Storyarn.AI.Settlement
  alias Storyarn.AI.TaskRegistry
  alias Storyarn.AI.Telemetry
  alias Storyarn.AI.UsageEvent
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers

  require Logger

  @spec claim(pos_integer()) ::
          {:ok, Operation.t(), Storyarn.AI.Task.t(), ExecutionRoute.t()}
          | {:cancelled, Operation.t()}
          | {:error, atom()}
  def claim(operation_id) do
    fn -> claim_locked(operation_id) end
    |> Repo.transaction()
    |> case do
      {:ok, {:claimed, operation, task, route}} -> {:ok, operation, task, route}
      {:ok, {:cancelled, operation}} -> {:cancelled, operation}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec start_attempt(Operation.t(), Storyarn.AI.Task.t(), ExecutionRoute.t()) ::
          {:ok, UsageEvent.t()} | {:cancelled, Operation.t()} | {:error, atom()}
  def start_attempt(%Operation{} = operation, task, route) do
    fn -> operation.id |> lock_operation() |> start_attempt_locked(task, route) end
    |> Repo.transaction()
    |> case do
      {:ok, {:started, usage}} -> {:ok, usage}
      {:ok, {:cancelled, cancelled}} -> {:cancelled, cancelled}
      {:error, reason} -> {:error, reason}
    end
  end

  defp claim_locked(operation_id) do
    operation = lock_operation(operation_id)

    with %Operation{execution_status: "queued"} <- operation,
         {:ok, task} <- TaskRegistry.fetch(operation.task_id),
         {:ok, route} <- ExecutionRoute.from_map(operation.execution_route) do
      authorize_claim(operation, task, route)
    else
      nil -> Repo.rollback(:not_found)
      %Operation{} -> Repo.rollback(:not_queued)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp authorize_claim(operation, task, route) do
    case PolicyDecision.reauthorize(operation, task, :execute, lane: route.lane, lock_policy: true) do
      {:ok, _decision} ->
        running = transition!(operation, "running", %{started_at: TimeHelpers.now()})
        {:claimed, running, task, route}

      {:error, reason} ->
        {:cancelled, cancel_locked(operation, reason)}
    end
  end

  defp start_attempt_locked(locked, task, route) do
    if Repo.exists?(from(event in UsageEvent, where: event.operation_id == ^locked.id)) do
      duplicate_attempt_alert(locked)
      Repo.rollback(:duplicate_external_attempt)
    else
      start_first_attempt(locked, task, route)
    end
  end

  defp start_first_attempt(locked, task, route) do
    with %Operation{execution_status: "running", external_attempt_started_at: nil} <- locked,
         {:ok, _decision} <-
           PolicyDecision.reauthorize(locked, task, :execute, lane: route.lane, lock_policy: true) do
      insert_attempt(locked, route)
    else
      {:error, reason} -> {:cancelled, cancel_locked(locked, reason)}
      _invalid -> Repo.rollback(:invalid_attempt_state)
    end
  end

  defp insert_attempt(locked, route) do
    now = TimeHelpers.now()

    usage =
      %UsageEvent{}
      |> UsageEvent.start_changeset(%{
        operation_id: locked.id,
        status: "running",
        lane: Atom.to_string(route.lane),
        provider: route.provider,
        model: route.model,
        started_at: now
      })
      |> Repo.insert!()

    locked
    |> Operation.transition_changeset(%{external_attempt_started_at: now})
    |> Repo.update!()

    {:started, usage}
  end

  @spec fail_before_attempt(Operation.t(), atom()) :: :ok
  def fail_before_attempt(%Operation{} = operation, reason) do
    Repo.transaction(fn ->
      locked = lock_operation(operation.id)

      if locked.execution_status == "running" and is_nil(locked.external_attempt_started_at) do
        locked = release!(locked)
        transition!(locked, "failed", %{error_classification: classify(reason), completed_at: TimeHelpers.now()})
        delete_result(locked.id)
      else
        Repo.rollback(:invalid_transition)
      end
    end)

    :ok
  end

  @spec finish_success(Operation.t(), UsageEvent.t(), map(), map()) :: :ok
  def finish_success(operation, usage, output, metrics) do
    Repo.transaction(fn ->
      locked = lock_running_attempt!(operation.id, usage.id)
      task = fetch_task!(locked.task_id)
      now = TimeHelpers.now()

      deliver? = match?({:ok, _}, PolicyDecision.reauthorize(locked, task, :execute, lock_policy: true))
      finish_usage!(usage.id, "succeeded", Map.put(metrics, :completed_at, now))
      locked = commit!(locked)

      if deliver? do
        result = Repo.get_by!(Result, operation_id: locked.id)
        encoded_output = Storyarn.AI.CanonicalJSON.encode!(output)
        result |> Result.output_changeset(encoded_output) |> Repo.update!()
        transition!(locked, "succeeded", %{completed_at: now})
      else
        delete_result(locked.id)

        transition!(locked, "succeeded", %{
          completed_at: now,
          cancellation_requested_at: now
        })
      end
    end)

    :ok
  end

  @spec finish_failure(Operation.t(), UsageEvent.t(), atom(), map()) :: :ok
  def finish_failure(operation, usage, reason, metrics \\ %{}) do
    Repo.transaction(fn ->
      locked = lock_running_attempt!(operation.id, usage.id)
      now = TimeHelpers.now()
      classification = classify(reason)

      finish_usage!(
        usage.id,
        "failed",
        metrics |> Map.put(:completed_at, now) |> Map.put(:error_classification, classification)
      )

      locked = release!(locked)
      delete_result(locked.id)
      transition!(locked, "failed", %{completed_at: now, error_classification: classification})
    end)

    :ok
  end

  @spec finish_unknown(Operation.t(), UsageEvent.t(), atom(), map()) :: :ok
  def finish_unknown(operation, usage, reason, metrics \\ %{}) do
    Repo.transaction(fn ->
      locked = lock_running_attempt!(operation.id, usage.id)
      now = TimeHelpers.now()
      classification = classify(reason)

      finish_usage!(
        usage.id,
        "unknown",
        metrics |> Map.put(:completed_at, now) |> Map.put(:error_classification, classification)
      )

      locked = release!(locked)
      delete_result(locked.id)
      transition!(locked, "unknown", %{completed_at: now, error_classification: classification})
    end)

    Logger.error("AI provider outcome is unknown for task #{operation.task_id}")

    Telemetry.emit([:operation, :unknown], %{count: 1}, %{
      task_id: operation.task_id,
      capability: operation.capability,
      status: "unknown",
      error_classification: classify(reason)
    })

    :ok
  end

  @spec request_cancellation(Storyarn.Accounts.Scope.t(), pos_integer()) ::
          {:ok, Operation.t()} | {:error, atom()}
  def request_cancellation(%{user: %{id: actor_id}}, operation_id) do
    Repo.transaction(fn ->
      operation =
        Repo.one(
          from(operation in Operation,
            where: operation.id == ^operation_id and operation.actor_id == ^actor_id,
            lock: "FOR UPDATE"
          )
        )

      case operation do
        %Operation{execution_status: "queued"} -> cancel_locked(operation, :user_cancelled)
        %Operation{execution_status: "running"} -> request_running_cancellation(operation)
        %Operation{} -> operation
        nil -> Repo.rollback(:not_found)
      end
    end)
  end

  defp request_running_cancellation(%Operation{external_attempt_started_at: nil} = operation) do
    cancel_locked(operation, :user_cancelled)
  end

  defp request_running_cancellation(%Operation{} = operation) do
    operation
    |> Operation.transition_changeset(%{cancellation_requested_at: TimeHelpers.now()})
    |> Repo.update!()
  end

  defp cancel_locked(operation, reason) do
    operation = release!(operation)
    delete_result(operation.id)

    transition!(operation, "cancelled", %{
      completed_at: TimeHelpers.now(),
      error_classification: classify(reason)
    })
  end

  defp transition!(operation, next_status, attrs) do
    ensure_transition!(operation, next_status)

    operation
    |> Operation.transition_changeset(Map.put(attrs, :execution_status, next_status))
    |> Repo.update!()
  end

  defp ensure_transition!(%Operation{execution_status: "queued"}, next) when next in ~w(running cancelled failed), do: :ok

  defp ensure_transition!(%Operation{execution_status: "running", external_attempt_started_at: nil}, "cancelled"), do: :ok

  defp ensure_transition!(%Operation{execution_status: "running"}, next) when next in ~w(succeeded failed unknown),
    do: :ok

  defp ensure_transition!(_operation, _next), do: Repo.rollback(:invalid_transition)

  defp lock_operation(id), do: Repo.one(from(operation in Operation, where: operation.id == ^id, lock: "FOR UPDATE"))

  defp lock_running_attempt!(operation_id, usage_id) do
    operation = lock_operation(operation_id)
    usage = Repo.one(from(event in UsageEvent, where: event.id == ^usage_id, lock: "FOR UPDATE"))

    if (operation.execution_status == "running" and operation.external_attempt_started_at) && usage.status == "running" do
      operation
    else
      Repo.rollback(:invalid_transition)
    end
  end

  defp finish_usage!(usage_id, status, attrs) do
    UsageEvent
    |> Repo.get!(usage_id)
    |> UsageEvent.finish_changeset(Map.put(attrs, :status, status))
    |> Repo.update!()
  end

  defp fetch_task!(task_id) do
    case TaskRegistry.get(task_id) do
      {:ok, task} -> task
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp commit!(%Operation{settlement_status: "reserved"} = operation) do
    case Settlement.commit(operation) do
      :ok -> operation |> Operation.transition_changeset(%{settlement_status: "committed"}) |> Repo.update!()
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp commit!(operation), do: operation

  defp release!(%Operation{settlement_status: "reserved"} = operation) do
    case Settlement.release(operation) do
      :ok -> operation |> Operation.transition_changeset(%{settlement_status: "released"}) |> Repo.update!()
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp release!(operation), do: operation

  defp delete_result(operation_id),
    do: Repo.delete_all(from(result in Result, where: result.operation_id == ^operation_id))

  defp duplicate_attempt_alert(operation) do
    Logger.error("Blocked duplicate AI external attempt for task #{operation.task_id}")

    Telemetry.emit([:attempt, :duplicate], %{count: 1}, %{
      task_id: operation.task_id,
      capability: operation.capability,
      status: operation.execution_status,
      error_classification: "duplicate_external_attempt"
    })
  end

  defp classify({:unknown, reason}), do: classify(reason)
  defp classify(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp classify(_reason), do: "provider_error"
end
