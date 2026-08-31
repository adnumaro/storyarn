defmodule Storyarn.AI.ManagedSpend.Commands.Settlement do
  @moduledoc "Managed allowance and provider-budget settlement implementation."

  alias Storyarn.AI.ExecutionRoute
  alias Storyarn.AI.ManagedSpend.Commands.Allowance
  alias Storyarn.AI.ManagedSpend.Commands.ProviderBudget
  alias Storyarn.AI.ManagedSpend.Queries.Allowance, as: AllowanceQueries
  alias Storyarn.AI.Operation
  alias Storyarn.Repo

  @spec available?(atom()) :: boolean()
  def available?(:managed), do: true
  def available?(_lane), do: false

  @spec preflight_status(atom(), pos_integer(), pos_integer()) :: :ok | {:error, atom()}
  def preflight_status(:managed, workspace_id, units) do
    case AllowanceQueries.projection(workspace_id) do
      %{status: "active", available_units: available} when available >= units -> :ok
      %{status: "active"} -> {:error, :allowance_exhausted}
      %{status: "paused"} -> {:error, :allowance_paused}
      _no_account -> {:error, :allowance_unavailable}
    end
  end

  def preflight_status(_lane, _workspace_id, _units), do: {:error, :allowance_unavailable}

  @spec reserve(Operation.t()) :: :ok | {:error, atom()}
  def reserve(%Operation{} = operation) do
    run_atomically(fn -> reserve_locked(operation) end)
  end

  defp reserve_locked(operation) do
    with {:ok, route} <- ExecutionRoute.from_map(operation.execution_route),
         :ok <- Allowance.reserve(operation) do
      ProviderBudget.reserve(operation, route)
    end
  end

  @spec commit(Operation.t()) :: :ok | {:error, atom()}
  def commit(%Operation{} = operation) do
    run_atomically(fn -> commit_locked(operation) end)
  end

  defp commit_locked(operation) do
    with :ok <- Allowance.commit(operation) do
      ProviderBudget.settle(operation)
    end
  end

  @spec release(Operation.t()) :: :ok | {:error, atom()}
  def release(%Operation{} = operation) do
    run_atomically(fn -> release_locked(operation) end)
  end

  defp release_locked(operation) do
    with :ok <- Allowance.release(operation) do
      ProviderBudget.settle(operation)
    end
  end

  defp run_atomically(fun) do
    if Repo.in_transaction?() do
      fun.()
    else
      case Repo.transaction(fn -> rollback_on_error(fun.()) end) do
        {:ok, result} -> result
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp rollback_on_error({:error, reason}), do: Repo.rollback(reason)
  defp rollback_on_error(result), do: result
end
