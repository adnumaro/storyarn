defmodule Storyarn.AI.Operations.Commands.Lifecycle do
  @moduledoc "Legal operation and usage-event lifecycle transitions."

  import Ecto.Query

  alias Storyarn.AI.Alerts
  alias Storyarn.AI.Context
  alias Storyarn.AI.CredentialResolver
  alias Storyarn.AI.ExecutionRoute
  alias Storyarn.AI.Governance
  alias Storyarn.AI.Integrations
  alias Storyarn.AI.ManagedSpend
  alias Storyarn.AI.Operation
  alias Storyarn.AI.Operations.Projections.UserRecord, as: User
  alias Storyarn.AI.Result
  alias Storyarn.AI.Routing
  alias Storyarn.AI.Task
  alias Storyarn.AI.Telemetry
  alias Storyarn.AI.UsageEvent
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

  require Logger

  @spec claim(pos_integer()) ::
          {:ok, Operation.t(), Task.t(), ExecutionRoute.t()}
          | {:cancelled, Operation.t()}
          | {:error, atom()}
  def claim(operation_id) do
    fn -> prepare_and_claim(operation_id) end
    |> Repo.transaction()
    |> case do
      {:ok, {:claimed, operation, task, route}} -> {:ok, operation, task, route}
      {:ok, {:cancelled, operation}} -> {:cancelled, operation}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec start_attempt(Operation.t(), Task.t(), ExecutionRoute.t()) ::
          {:ok, UsageEvent.t(), Storyarn.AI.ResolvedCredential.t()}
          | {:cancelled, Operation.t()}
          | {:error, atom()}
  def start_attempt(%Operation{} = operation, task, route) do
    fn -> prepare_and_start_attempt(operation.id, task, route) end
    |> Repo.transaction()
    |> case do
      {:ok, {:started, usage, credential}} ->
        {:ok, usage, credential}

      {:ok, {:cancelled, cancelled}} ->
        {:cancelled, cancelled}

      {:error, :duplicate_external_attempt = reason} ->
        duplicate_attempt_alert(operation)
        {:error, reason}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp prepare_and_claim(operation_id) do
    case Repo.get(Operation, operation_id) do
      nil ->
        Repo.rollback(:not_found)

      %Operation{execution_status: "queued"} = snapshot ->
        preparation = prepare_claim(snapshot)
        snapshot.id |> lock_operation() |> claim_locked(preparation)

      %Operation{} = snapshot ->
        case lock_operation(snapshot.id) do
          nil -> Repo.rollback(:not_found)
          %Operation{} -> Repo.rollback(:not_queued)
        end
    end
  end

  defp prepare_claim(snapshot) do
    lock_preparation = Governance.prepare_operation_reauthorization(snapshot)

    with {:ok, task} <- Routing.fetch_task(snapshot.task_id),
         :ok <- task_contract_current(snapshot, task),
         {:ok, route} <- ExecutionRoute.from_map(snapshot.execution_route) do
      preauthorization =
        Governance.preauthorize_operation(snapshot, task, :execute,
          lane: route.lane,
          preparation: lock_preparation
        )

      {:prepared, preauthorization}
    else
      {:error, reason} -> {:denied, reason}
    end
  end

  defp claim_locked(nil, _preparation), do: Repo.rollback(:not_found)

  defp claim_locked(%Operation{execution_status: status}, _preparation) when status != "queued",
    do: Repo.rollback(:not_queued)

  defp claim_locked(%Operation{} = operation, {:denied, reason}) do
    {:cancelled, cancel_locked(operation, reason)}
  end

  defp claim_locked(%Operation{} = operation, {:prepared, preauthorization}) do
    with {:ok, task} <- Routing.fetch_task(operation.task_id),
         :ok <- task_contract_current(operation, task),
         {:ok, route} <- ExecutionRoute.from_map(operation.execution_route),
         {:ok, _decision} <-
           Governance.complete_operation_reauthorization(
             operation,
             task,
             :execute,
             preauthorization,
             lane: route.lane
           ),
         {:ok, scope} <- operation_scope(operation),
         :ok <- Context.operation_current?(scope, task, operation) do
      running = transition!(operation, "running", %{started_at: TimeHelpers.now()})
      {:claimed, running, task, route}
    else
      {:error, :operation_authorization_changed} -> Repo.rollback(:operation_authorization_changed)
      {:error, reason} -> {:cancelled, cancel_locked(operation, reason)}
    end
  end

  defp prepare_and_start_attempt(operation_id, task, route) do
    snapshot = Repo.get(Operation, operation_id)
    lock_preparation = prepare_operation_lock(snapshot)

    preauthorization =
      if attemptable_snapshot?(snapshot) and not attempt_exists?(operation_id) do
        prepare_attempt(snapshot, task, route, lock_preparation)
      end

    operation_id
    |> lock_prepared_operation(lock_preparation)
    |> start_attempt_locked(preauthorization)
  end

  defp prepare_attempt(snapshot, supplied_task, supplied_route, lock_preparation) do
    case attempt_arguments_current(snapshot, supplied_task, supplied_route) do
      :ok ->
        with {:ok, task} <- Routing.fetch_task(snapshot.task_id),
             :ok <- task_contract_current(snapshot, task),
             {:ok, route} <- ExecutionRoute.from_map(snapshot.execution_route) do
          {:prepared,
           Governance.preauthorize_operation(snapshot, task, :execute,
             lane: route.lane,
             preparation: lock_preparation
           )}
        else
          {:error, reason} -> {:denied, reason}
        end

      {:error, reason} ->
        {:invalid_arguments, reason}
    end
  end

  defp start_attempt_locked(nil, _preauthorization), do: Repo.rollback(:invalid_attempt_state)

  defp start_attempt_locked(locked, preauthorization) do
    if attempt_exists?(locked.id) do
      Repo.rollback(:duplicate_external_attempt)
    else
      case preauthorization do
        {:invalid_arguments, reason} -> Repo.rollback(reason)
        _prepared_or_denied -> start_first_attempt(locked, preauthorization)
      end
    end
  end

  defp start_first_attempt(locked, preauthorization) do
    with %Operation{execution_status: "running", external_attempt_started_at: nil} <- locked,
         {:ok, task} <- Routing.fetch_task(locked.task_id),
         :ok <- task_contract_current(locked, task),
         {:ok, route} <- ExecutionRoute.from_map(locked.execution_route),
         {:ok, _decision} <-
           complete_attempt_reauthorization(locked, task, route, preauthorization),
         {:ok, scope} <- operation_scope(locked),
         :ok <- Context.operation_current?(scope, task, locked),
         {:ok, credential} <-
           CredentialResolver.resolve(route.credential_ref, %{operation: locked, task: task, route: route}) do
      insert_attempt(locked, route, credential)
    else
      {:error, :operation_authorization_changed} -> Repo.rollback(:operation_authorization_changed)
      {:error, reason} -> {:cancelled, cancel_locked(locked, reason)}
      _invalid -> Repo.rollback(:invalid_attempt_state)
    end
  end

  defp attemptable_snapshot?(%Operation{execution_status: "running", external_attempt_started_at: nil}), do: true
  defp attemptable_snapshot?(_operation), do: false

  defp attempt_exists?(operation_id) do
    Repo.exists?(from(event in UsageEvent, where: event.operation_id == ^operation_id))
  end

  defp attempt_arguments_current(%Operation{} = operation, %Task{} = task, %ExecutionRoute{} = route) do
    if operation.task_id == task.id and
         operation.task_contract_hash == Task.contract_hash(task) and
         operation.execution_route == ExecutionRoute.to_map(route) do
      :ok
    else
      {:error, :attempt_contract_mismatch}
    end
  end

  defp attempt_arguments_current(%Operation{}, _task, _route), do: {:error, :attempt_contract_mismatch}

  defp complete_attempt_reauthorization(%Operation{}, %Task{}, %ExecutionRoute{}, {:denied, reason}), do: {:error, reason}

  defp complete_attempt_reauthorization(%Operation{}, %Task{}, %ExecutionRoute{}, nil),
    do: {:error, :operation_authorization_changed}

  defp complete_attempt_reauthorization(
         %Operation{} = operation,
         %Task{} = task,
         %ExecutionRoute{} = route,
         {:prepared, preauthorization}
       ) do
    Governance.complete_operation_reauthorization(
      operation,
      task,
      :execute,
      preauthorization,
      lane: route.lane
    )
  end

  defp insert_attempt(locked, route, credential) do
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

    {:started, usage, credential}
  end

  @spec fail_before_attempt(Operation.t(), term()) :: :ok | {:error, term()}
  def fail_before_attempt(%Operation{} = operation, reason) do
    fn ->
      lock_preparation = Operation |> Repo.get(operation.id) |> prepare_operation_lock()
      locked = lock_prepared_operation(operation.id, lock_preparation)

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
      snapshot = Repo.get(Operation, operation.id)
      {lock_preparation, preauthorization} = prepare_delivery_reauthorization(snapshot)
      locked = lock_running_attempt!(operation.id, usage.id, lock_preparation)
      now = TimeHelpers.now()

      delivery_contract = current_delivery_contract(locked)
      deliver? = deliverable?(locked, delivery_contract, preauthorization)

      finish_usage!(usage.id, "succeeded", Map.put(metrics, :completed_at, now))
      locked = commit!(locked)

      if deliver? do
        {:ok, task, _route} = delivery_contract
        result = Repo.get_by!(Result, operation_id: locked.id)
        encoded_output = Storyarn.AI.Operations.Rules.CanonicalJSON.encode!(output)
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
      lock_preparation = Operation |> Repo.get(operation.id) |> prepare_operation_lock()
      locked = lock_running_attempt!(operation.id, usage.id, lock_preparation)
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
      fn ->
        lock_preparation = Operation |> Repo.get(operation.id) |> prepare_operation_lock()
        locked = lock_running_attempt!(operation.id, usage.id, lock_preparation)
        finish_unknown_transition(locked, usage.id, reason, metrics)
      end
      |> Repo.transaction()
      |> transaction_status()

    if result == :ok, do: emit_unknown(operation, reason)
    result
  end

  @doc "Recovers a worker interrupted without ever starting a second provider attempt."
  @spec recover_interrupted(pos_integer()) :: :ready | :ok | {:error, term()}
  def recover_interrupted(operation_id) do
    fn ->
      lock_preparation = Operation |> Repo.get(operation_id) |> prepare_operation_lock()
      operation_id |> lock_prepared_operation(lock_preparation) |> recover_locked()
    end
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
        lock_preparation = Operation |> Repo.get(operation_id) |> prepare_operation_lock()

        case lock_prepared_operation(operation_id, lock_preparation) do
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
    finish_unknown_transition(operation, usage.id, :worker_interrupted, %{})
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

  @spec request_cancellation(Scope.t(), pos_integer()) ::
          {:ok, Operation.t()} | {:error, atom()}
  def request_cancellation(%{user: %{id: actor_id}}, operation_id) do
    Repo.transaction(fn ->
      snapshot = get_actor_operation(operation_id, actor_id)
      lock_preparation = prepare_operation_lock(snapshot)
      operation = lock_prepared_operation(operation_id, lock_preparation)

      case operation do
        %Operation{execution_status: "queued"} -> cancel_locked(operation, :user_cancelled)
        %Operation{execution_status: "running"} -> request_running_cancellation(operation)
        %Operation{} -> operation
        nil -> Repo.rollback(:not_found)
      end
    end)
  end

  @doc """
  Releases an operation only while releasing it is still free.

  `request_cancellation/2` stamps `cancellation_requested_at` once a provider
  attempt has started, which charges the unit anyway and destroys the output the
  actor paid for. A surface that is merely walking away wants the opposite: give
  up the reservation if nothing has been spent, and otherwise leave the run
  strictly alone so its result stays readable inside its TTL.

  The decision cannot be made by reading the status first and cancelling second —
  a worker can stamp `external_attempt_started_at` in between — so it is taken
  here, under the same `FOR UPDATE` lock as the transition.

  No caller in `lib/` since Slice 7.1a.0 removed the first AI surface. Kept on
  purpose: every surface that can be closed mid-operation needs it, and it is the
  only place where "give up for free" is decided atomically. Covered by
  `test/storyarn/ai/kernel_spend_guarantees_test.exs`.
  """
  @spec release_if_unstarted(Scope.t(), pos_integer()) ::
          {:ok, :released | :started | :settled} | {:error, atom()}
  def release_if_unstarted(%{user: %{id: actor_id}}, operation_id) do
    Repo.transaction(fn ->
      snapshot = get_actor_operation(operation_id, actor_id)
      lock_preparation = prepare_operation_lock(snapshot)
      operation = lock_prepared_operation(operation_id, lock_preparation)

      case operation do
        %Operation{execution_status: "queued"} ->
          cancel_locked(operation, :user_cancelled)
          :released

        %Operation{execution_status: "running", external_attempt_started_at: nil} ->
          cancel_locked(operation, :user_cancelled)
          :released

        %Operation{execution_status: "running"} ->
          :started

        %Operation{} ->
          :settled

        nil ->
          Repo.rollback(:not_found)
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

  defp get_actor_operation(operation_id, actor_id) do
    Repo.one(
      from(operation in Operation,
        where: operation.id == ^operation_id and operation.actor_id == ^actor_id
      )
    )
  end

  defp prepare_operation_lock(nil), do: nil

  defp prepare_operation_lock(%Operation{} = snapshot) do
    Governance.prepare_operation_reauthorization(snapshot)
  end

  defp lock_prepared_operation(_operation_id, nil), do: nil

  defp lock_prepared_operation(operation_id, preparation) do
    case lock_operation(operation_id) do
      nil ->
        nil

      %Operation{} = operation ->
        case Governance.complete_operation_lock_preparation(operation, preparation) do
          :ok -> operation
          {:error, reason} -> Repo.rollback(reason)
        end
    end
  end

  defp lock_operation(id), do: Repo.one(from(operation in Operation, where: operation.id == ^id, lock: "FOR UPDATE"))

  defp operation_scope(%Operation{user_id: user_id}) when is_integer(user_id) do
    case Repo.get(User, user_id) do
      %User{} = user -> {:ok, %{user: user}}
      nil -> {:error, :actor_deleted}
    end
  end

  defp operation_scope(%Operation{}), do: {:error, :actor_deleted}

  defp lock_running_attempt!(operation_id, usage_id, lock_preparation) do
    operation = lock_prepared_operation(operation_id, lock_preparation) || Repo.rollback(:invalid_transition)
    usage = Repo.one(from(event in UsageEvent, where: event.id == ^usage_id, lock: "FOR UPDATE"))

    if usage && operation.execution_status == "running" &&
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

  defp current_task(task_id) when is_binary(task_id) do
    case Routing.get_task(task_id) do
      {:ok, task} -> task
      {:error, _reason} -> nil
    end
  end

  defp current_task(_task_id), do: nil

  defp prepare_delivery_reauthorization(%Operation{} = snapshot) do
    lock_preparation = Governance.prepare_operation_reauthorization(snapshot)

    preauthorization =
      with {:ok, task, _route} <- current_delivery_contract(snapshot),
           true <- is_nil(snapshot.cancellation_requested_at) do
        {:prepared, Governance.preauthorize_operation(snapshot, task, :execute, preparation: lock_preparation)}
      else
        _not_deliverable -> nil
      end

    {lock_preparation, preauthorization}
  end

  defp prepare_delivery_reauthorization(_snapshot), do: {nil, nil}

  defp current_delivery_contract(%Operation{} = operation) do
    with %Task{} = task <- current_task(operation.task_id),
         :ok <- task_contract_current(operation, task),
         {:ok, route} <- ExecutionRoute.from_map(operation.execution_route) do
      {:ok, task, route}
    else
      nil -> {:error, :unknown_task}
      {:error, reason} -> {:error, reason}
    end
  end

  defp deliverable?(locked, {:ok, task, route}, preauthorization) do
    with true <- is_nil(locked.cancellation_requested_at),
         {:ok, _decision} <- complete_delivery_reauthorization(locked, task, preauthorization),
         :ok <- Integrations.authorize_operation_consent(locked, task, route, lock: true) do
      true
    else
      _unauthorized -> false
    end
  end

  defp deliverable?(_locked, {:error, _reason}, _preauthorization), do: false

  defp complete_delivery_reauthorization(%Operation{} = operation, %Task{} = task, {:prepared, preauthorization}) do
    Governance.complete_operation_reauthorization(operation, task, :execute, preauthorization)
  end

  defp complete_delivery_reauthorization(%Operation{}, %Task{}, nil), do: {:error, :operation_authorization_changed}

  defp task_contract_current(operation, task) do
    if operation.task_contract_hash == Task.contract_hash(task),
      do: :ok,
      else: {:error, :task_contract_changed}
  end

  defp commit!(%Operation{settlement_status: "reserved"} = operation) do
    case ManagedSpend.commit(operation) do
      :ok -> operation |> Operation.transition_changeset(%{settlement_status: "committed"}) |> Repo.update!()
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp commit!(operation), do: operation

  defp release!(%Operation{settlement_status: "reserved"} = operation) do
    case ManagedSpend.release(operation) do
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

    Alerts.record(%{
      dedupe_key: "duplicate-attempt:#{operation.id}",
      kind: "duplicate_attempt",
      severity: "critical",
      workspace_id: operation.workspace_id,
      workspace_id_snapshot: operation.workspace_id_snapshot,
      operation_id: operation.id,
      metadata: %{"task_id" => operation.task_id}
    })
  end

  defp finish_unknown_transition(locked, usage_id, reason, metrics) do
    now = TimeHelpers.now()
    classification = classify(reason)

    finish_usage!(
      usage_id,
      "unknown",
      metrics |> Map.put(:completed_at, now) |> Map.put(:error_classification, classification)
    )

    Alerts.record(%{
      dedupe_key: "unknown-operation:#{locked.id}",
      kind: "unknown_operation",
      severity: "critical",
      workspace_id: locked.workspace_id,
      workspace_id_snapshot: locked.workspace_id_snapshot,
      operation_id: locked.id,
      metadata: %{
        "task_id" => locked.task_id,
        "error_classification" => classification
      }
    })

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
