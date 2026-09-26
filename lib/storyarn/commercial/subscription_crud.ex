defmodule Storyarn.Commercial.Billing.SubscriptionCrud do
  @moduledoc false

  alias Storyarn.Commercial.Billing.Plan
  alias Storyarn.Commercial.Billing.Subscription
  alias Storyarn.Commercial.Commands.Subscriptions, as: SubscriptionCommands
  alias Storyarn.Commercial.Queries.Subscriptions, as: SubscriptionQueries

  @doc """
  Gets the subscription of an account.
  """
  def get_subscription(user_id) do
    SubscriptionQueries.get_subscription(user_id)
  end

  @doc """
  Creates the subscription of an account (defaults to the free plan).
  """
  def create_subscription(%{id: _} = user, plan \\ Plan.default_plan()) do
    SubscriptionCommands.create_subscription(user, plan)
  end

  @doc """
  Updates the plan for a subscription (for future upgrades).
  """
  def update_plan(%Subscription{} = subscription, new_plan) do
    SubscriptionCommands.update_plan(subscription, new_plan)
  end

  @doc """
  Returns the plan key an account is entitled to.
  """
  def plan_for_user(user_id) do
    SubscriptionQueries.plan_for_user(user_id)
  end

  @doc """
  Returns the plan key a workspace takes its limits from: its owner's.
  """
  def plan_for(%{id: _} = workspace) do
    SubscriptionQueries.plan_for(workspace)
  end

  def plan_for_workspace_id(workspace_id) do
    SubscriptionQueries.plan_for_workspace_id(workspace_id)
  end

  @doc """
  Returns the plan key for each workspace ID in one query.

  Each workspace takes its owner's plan.
  """
  @spec plans_for_workspace_ids([pos_integer()]) :: %{pos_integer() => String.t()}
  def plans_for_workspace_ids(workspace_ids) when is_list(workspace_ids) do
    SubscriptionQueries.plans_for_workspace_ids(workspace_ids)
  end
end
