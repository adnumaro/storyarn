defmodule Storyarn.AI.Operations.Commands.Execute do
  @moduledoc "Idempotently creates and dispatches one authorized durable AI operation."

  import Ecto.Query

  alias Storyarn.AI.Alerts
  alias Storyarn.AI.Context
  alias Storyarn.AI.Context.Package
  alias Storyarn.AI.ExecutionIntent
  alias Storyarn.AI.ExecutionRoute
  alias Storyarn.AI.Executor
  alias Storyarn.AI.Governance
  alias Storyarn.AI.ManagedSpend
  alias Storyarn.AI.Operation
  alias Storyarn.AI.Operations.Adapters.Jobs.ExecutionQueue
  alias Storyarn.AI.Operations.RateLimits
  alias Storyarn.AI.Operations.Rules.CanonicalJSON
  alias Storyarn.AI.Result
  alias Storyarn.AI.Routing
  alias Storyarn.AI.Task
  alias Storyarn.Repo

  @idempotency_lock_namespace 981_005

  @spec run(ExecutionIntent.t()) :: {:ok, Operation.t()} | {:error, atom() | Ecto.Changeset.t()}
  def run(%ExecutionIntent{idempotency_key: nil}), do: {:error, :idempotency_key_required}
  def run(%ExecutionIntent{requested_route_ref: nil}), do: {:error, :route_ref_required}

  def run(%ExecutionIntent{} = intent) do
    with {:ok, task} <- Routing.fetch_task(intent.task_id),
         :ok <- validate_input(task, intent),
         {:ok, operation, created?} <- create_or_replay(intent, task) do
      maybe_run_inline(operation, task, created?)
    end
  end

  defp create_or_replay(intent, task) do
    fn -> replay_or_create(intent, task) end
    |> Repo.transaction()
    |> case do
      {:ok, {operation, created?}} ->
        {:ok, operation, created?}

      {:error, reason} ->
        maybe_alert_execution_block(intent, reason)
        {:error, reason}
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
    with {:ok, route_option_snapshot, route_snapshot} <- Routing.snapshot_route_option(intent, task),
         {:ok, intent_preauthorization} <-
           Governance.preauthorize_intent(intent, task, :execute, lane: route_snapshot.lane),
         # Authorization retains Workspace -> Project -> memberships/policy.
         # RouteOption comes afterwards so parent hard-delete can never hold
         # Workspace while this transaction holds RouteOption in reverse order.
         {:ok, route_option, _prelocked_route} <-
           Routing.lock_route_option(route_option_snapshot, intent, task),
         {:ok, current_task} <- Routing.fetch_task(task.id),
         {:ok, route} <-
           Routing.revalidate_route_option(
             route_option,
             route_option_snapshot,
             intent,
             current_task
           ),
         {:ok, decision} <-
           Governance.complete_intent_authorization(
             intent,
             current_task,
             :execute,
             intent_preauthorization,
             lane: route.lane
           ),
         true <- decision.policy_version == route.policy_version || {:error, :route_ref_stale},
         true <- Routing.route_current?(decision, current_task, route) || {:error, :route_ref_stale},
         :ok <- RateLimits.check_execution(intent.scope.user.id, current_task.id),
         {:ok, context} <- Context.prepare(intent.scope, current_task, intent),
         :ok <- context_matches_option(context, route_option),
         {:ok, input} <- context_input(intent.input, context) do
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
          task_id: current_task.id,
          task_contract_hash: route_option.task_contract_hash,
          capability: Atom.to_string(current_task.capability),
          idempotency_key: intent.idempotency_key,
          execution_status: "queued",
          settlement_status: settlement_status,
          subject_type: subject[:type],
          subject_id: subject[:id],
          subject_revision: subject[:revision],
          context_hash: context_hash(context),
          context_manifest: context_manifest(context),
          context_subject: context_subject(context),
          input_hash: intent.input_hash,
          input_schema_version: current_task.input_schema_version,
          output_schema_version: current_task.output_schema_version,
          prompt_version: current_task.prompt_version,
          context_version: current_task.context_version,
          result_type: current_task.result_type,
          result_destination: stringify_destination(current_task.result_destination),
          policy_decision: Governance.decision_to_map(decision),
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
        context_hash: context_hash(context),
        context_manifest: context_manifest(context),
        task_id: current_task.id,
        prompt_version: current_task.prompt_version,
        context_version: current_task.context_version,
        output_schema_version: current_task.output_schema_version
      })
      |> Repo.insert!()

      reserve!(operation, route)

      case Routing.consume_route_option(route_option, operation.id) do
        {:ok, _consumed} -> :ok
        {:error, changeset} -> Repo.rollback(changeset)
      end

      if current_task.execution_mode == :background do
        ExecutionQueue.enqueue!(operation.id)
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
    case ManagedSpend.reserve(operation) do
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

  defp context_matches_option(nil, %{context_hash: nil, context_manifest: nil, context_subject: nil}), do: :ok

  defp context_matches_option(%{package: %Package{} = package, subject: subject}, %{
         context_hash: hash,
         context_manifest: manifest,
         context_subject: persisted_subject
       }) do
    if package.hash == hash and Package.provenance(package) == manifest and subject == persisted_subject,
      do: :ok,
      else: {:error, :stale_context}
  end

  defp context_matches_option(_context, _option), do: {:error, :stale_context}

  defp context_input(input, nil), do: CanonicalJSON.encode(input)

  defp context_input(input, %{package: %Package{} = package}) do
    CanonicalJSON.encode(%{
      "request" => input,
      "context" => package.payload
    })
  end

  defp context_hash(nil), do: nil
  defp context_hash(%{package: %Package{hash: hash}}), do: hash

  defp context_manifest(nil), do: nil
  defp context_manifest(%{package: %Package{} = package}), do: Package.provenance(package)

  defp context_subject(nil), do: nil
  defp context_subject(%{subject: subject}), do: subject

  defp maybe_alert_execution_block(intent, reason)
       when reason in [
              :provider_daily_budget_exhausted,
              :provider_monthly_budget_exhausted,
              :workspace_provider_budget_exhausted
            ] do
    Alerts.record(%{
      dedupe_key: "provider-budget:#{intent.workspace_id}:#{reason}:#{Date.utc_today()}",
      kind: "provider_cost_spike",
      severity: "warning",
      workspace_id: intent.workspace_id,
      workspace_id_snapshot: intent.workspace_id,
      metadata: %{"reason" => Atom.to_string(reason), "task_id" => intent.task_id}
    })
  end

  defp maybe_alert_execution_block(intent, :allowance_projection_mismatch) do
    Alerts.record(%{
      dedupe_key: "allowance-projection:#{intent.workspace_id}:#{Date.utc_today()}",
      kind: "allowance_anomaly",
      severity: "critical",
      workspace_id: intent.workspace_id,
      workspace_id_snapshot: intent.workspace_id,
      metadata: %{"task_id" => intent.task_id}
    })
  end

  defp maybe_alert_execution_block(_intent, _reason), do: :ok
end
