defmodule Storyarn.AI.Operations do
  @moduledoc "Legal operation and usage-event lifecycle transitions."

  import Ecto.Query

  alias Storyarn.AI.ExecutionRoute
  alias Storyarn.AI.Operation
  alias Storyarn.AI.PolicyDecision
  alias Storyarn.AI.Result
  alias Storyarn.AI.Settlement
  alias Storyarn.AI.Task
  alias Storyarn.AI.TaskRegistry
  alias Storyarn.AI.Telemetry
  alias Storyarn.AI.UsageEvent
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers

  require Logger

  @spec claim(pos_integer()) ::
          {:ok, Operation.t(), Task.t(), ExecutionRoute.t()}
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

  @spec start_attempt(Operation.t(), Task.t(), ExecutionRoute.t()) ::
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
    case lock_operation(operation_id) do
      nil -> Repo.rollback(:not_found)
      %Operation{execution_status: "queued"} = operation -> claim_queued(operation)
      %Operation{} -> Repo.rollback(:not_queued)
    end
  end

  defp claim_queued(operation) do
    with {:ok, task} <- TaskRegistry.fetch(operation.task_id),
         true <- operation.task_contract_hash == Task.contract_hash(task) || {:error, :task_contract_changed},
         {:ok, route} <- ExecutionRoute.from_map(operation.execution_route) do
      authorize_claim(operation, task, route)
    else
      {:error, reason} -> {:cancelled, cancel_locked(operation, reason)}
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

  @spec fail_before_attempt(Operation.t(), term()) :: :ok | {:error, term()}
  def fail_before_attempt(%Operation{} = operation, reason) do
    fn ->
      locked = lock_operation(operation.id)

      if (locked && locked.execution_status == "running") and is_nil(locked.external_attempt_started_at) do
        locked = release!(locked)
        transition!(locked, "failed", %{error_classification: classify(reason), completed_at: TimeHelpers.now()})
        delete_result(locked.id)
      else
        Repo.rollback(:invalid_transition)
      end
    end
    |> Repo.transaction()
    |> transaction_status()
  end

  @spec finish_success(Operation.t(), UsageEvent.t(), map() | list(), map()) :: :ok | {:error, term()}
  def finish_success(operation, usage, output, metrics) do
    fn ->
      locked = lock_running_attempt!(operation.id, usage.id)
      task = current_task(locked.task_id)
      now = TimeHelpers.now()

      deliver? =
        not is_nil(task) and locked.task_contract_hash == Task.contract_hash(task) and
          is_nil(locked.cancellation_requested_at) and
          match?({:ok, _}, PolicyDecision.reauthorize(locked, task, :execute, lock_policy: true))

      finish_usage!(usage.id, "succeeded", Map.put(metrics, :completed_at, now))
      locked = commit!(locked)

      if deliver? do
        result = Repo.get_by!(Result, operation_id: locked.id)
        encoded_output = Storyarn.AI.CanonicalJSON.encode!(output)
        expires_at = DateTime.add(now, task.result_ttl_seconds, :second)
        result |> Result.output_changeset(encoded_output, expires_at) |> Repo.update!()
        transition!(locked, "succeeded", %{completed_at: now})
      else
        delete_result(locked.id)

        transition!(locked, "succeeded", %{
          completed_at: now,
          cancellation_requested_at: locked.cancellation_requested_at || now
        })
      end
    end
    |> Repo.transaction()
    |> transaction_status()
  end

  @spec finish_failure(Operation.t(), UsageEvent.t(), term(), map()) :: :ok | {:error, term()}
  def finish_failure(operation, usage, reason, metrics \\ %{}) do
    fn ->
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
    end
    |> Repo.transaction()
    |> transaction_status()
  end

  @spec finish_unknown(Operation.t(), UsageEvent.t(), term(), map()) :: :ok | {:error, term()}
  def finish_unknown(operation, usage, reason, metrics \\ %{}) do
    result =
      fn -> finish_unknown_locked(operation.id, usage.id, reason, metrics) end
      |> Repo.transaction()
      |> transaction_status()

    if result == :ok, do: emit_unknown(operation, reason)
    result
  end

  @doc "Recovers a worker interrupted without ever starting a second provider attempt."
  @spec recover_interrupted(pos_integer()) :: :ready | :ok | {:error, term()}
  def recover_interrupted(operation_id) do
    fn -> operation_id |> lock_operation() |> recover_locked() end
    |> Repo.transaction()
    |> case do
      {:ok, :ready} ->
        :ready

      {:ok, {:unknown, operation}} ->
        emit_unknown(operation, :worker_interrupted)
        :ok

      {:ok, _terminal} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Fails a queued operation when durable worker recovery exhausts its retries."
  @spec fail_queued_after_retries(pos_integer(), term()) :: :ok | {:error, term()}
  def fail_queued_after_retries(operation_id, reason) do
    result =
      Repo.transaction(fn ->
        case lock_operation(operation_id) do
          %Operation{execution_status: "queued"} = operation ->
            operation = release!(operation)
            delete_result(operation.id)

            transition!(operation, "failed", %{
              completed_at: TimeHelpers.now(),
              error_classification: classify(reason)
            })

          _missing_or_terminal ->
            :terminal
        end
      end)

    case result do
      {:ok, %Operation{} = operation} ->
        emit_failed(operation, reason)
        :ok

      {:ok, :terminal} ->
        :ok

      {:error, transaction_reason} ->
        {:error, transaction_reason}
    end
  end

  defp recover_locked(nil), do: :terminal
  defp recover_locked(%Operation{execution_status: "queued"}), do: :ready

  defp recover_locked(%Operation{execution_status: "running", external_attempt_started_at: nil} = operation) do
    operation = release!(operation)
    delete_result(operation.id)

    transition!(operation, "failed", %{
      completed_at: TimeHelpers.now(),
      error_classification: "worker_interrupted_before_attempt"
    })

    :terminal
  end

  defp recover_locked(%Operation{execution_status: "running"} = operation) do
    recovered =
      operation
      |> lock_usage_for_operation()
      |> recover_started_attempt(operation)

    {:unknown, recovered}
  end

  defp recover_locked(%Operation{}), do: :terminal

  defp recover_started_attempt(%UsageEvent{status: "running"} = usage, operation) do
    finish_unknown_locked(operation.id, usage.id, :worker_interrupted, %{})
  end

  defp recover_started_attempt(_usage, operation) do
    operation = release!(operation)
    delete_result(operation.id)

    transition!(operation, "unknown", %{
      completed_at: TimeHelpers.now(),
      error_classification: "worker_interrupted"
    })
  end

  defp lock_usage_for_operation(operation) do
    Repo.one(from(event in UsageEvent, where: event.operation_id == ^operation.id, lock: "FOR UPDATE"))
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

    if operation && usage && operation.execution_status == "running" &&
         not is_nil(operation.external_attempt_started_at) && usage.operation_id == operation.id &&
         usage.status == "running" do
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

  defp current_task(task_id) do
    case TaskRegistry.get(task_id) do
      {:ok, task} -> task
      {:error, _reason} -> nil
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

  defp finish_unknown_locked(operation_id, usage_id, reason, metrics) do
    locked = lock_running_attempt!(operation_id, usage_id)
    now = TimeHelpers.now()
    classification = classify(reason)

    finish_usage!(
      usage_id,
      "unknown",
      metrics |> Map.put(:completed_at, now) |> Map.put(:error_classification, classification)
    )

    locked = release!(locked)
    delete_result(locked.id)
    transition!(locked, "unknown", %{completed_at: now, error_classification: classification})
  end

  defp emit_unknown(operation, reason) do
    Logger.error("AI provider outcome is unknown for task #{operation.task_id}")

    Telemetry.emit([:operation, :unknown], %{count: 1}, %{
      task_id: operation.task_id,
      capability: operation.capability,
      status: "unknown",
      error_classification: classify(reason)
    })
  end

  defp emit_failed(operation, reason) do
    Logger.error("AI operation exhausted worker retries for task #{operation.task_id}")

    Telemetry.emit([:operation, :failed], %{count: 1}, %{
      task_id: operation.task_id,
      capability: operation.capability,
      status: "failed",
      error_classification: classify(reason)
    })
  end

  defp transaction_status({:ok, _result}), do: :ok
  defp transaction_status({:error, reason}), do: {:error, reason}

  defp classify({:unknown, reason}), do: classify(reason)
  defp classify(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp classify(_reason), do: "provider_error"
end
