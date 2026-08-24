defmodule Storyarn.Billing.SubscriptionCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Billing.Plan
  alias Storyarn.Billing.Subscription
  alias Storyarn.Repo

  @doc """
  Gets the subscription for a workspace.
  """
  def get_subscription(workspace_id) do
    Repo.get_by(Subscription, workspace_id: workspace_id)
  end

  @doc """
  Creates a subscription for a workspace (defaults to free plan).
  """
  def create_subscription(%{id: _} = workspace, plan \\ Plan.default_plan()) do
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
  def plan_for(%{id: _} = workspace) do
    plan_for_workspace_id(workspace.id)
  end

  def plan_for_workspace_id(workspace_id) do
    case get_subscription(workspace_id) do
      %Subscription{plan: plan} -> plan
      nil -> Plan.default_plan()
    end
  end

  @doc """
  Returns the plan key for each workspace ID in one query.

  Workspaces without a subscription use the default plan.
  """
  @spec plans_for_workspace_ids([pos_integer()]) :: %{pos_integer() => String.t()}
  def plans_for_workspace_ids(workspace_ids) when is_list(workspace_ids) do
    workspace_ids = Enum.uniq(workspace_ids)

    plans =
      if workspace_ids == [] do
        %{}
      else
        Subscription
        |> where([subscription], subscription.workspace_id in ^workspace_ids)
        |> select([subscription], {subscription.workspace_id, subscription.plan})
        |> Repo.all()
        |> Map.new()
      end

    Map.new(workspace_ids, fn workspace_id ->
      {workspace_id, Map.get(plans, workspace_id, Plan.default_plan())}
    end)
  end
end
