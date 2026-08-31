defmodule Storyarn.AI.ProviderBudget do
  @moduledoc "Compatibility contract for managed provider-budget commands."

  alias Storyarn.AI.ExecutionRoute
  alias Storyarn.AI.ManagedSpend.Commands.ProviderBudget, as: ProviderBudgetCommands
  alias Storyarn.AI.Operation
  alias Storyarn.Repo

  @spec reserve(Operation.t(), ExecutionRoute.t()) :: :ok | {:error, atom()}
  def reserve(operation, route), do: run_atomically(fn -> ProviderBudgetCommands.reserve(operation, route) end)

  @spec settle(Operation.t()) :: :ok | {:error, atom()}
  def settle(operation), do: run_atomically(fn -> ProviderBudgetCommands.settle(operation) end)

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
