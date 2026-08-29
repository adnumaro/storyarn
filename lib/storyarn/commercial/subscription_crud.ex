defmodule Storyarn.Commercial.Billing.SubscriptionCrud do
  @moduledoc false

  alias Storyarn.Commercial.Billing.Plan
  alias Storyarn.Commercial.Billing.Subscription
  alias Storyarn.Commercial.Commands.Subscriptions, as: SubscriptionCommands
  alias Storyarn.Commercial.Queries.Subscriptions, as: SubscriptionQueries

  @doc """
  Gets the subscription for a workspace.
  """
  def get_subscription(workspace_id) do
    SubscriptionQueries.get_subscription(workspace_id)
  end

  @doc """
  Creates a subscription for a workspace (defaults to free plan).
  """
  def create_subscription(%{id: _} = workspace, plan \\ Plan.default_plan()) do
    SubscriptionCommands.create_subscription(workspace, plan)
  end

  @doc """
  Updates the plan for a subscription (for future upgrades).
  """
  def update_plan(%Subscription{} = subscription, new_plan) do
    SubscriptionCommands.update_plan(subscription, new_plan)
  end

  @doc """
  Returns the plan key for a workspace. Defaults to the default plan if no subscription exists.
  """
  def plan_for(%{id: _} = workspace) do
    SubscriptionQueries.plan_for(workspace)
  end

  def plan_for_workspace_id(workspace_id) do
    SubscriptionQueries.plan_for_workspace_id(workspace_id)
  end

  @doc """
  Returns the plan key for each workspace ID in one query.

  Workspaces without a subscription use the default plan.
  """
  @spec plans_for_workspace_ids([pos_integer()]) :: %{pos_integer() => String.t()}
  def plans_for_workspace_ids(workspace_ids) when is_list(workspace_ids) do
    SubscriptionQueries.plans_for_workspace_ids(workspace_ids)
  end
end
