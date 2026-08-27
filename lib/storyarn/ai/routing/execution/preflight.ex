defmodule Storyarn.AI.Routing.Execution.Preflight do
  @moduledoc "Resolves and discloses authorized route choices without creating an operation."

  alias Storyarn.AI.Context
  alias Storyarn.AI.Context.Package
  alias Storyarn.AI.ExecutionIntent
  alias Storyarn.AI.Governance
  alias Storyarn.AI.RouteOptions
  alias Storyarn.AI.RouteResolver
  alias Storyarn.AI.Routing.RateLimits
  alias Storyarn.AI.Routing.Rules.CanonicalJSON
  alias Storyarn.AI.Routing.Rules.ModelLimits
  alias Storyarn.AI.Task
  alias Storyarn.AI.TaskRegistry
  alias Storyarn.Repo

  @spec run(ExecutionIntent.t()) :: {:ok, map()} | {:error, atom() | Ecto.Changeset.t()}
  def run(%ExecutionIntent{} = intent) do
    with {:ok, task} <- TaskRegistry.fetch(intent.task_id),
         :ok <- validate_input(task, intent),
         {:ok, decision} <- Governance.authorize(intent, task, :execute),
         :ok <- RateLimits.check_preflight(intent.scope.user.id, task.id),
         {:ok, context} <- Context.prepare(intent.scope, task, intent),
         resolution = RouteResolver.preflight_options(decision, task),
         :ok <- routable(resolution) do
      issue_preflight(intent, task, resolution, context)
    else
      false -> {:error, :no_route}
      {:error, reason} -> {:error, reason}
    end
  end

  defp routable(%{routes: [], personal_choices: [], blocked_lanes: [%{reason: reason} | _rest]}), do: {:error, reason}

  defp routable(%{routes: [], personal_choices: []}), do: {:error, :no_route}
  defp routable(_resolution), do: :ok

  defp issue_preflight(intent, task, resolution, context) do
    fn ->
      {available_routes, blocked_routes} =
        partition_routes_by_context_limits(intent, task, resolution.routes, context)

      personal_choices = update_blocked_personal_choices(resolution.personal_choices, blocked_routes)

      if available_routes == [] and personal_choices == [] and blocked_routes != [] do
        Repo.rollback(preferred_context_limit_error(blocked_routes))
      end

      %{
        task_id: task.id,
        route_options: Enum.map(available_routes, &issue_route_option!(intent, task, &1, context)),
        personal_choices: Enum.map(personal_choices, &Map.delete(&1, :route)),
        personal_preference: update_blocked_personal_preference(resolution.personal_preference, personal_choices),
        blocked_lanes: resolution.blocked_lanes,
        context_disclosure: context_disclosure(context),
        result_destination: task.result_destination,
        result_ttl_seconds: task.result_ttl_seconds,
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

  defp context_disclosure(nil), do: nil
  defp context_disclosure(%{package: %Package{} = package}), do: Package.disclosure(package)

  defp unwrap_transaction({:ok, result}), do: {:ok, result}
  defp unwrap_transaction({:error, reason}), do: {:error, reason}
end
