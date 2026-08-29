defmodule Storyarn.Commercial.Entitlements do
  @moduledoc """
  Resolves Commercial-owned commercial entitlements without applying them.

  Each product context remains responsible for measuring its operation and
  deciding how an entitlement constrains its own transaction.
  """

  alias Storyarn.Commercial.Billing.Plan
  alias Storyarn.Commercial.Queries.Subscriptions

  @spec limit(pos_integer(), atom()) :: non_neg_integer() | nil
  def limit(workspace_id, resource) when is_integer(workspace_id) and workspace_id > 0 and is_atom(resource) do
    workspace_id
    |> Subscriptions.plan_for_workspace_id()
    |> Plan.limit(resource)
  end

  def limit(_workspace_id, _resource), do: nil
end
