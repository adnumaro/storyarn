defmodule Storyarn.AI.ProviderBudget do
  @moduledoc "Compatibility contract for managed provider-budget commands."

  alias Storyarn.AI.ExecutionRoute
  alias Storyarn.AI.ManagedSpend.Commands.ProviderBudget, as: ProviderBudgetCommands
  alias Storyarn.AI.Operation

  @spec reserve(Operation.t(), ExecutionRoute.t()) :: :ok | {:error, atom()}
  defdelegate reserve(operation, route), to: ProviderBudgetCommands

  @spec settle(Operation.t()) :: :ok | {:error, atom()}
  defdelegate settle(operation), to: ProviderBudgetCommands
end
