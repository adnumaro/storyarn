defmodule Storyarn.AI.Execution do
  @moduledoc "Preflight and idempotent operation-creation pipeline."

  import Ecto.Query

  alias Storyarn.AI.CanonicalJSON
  alias Storyarn.AI.ExecutionIntent
  alias Storyarn.AI.ExecutionRoute
  alias Storyarn.AI.Executor
  alias Storyarn.AI.Operation
  alias Storyarn.AI.PolicyDecision
  alias Storyarn.AI.Result
  alias Storyarn.AI.RouteOptions
  alias Storyarn.AI.RouteResolver
  alias Storyarn.AI.Settlement
  alias Storyarn.AI.Task
  alias Storyarn.AI.TaskRegistry
  alias Storyarn.RateLimiter
  alias Storyarn.Repo
  alias Storyarn.Workers.AIExecutionWorker

  @idempotency_lock_namespace 981_005

  @spec preflight(ExecutionIntent.t()) :: {:ok, map()} | {:error, atom() | Ecto.Changeset.t()}
  def preflight(%ExecutionIntent{} = intent) do
    with {:ok, task} <- TaskRegistry.fetch(intent.task_id),
         :ok <- validate_input(task, intent),
         :ok <- RateLimiter.check_ai_preflight(intent.scope.user.id, task.id),
         {:ok, decision} <- PolicyDecision.authorize(intent, task, :execute),
         routes when routes != [] <- RouteResolver.routes(decision, task) do
      issue_preflight(intent, task, routes)
    else
      [] -> {:error, :no_route}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec execute(ExecutionIntent.t()) :: {:ok, Operation.t()} | {:error, atom() | Ecto.Changeset.t()}
  def execute(%ExecutionIntent{idempotency_key: nil}), do: {:error, :idempotency_key_required}
  def execute(%ExecutionIntent{requested_route_ref: nil}), do: {:error, :route_ref_required}

  def execute(%ExecutionIntent{} = intent) do
    with {:ok, task} <- TaskRegistry.fetch(intent.task_id),
         :ok <- validate_input(task, intent),
         {:ok, operation, created?} <- create_or_replay(intent, task) do
      maybe_run_inline(operation, task, created?)
    end
  end

  defp create_or_replay(intent, task) do
    fn -> replay_or_create(intent, task) end
    |> Repo.transaction()
    |> case do
      {:ok, {operation, created?}} -> {:ok, operation, created?}
      {:error, reason} -> {:error, reason}
    end
  end

  defp issue_preflight(intent, task, routes) do
    fn ->
      %{
        task_id: task.id,
        route_options: Enum.map(routes, &issue_route_option!(intent, task, &1)),
        result_destination: task.result_destination,
        operation_created: false
      }
    end
    |> Repo.transaction()
    |> unwrap_transaction()
  end

  defp issue_route_option!(intent, task, route) do
    case RouteOptions.issue(intent, task, route) do
      {:ok, option} -> option
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp replay_or_create(intent, task) do
    lock_idempotency!(intent, task)

    case idempotent_operation(intent, task) do
      %Operation{} = existing -> replay(existing, intent)
      nil -> create_operation(intent, task)
    end
  end

  defp replay(existing, intent) do
    if same_intent?(existing, intent), do: {existing, false}, else: Repo.rollback(:idempotency_conflict)
  end

  defp create_operation(intent, task) do
    with {:ok, route_option, route} <- RouteOptions.resolve_locked(intent, task),
         {:ok, decision} <-
           PolicyDecision.authorize(intent, task, :execute, lane: route.lane, lock_policy: true),
         true <- decision.policy_version == route.policy_version || {:error, :route_ref_stale},
         true <- RouteResolver.current?(decision, task, route) || {:error, :route_ref_stale},
         :ok <- RateLimiter.check_ai_execution(intent.scope.user.id, task.id),
         {:ok, input} <- CanonicalJSON.encode(intent.input) do
      subject = intent.subject || %{}
      settlement_status = if route.lane == :managed, do: "reserved", else: "not_applicable"

      operation =
        %Operation{}
        |> Operation.create_changeset(%{
          user_id: intent.scope.user.id,
          actor_id: intent.scope.user.id,
          workspace_id: intent.workspace_id,
          workspace_id_snapshot: intent.workspace_id,
          project_id: intent.project_id,
          project_id_snapshot: intent.project_id,
          route_option_id: route_option.id,
          task_id: task.id,
          task_contract_hash: Task.contract_hash(task),
          capability: Atom.to_string(task.capability),
          idempotency_key: intent.idempotency_key,
          execution_status: "queued",
          settlement_status: settlement_status,
          subject_type: subject[:type],
          subject_id: subject[:id],
          subject_revision: subject[:revision],
          input_hash: intent.input_hash,
          input_schema_version: task.input_schema_version,
          output_schema_version: task.output_schema_version,
          prompt_version: task.prompt_version,
          context_version: task.context_version,
          result_type: task.result_type,
          result_destination: stringify_destination(task.result_destination),
          policy_decision: PolicyDecision.to_map(decision),
          execution_route: ExecutionRoute.to_map(route)
        })
        |> Repo.insert!()

      %Result{}
      |> Result.create_changeset(%{
        operation_id: operation.id,
        user_id: intent.scope.user.id,
        actor_id: intent.scope.user.id,
        workspace_id: intent.workspace_id,
        project_id: intent.project_id,
        input_encrypted: input,
        input_hash: intent.input_hash,
        task_id: task.id,
        prompt_version: task.prompt_version,
        context_version: task.context_version,
        output_schema_version: task.output_schema_version
      })
      |> Repo.insert!()

      reserve!(operation, route)

      case RouteOptions.consume(route_option, operation.id) do
        {:ok, _consumed} -> :ok
        {:error, changeset} -> Repo.rollback(changeset)
      end

      if task.execution_mode == :background do
        %{operation_id: operation.id}
        |> AIExecutionWorker.new()
        |> Oban.insert!()
      end

      {operation, true}
    else
      false -> Repo.rollback(:route_ref_stale)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp idempotent_operation(intent, task) do
    Repo.one(
      from(operation in Operation,
        where:
          operation.actor_id == ^intent.scope.user.id and
            operation.task_id == ^task.id and
            operation.idempotency_key == ^intent.idempotency_key,
        lock: "FOR UPDATE"
      )
    )
  end

  defp lock_idempotency!(intent, task) do
    lock_key = :erlang.phash2({intent.scope.user.id, task.id, intent.idempotency_key}, 2_147_483_647)
    Repo.query!("SELECT pg_advisory_xact_lock($1, $2)", [@idempotency_lock_namespace, lock_key])
  end

  defp same_intent?(operation, intent) do
    subject = intent.subject || %{}

    operation.workspace_id_snapshot == intent.workspace_id and
      operation.project_id_snapshot == intent.project_id and
      operation.input_hash == intent.input_hash and
      operation.subject_type == subject[:type] and
      operation.subject_id == subject[:id] and
      operation.subject_revision == subject[:revision]
  end

  defp reserve!(operation, %ExecutionRoute{lane: :managed}) do
    case Settlement.reserve(operation) do
      :ok -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp reserve!(_operation, _route), do: :ok

  defp maybe_run_inline(operation, task, true) when task.execution_mode == :inline do
    :ok = Executor.run(operation.id)
    {:ok, Repo.get!(Operation, operation.id)}
  end

  defp maybe_run_inline(operation, _task, _created?), do: {:ok, operation}

  defp validate_input(task, intent) do
    with :ok <- Task.validate_input(task, intent.input),
         {:ok, encoded} <- CanonicalJSON.encode(intent.input),
         actual_hash = :sha256 |> :crypto.hash(encoded) |> Base.encode16(case: :lower),
         true <- actual_hash == intent.input_hash || {:error, :input_hash_mismatch},
         true <- byte_size(encoded) <= task.max_input_bytes do
      :ok
    else
      false -> {:error, :input_too_large}
      {:error, reason} -> {:error, reason}
    end
  end

  defp stringify_destination(destination) do
    Map.new(destination, fn {key, value} ->
      {Atom.to_string(key), if(is_atom(value), do: Atom.to_string(value), else: value)}
    end)
  end

  defp unwrap_transaction({:ok, result}), do: {:ok, result}
  defp unwrap_transaction({:error, reason}), do: {:error, reason}
end
