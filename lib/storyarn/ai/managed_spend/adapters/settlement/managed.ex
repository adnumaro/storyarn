defmodule Storyarn.AI.Settlement.Managed do
  @moduledoc "Managed settlement adapter backed by promotional allowance and provider budgets."
  @behaviour Storyarn.AI.SettlementAdapter

  alias Storyarn.AI.ManagedSpend.Commands.Settlement
  alias Storyarn.AI.Operation

  @impl true
  defdelegate available?(lane), to: Settlement

  # Read-only preflight projection: a paused or exhausted account blocks the
  # managed choice before an operation exists, instead of failing at reserve —
  # and says WHICH, because "out of units" and "paused by an owner" are
  # different situations for the actor.
  @impl true
  defdelegate preflight_status(lane, workspace_id, units), to: Settlement

  @impl true
  def reserve(%Operation{} = operation), do: Settlement.reserve(operation)

  @impl true
  def commit(%Operation{} = operation), do: Settlement.commit(operation)

  @impl true
  def release(%Operation{} = operation), do: Settlement.release(operation)
end
