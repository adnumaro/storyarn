defmodule Storyarn.AI.Execution do
  @moduledoc "Preflight and idempotent operation-creation pipeline."

  import Ecto.Query

  alias Storyarn.AI.Alerts
  alias Storyarn.Shared.CanonicalJSON
  alias Storyarn.AI.Context
  alias Storyarn.AI.Context.ModelLimits
  alias Storyarn.AI.Context.Package
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
         {:ok, decision} <- PolicyDecision.authorize(intent, task, :execute),
         :ok <- RateLimiter.check_ai_preflight(intent.scope.user.id, task.id),
         {:ok, context} <- Context.prepare(intent.scope, task, intent),
         resolution = RouteResolver.preflight_options(decision, task),
         true <- resolution.routes != [] or resolution.personal_choices != [] do
      issue_preflight(
        intent,
        task,
        resolution.routes,
        resolution.personal_choices,
        resolution.personal_preference,
        context
      )
    else
      false -> {:error, :no_route}
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
      {:ok, {operation, created?}} ->
        {:ok, operation, created?}

      {:error, reason} ->
        maybe_alert_execution_block(intent, reason)
        {:error, reason}
    end
  end

  defp issue_preflight(intent, task, routes, personal_choices, personal_preference, context) do
    fn ->
      {available_routes, blocked_routes} =
        partition_routes_by_context_limits(intent, task, routes, context)

      personal_choices = update_blocked_personal_choices(personal_choices, blocked_routes)

      if available_routes == [] and personal_choices == [] and blocked_routes != [] do
        Repo.rollback(preferred_context_limit_error(blocked_routes))
      end

      %{
        task_id: task.id,
        route_options: Enum.map(available_routes, &issue_route_option!(intent, task, &1, context)),
        personal_choices: Enum.map(personal_choices, &Map.delete(&1, :route)),
        personal_preference: update_blocked_personal_preference(personal_preference, personal_choices),
        context_disclosure: context_disclosure(context),
        result_destination: task.result_destination,
        operation_created: false
      }
    end
    |> Repo.transaction()
    |> unwrap_transaction()
  end

  defp partition_routes_by_context_limits(intent, task, routes, context) do
    routes
    |> Enum.reduce(
      {[], []},
      &partition_route_by_context_limit(&1, &2, intent, task, context)
    )
    |> then(fn {available, blocked} ->
      {Enum.reverse(available), Enum.reverse(blocked)}
    end)
  end

  defp partition_route_by_context_limit(route, {available, blocked}, intent, task, context) do
    case ModelLimits.validate_context(task, route, intent.input, context) do
      :ok -> {[route | available], blocked}
      {:error, reason} -> partition_blocked_route(route, reason, available, blocked)
    end
  end

  defp partition_blocked_route(route, reason, available, blocked) do
    if ModelLimits.context_limit_error?(reason) do
      {available, [{route, reason} | blocked]}
    else
      Repo.rollback(reason)
    end
  end

  defp update_blocked_personal_choices(personal_choices, blocked_routes) do
    Enum.map(personal_choices, fn choice ->
      case blocked_route_reason(choice[:route], blocked_routes) do
        nil -> choice
        reason -> Map.put(choice, :status, ModelLimits.public_status(reason))
      end
    end)
  end

  defp blocked_route_reason(nil, _blocked_routes), do: nil

  defp blocked_route_reason(route, blocked_routes) do
    Enum.find_value(blocked_routes, fn
      {^route, reason} -> reason
      {_other_route, _reason} -> nil
    end)
  end

  defp update_blocked_personal_preference(personal_preference, personal_choices) do
    case Enum.find(personal_choices, & &1.preferred) do
      %{status: status} -> Map.put(personal_preference, :status, status)
      nil -> personal_preference
    end
  end

  defp preferred_context_limit_error(blocked_routes) do
    reasons = MapSet.new(blocked_routes, fn {_route, reason} -> reason end)

    Enum.find(
      [
        :model_context_window_exceeded,
        :model_output_limit_exceeded,
        :model_context_limits_unavailable
      ],
      &MapSet.member?(reasons, &1)
    )
  end

  defp issue_route_option!(intent, task, route, context) do
    case RouteOptions.issue(intent, task, route, context) do
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
         {:ok, context} <- Context.prepare(intent.scope, task, intent),
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
          task_id: task.id,
          task_contract_hash: Task.contract_hash(task),
          capability: Atom.to_string(task.capability),
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
        context_hash: context_hash(context),
        context_manifest: context_manifest(context),
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

  defp context_disclosure(nil), do: nil
  defp context_disclosure(%{package: %Package{} = package}), do: Package.disclosure(package)

  defp unwrap_transaction({:ok, result}), do: {:ok, result}
  defp unwrap_transaction({:error, reason}), do: {:error, reason}

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
