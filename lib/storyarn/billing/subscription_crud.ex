defmodule Storyarn.Billing.SubscriptionCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Billing.{Plan, Subscription}
  alias Storyarn.Repo
  alias Storyarn.Workspaces.Workspace

  @doc """
  Gets the subscription for a workspace.
  """
  def get_subscription(workspace_id) do
    Repo.get_by(Subscription, workspace_id: workspace_id)
  end

  @doc """
  Creates a subscription for a workspace (defaults to free plan).
  """
  def create_subscription(%Workspace{} = workspace, plan \\ Plan.default_plan()) do
    %Subscription{}
    |> Subscription.create_changeset(%{workspace_id: workspace.id, plan: plan, status: "active"})
    |> Repo.insert()
  end

  @doc """
  Updates the plan for a subscription (for future upgrades).
  """
  def update_plan(%Subscription{} = subscription, new_plan) do
    subscription
    |> Subscription.update_changeset(%{plan: new_plan})
    |> Repo.update()
  end

  @doc """
  Returns the plan key for a workspace. Defaults to the default plan if no subscription exists.
  """
  def plan_for(%Workspace{} = workspace) do
    plan_for_workspace_id(workspace.id)
  end

  def plan_for_workspace_id(workspace_id) do
    case get_subscription(workspace_id) do
      %Subscription{plan: plan} -> plan
      nil -> Plan.default_plan()
    end
  end
end
