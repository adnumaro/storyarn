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

  # Read-only preflight projection: a paused or exhausted account blocks the
  # managed choice before an operation exists, instead of failing at reserve —
  # and says WHICH, because "out of units" and "paused by an owner" are
  # different situations for the actor.
  @impl true
  def preflight_status(:managed, workspace_id, units) do
    case Allowance.projection(workspace_id) do
      %{status: "active", available_units: available} when available >= units -> :ok
      %{status: "active"} -> {:error, :allowance_exhausted}
      %{status: "paused"} -> {:error, :allowance_paused}
      _no_account -> {:error, :allowance_unavailable}
    end
  end

  def preflight_status(_lane, _workspace_id, _units), do: {:error, :allowance_unavailable}

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
