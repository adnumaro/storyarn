defmodule Storyarn.AI.Settlement.Managed do
  @moduledoc "Managed settlement adapter backed by promotional allowance and provider budgets."
  @behaviour Storyarn.AI.SettlementAdapter

  alias Storyarn.AI.Allowance
  alias Storyarn.AI.ExecutionRoute
  alias Storyarn.AI.Operation
  alias Storyarn.AI.ProviderBudget

  @impl true
  def available?(:managed), do: true
  def available?(_lane), do: false

  @impl true
  def reserve(%Operation{} = operation) do
    with {:ok, route} <- ExecutionRoute.from_map(operation.execution_route),
         :ok <- Allowance.reserve(operation) do
      ProviderBudget.reserve(operation, route)
    end
  end

  @impl true
  def commit(%Operation{} = operation) do
    with :ok <- Allowance.commit(operation) do
      ProviderBudget.settle(operation)
    end
  end

  @impl true
  def release(%Operation{} = operation) do
    with :ok <- Allowance.release(operation) do
      ProviderBudget.settle(operation)
    end
  end
end
